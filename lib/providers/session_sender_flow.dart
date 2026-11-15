import '../models/media_source_type.dart';
import '../models/session_phase.dart';
import '../models/signaling_data.dart';
import 'discovery_provider.dart';
import 'platform_provider.dart';
import 'session_signaling_bridge.dart';
import 'session_state.dart';
import 'settings_provider.dart';

/// Executes Sender casting, source-switching, and teardown workflows.
class SessionSenderFlow {
  final SessionSignalingBridge bridge;

  const SessionSenderFlow(this.bridge);

  /// Connects to [target] over `/ws`, captures local media, and sends offer.
  Future<void> connectAndStream(
    SessionContext ctx,
    SignalingData target, {
    String? pin,
    required Future<void> Function(String? err) onHostPeerFailed,
  }) async {
    final ref = ctx.sessionRef;
    final epoch = ctx.bumpEpoch();
    ctx.isHosting = false;
    ctx.activeSessionId = target.sessionId;
    await teardownResources(ctx, clearUi: false);
    if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

    ctx.currentState = ctx.currentState.reset(
      phase: .connecting,
      activeEndpoint: target,
      connectedPeerName: target.deviceName,
    );

    try {
      await ref.read(lanDiscoveryServiceProvider).stopListening();
      final config = ref.read(streamConfigProvider);
      final localStream = await ctx.mediaCapture.startCapture(config);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }
      ctx.currentState = ctx.currentState.copyWith(localStream: localStream);

      final deviceName = await ref
          .read(platformServiceProvider)
          .resolveDeviceName();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      final client = ref.read(signalingClientServiceProvider);
      bridge.wireWebRtc(
        ctx,
        onHostPeerFailed: onHostPeerFailed,
        onSenderPeerFailed: (err) => teardown(ctx, .failed, errorMessage: err),
      );
      await bridge.listenClient(
        client,
        onMessage: (m) => bridge.dispatchClientMessage(
          m,
          webrtc: ctx.webrtc,
          isActive: () =>
              ctx.epoch == epoch && ctx.isNotifierMounted && !ctx.isHosting,
          onWelcome: (name) => ctx.currentState = ctx.currentState.copyWith(
            connectedPeerName: name,
          ),
          onError: (reason) => teardown(ctx, .failed, errorMessage: reason),
          onBye: () => teardown(ctx, .idle),
        ),
        onDisconnected: () async {
          if (ctx.epoch == epoch && ctx.isNotifierMounted && !ctx.isHosting) {
            await teardown(
              ctx,
              .failed,
              errorMessage: 'Disconnected from receiver.',
            );
          }
        },
      );
      await client.connect(
        target: target,
        clientDeviceName: deviceName,
        pin: pin,
      );
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      final offer = await ctx.webrtc.createOfferForStream(
        localStream,
        maxBitrateBps: config.videoBitrate,
      );
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      bridge.sendOffer(offer, client: client, sessionId: target.sessionId);
    } catch (e) {
      if (ctx.epoch == epoch && ctx.isNotifierMounted) {
        await teardown(ctx, .failed, errorMessage: friendlySessionError(e));
      }
    }
  }

  /// Switches camera/screen source and replaces active video track in-place.
  Future<void> changeSource(
    SessionContext ctx,
    MediaSourceType source, {
    String? desktopSourceId,
  }) async {
    final ref = ctx.sessionRef;
    final configNotifier = ref.read(streamConfigProvider.notifier);
    configNotifier.setSourceType(source);
    configNotifier.setDesktopSourceId(
      source == .screen ? desktopSourceId : null,
    );
    final phase = ctx.currentState.phase;
    if (phase != .streaming && phase != .connecting) return;

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
      if (tracks.isNotEmpty) await ctx.webrtc.replaceVideoTrack(tracks.first);
      await ctx.webrtc.applyBitrateLimit(updated.videoBitrate);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      ctx.currentState = ctx.currentState.copyWith(
        localStream: newStream,
        isTorchOn: false,
        clearError: true,
      );
    } catch (e) {
      if (!ctx.isNotifierMounted) return;
      ctx.currentState = ctx.currentState.copyWith(
        errorMessage: friendlySessionError(e),
        clearLocalStream: ctx.mediaCapture.activeStream == null,
      );
    }
  }

  /// Tears down Sender media, signaling, and WebRTC state cleanly.
  Future<void> teardown(
    SessionContext ctx,
    SessionPhase nextPhase, {
    String? errorMessage,
    bool stopListening = false,
  }) async {
    ctx.bumpEpoch();
    ctx.activeSessionId = null;
    await teardownResources(
      ctx,
      clearUi: true,
      nextPhase: nextPhase,
      errorMessage: errorMessage,
      stopListening: stopListening,
    );
  }

  /// Releases Sender transport and capture resources.
  Future<void> teardownResources(
    SessionContext ctx, {
    required bool clearUi,
    SessionPhase nextPhase = .idle,
    String? errorMessage,
    bool stopListening = false,
  }) async {
    final ref = ctx.sessionRef;
    final webrtc = ctx.webrtc;
    final media = ctx.mediaCapture;
    final client = ref.read(signalingClientServiceProvider);
    final discovery = ref.read(lanDiscoveryServiceProvider);
    if (clearUi && ctx.isNotifierMounted) {
      ctx.currentState = ctx.currentState.reset(
        phase: nextPhase,
        errorMessage: errorMessage,
      );
    }
    await bridge.cancelSessionSubs();
    await webrtc.close();
    await media.stopCapture();
    await client.disconnect();
    if (stopListening) {
      await discovery.stopListening();
    }
  }
}
