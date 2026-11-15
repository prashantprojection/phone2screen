import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/media_source_type.dart';
import '../models/session_phase.dart';
import '../models/signaling_data.dart';
import 'discovery_provider.dart';
import 'platform_provider.dart';
import 'preferences_provider.dart';
import 'session_signaling_bridge.dart';
import 'session_state.dart';
import 'settings_provider.dart';

class _SenderAttempt {
  bool hadConnectedStream = false;
  bool dropHandled = false;
}

/// Executes Sender casting, source-switching, auto-reconnect, and teardown.
class SessionSenderFlow {
  final SessionSignalingBridge bridge;
  final Duration reconnectDelay;
  StreamSubscription<RTCPeerConnectionState>? _connStateSub;

  SessionSenderFlow(this.bridge, {this.reconnectDelay = const Duration(milliseconds: 650)});

  /// Connects to [target] over `/ws`, captures local media, and sends offer.
  Future<void> connectAndStream(
    SessionContext ctx,
    SignalingData target, {
    String? pin,
    required Future<void> Function(String? err) onHostPeerFailed,
  }) => _runConnectAttempt(ctx, target, pin: pin, onHostPeerFailed: onHostPeerFailed, retryCount: 0);

  Future<void> _runConnectAttempt(
    SessionContext ctx,
    SignalingData target, {
    String? pin,
    required Future<void> Function(String? err) onHostPeerFailed,
    required int retryCount,
    int? expectedEpoch,
  }) async {
    final ref = ctx.sessionRef;
    if (expectedEpoch != null && ctx.epoch != expectedEpoch) return;
    final epoch = ctx.bumpEpoch();
    ctx.isHosting = false;
    ctx.activeSessionId = target.sessionId;
    await teardownResources(ctx, clearUi: false);
    if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

    final preservedName = ctx.currentState.connectedPeerName;
    ctx.currentState = ctx.currentState.reset(
      phase: retryCount > 0 ? .reconnecting : .connecting,
      activeEndpoint: target,
      connectedPeerName: retryCount > 0 && preservedName != null ? preservedName : target.deviceName,
    );

    final attempt = _SenderAttempt();
    _connStateSub = ctx.webrtc.onConnectionState.listen((connState) {
      if (ctx.epoch != epoch) return;
      if (connState == .RTCPeerConnectionStateConnected ||
          (connState == .RTCPeerConnectionStateDisconnected && ctx.currentState.phase == .streaming)) {
        attempt.hadConnectedStream = true;
      }
    });

    try {
      await ref.read(lanDiscoveryServiceProvider).stopListening();
      final config = ref.read(streamConfigProvider);
      final localStream = await ctx.mediaCapture.startCapture(config);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }
      ctx.currentState = ctx.currentState.copyWith(localStream: localStream);

      final deviceName = await ref.read(platformServiceProvider).resolveDeviceName();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      Future<void> onDrop(String msg) => _handleUnexpectedDrop(
        ctx, target, pin: pin, onHostPeerFailed: onHostPeerFailed,
        epoch: epoch, retryCount: retryCount, attempt: attempt, errorMessage: msg,
      );

      final client = ref.read(signalingClientServiceProvider);
      bridge.wireWebRtc(
        ctx,
        onHostPeerFailed: onHostPeerFailed,
        onSenderPeerFailed: (err) => onDrop(err ?? 'WebRTC peer connection failed.'),
      );
      await bridge.listenClient(
        client,
        onMessage: (m) => bridge.dispatchClientMessage(
          m,
          webrtc: ctx.webrtc,
          isActive: () => ctx.epoch == epoch && ctx.isNotifierMounted && !ctx.isHosting,
          onWelcome: (name) => ctx.currentState = ctx.currentState.copyWith(connectedPeerName: name),
          onError: (reason) => teardown(ctx, .failed, errorMessage: reason),
          onBye: () => teardown(ctx, .idle),
        ),
        onDisconnected: () => onDrop('Disconnected from receiver.'),
      );
      await client.connect(target: target, clientDeviceName: deviceName, pin: pin);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      unawaited(ref.read(lastEndpointProvider.notifier).setLastEndpoint(target));

      final offer = await ctx.webrtc.createOfferForStream(localStream, maxBitrateBps: config.videoBitrate);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      bridge.sendOffer(offer, client: client, sessionId: target.sessionId);
    } catch (e) {
      if (ctx.epoch == epoch && ctx.isNotifierMounted) {
        await teardown(ctx, .failed, errorMessage: friendlySessionError(e));
      }
    }
  }

  Future<void> _handleUnexpectedDrop(
    SessionContext ctx,
    SignalingData target, {
    required String? pin,
    required Future<void> Function(String? err) onHostPeerFailed,
    required int epoch,
    required int retryCount,
    required _SenderAttempt attempt,
    required String errorMessage,
  }) async {
    if (attempt.dropHandled || ctx.epoch != epoch || !ctx.isNotifierMounted || ctx.isHosting) return;
    attempt.dropHandled = true;

    final wasStreaming = attempt.hadConnectedStream || ctx.currentState.phase == .streaming;
    if (!wasStreaming || retryCount >= 1) {
      await teardown(ctx, .failed, errorMessage: errorMessage);
      return;
    }

    // Bump epoch immediately so intentional disconnect() aborts any pending retry.
    final reconnectEpoch = ctx.bumpEpoch();
    final endpoint = ctx.currentState.activeEndpoint ?? target;
    final peerName = ctx.currentState.connectedPeerName ?? target.deviceName;
    ctx.activeSessionId = null;
    ctx.currentState = ctx.currentState.reset(phase: .reconnecting, activeEndpoint: endpoint, connectedPeerName: peerName);
    await teardownResources(ctx, clearUi: false);
    if (ctx.epoch != reconnectEpoch || !ctx.isNotifierMounted || ctx.isHosting) return;

    await Future<void>.delayed(reconnectDelay);
    if (ctx.epoch != reconnectEpoch || !ctx.isNotifierMounted || ctx.isHosting) return;

    final resolvedTarget = await _resolveReconnectTarget(ctx, endpoint, expectedEpoch: reconnectEpoch);
    if (resolvedTarget == null || ctx.epoch != reconnectEpoch || !ctx.isNotifierMounted || ctx.isHosting) return;

    await _runConnectAttempt(
      ctx, resolvedTarget, pin: pin, onHostPeerFailed: onHostPeerFailed,
      retryCount: retryCount + 1, expectedEpoch: reconnectEpoch,
    );
  }

  Future<SignalingData?> _resolveReconnectTarget(
    SessionContext ctx,
    SignalingData fallback, {
    required int expectedEpoch,
  }) async {
    try {
      final usbPeers = await ctx.sessionRef
          .read(usbBridgeServiceProvider)
          .probeLoopbackReceivers(timeout: const Duration(milliseconds: 250));
      if (ctx.epoch != expectedEpoch || !ctx.isNotifierMounted || ctx.isHosting) return null;
      if (usbPeers.isNotEmpty) {
        final matching = usbPeers.where((p) => p.endpoint.sessionId == fallback.sessionId);
        return (matching.firstOrNull ?? usbPeers.first).endpoint;
      }
    } catch (_) {
      // Fall back to original target when USB loopback probe fails.
    }
    return fallback;
  }

  /// Switches camera/screen source and replaces active video track in-place.
  Future<void> changeSource(
    SessionContext ctx,
    MediaSourceType source, {
    String? desktopSourceId,
  }) async {
    final ref = ctx.sessionRef;
    ref.read(streamConfigProvider.notifier)
      ..setSourceType(source)
      ..setDesktopSourceId(source == .screen ? desktopSourceId : null);
    final phase = ctx.currentState.phase;
    final activeCapture = phase == .streaming || phase == .connecting ||
        (ctx.currentState.isWebBroadcast && phase == .hosting);
    if (!activeCapture) return;

    final epoch = ctx.epoch;
    try {
      final updated = ref.read(streamConfigProvider);
      final newStream = await ctx.mediaCapture.startCapture(updated);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }
      ctx.mediaCapture.setMicMuted(ctx.currentState.isMicMuted);
      final tracks = newStream.getVideoTracks();
      if (ctx.currentState.isVideoPaused) {
        for (final track in tracks) {
          track.enabled = false;
        }
      }
      if (tracks.isNotEmpty) await ctx.webrtc.replaceVideoTrack(tracks.first);
      await ctx.webrtc.applyBitrateLimit(updated.videoBitrate);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      ctx.currentState = ctx.currentState.copyWith(localStream: newStream, isTorchOn: false, clearError: true);
    } catch (e) {
      if (!ctx.isNotifierMounted) return;
      ctx.currentState = ctx.currentState.copyWith(
        errorMessage: friendlySessionError(e),
        clearLocalStream: ctx.mediaCapture.activeStream == null,
      );
    }
  }

  /// Tears down Sender media, signaling, and WebRTC state cleanly.
  Future<void> teardown(SessionContext ctx, SessionPhase nextPhase, {String? errorMessage, bool stopListening = false}) async {
    ctx.bumpEpoch();
    ctx.activeSessionId = null;
    await teardownResources(ctx, clearUi: true, nextPhase: nextPhase, errorMessage: errorMessage, stopListening: stopListening);
  }

  /// Releases Sender transport and capture resources.
  Future<void> teardownResources(
    SessionContext ctx, {
    required bool clearUi,
    SessionPhase nextPhase = .idle,
    String? errorMessage,
    bool stopListening = false,
  }) async {
    final connSub = _connStateSub;
    _connStateSub = null;
    await connSub?.cancel();

    final ref = ctx.sessionRef;
    if (clearUi && ctx.isNotifierMounted) {
      ctx.currentState = ctx.currentState.reset(phase: nextPhase, errorMessage: errorMessage);
    }
    await bridge.cancelSessionSubs();
    await ctx.webrtc.close();
    await ctx.mediaCapture.stopCapture();
    await ref.read(signalingClientServiceProvider).disconnect();
    if (stopListening) await ref.read(lanDiscoveryServiceProvider).stopListening();
  }
}
