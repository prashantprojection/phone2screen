import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/camera_control_state.dart';
import '../models/clipboard_item.dart';
import '../models/obs_sync_state.dart';
import '../models/signaling_message.dart';
import '../services/signaling/signaling_client_service.dart';
import '../services/signaling/signaling_server_service.dart';
import '../services/webrtc/webrtc_session_service.dart';
import 'discovery_provider.dart';
import 'session_state.dart';
import 'settings_provider.dart';

/// Encapsulates signaling stream subscriptions, WebRTC event wiring, and
/// SDP/ICE payload dispatch for [SessionNotifier].
class SessionSignalingBridge {
  final List<StreamSubscription<dynamic>> _sessionSubs = [];
  final List<StreamSubscription<dynamic>> _webrtcSubs = [];
  Future<void> Function(RemoteCameraCommand cmd)? _onCameraCommand;
  LiveTallyMessage Function()? _readHostTally;
  bool _webrtcWired = false;

  /// Subscribes once to [WebRtcSessionService] broadcast streams.
  void wireWebRtc(
    SessionContext ctx, {
    required Future<void> Function(String? errorMessage) onHostPeerFailed,
    required Future<void> Function(String? errorMessage) onSenderPeerFailed,
    Future<void> Function(RemoteCameraCommand cmd)? onCameraCommand,
    LiveTallyMessage Function()? readHostTally,
  }) {
    _onCameraCommand = onCameraCommand ?? _onCameraCommand;
    _readHostTally = readHostTally ?? _readHostTally;
    if (_webrtcWired) return;
    _webrtcWired = true;
    final ref = ctx.sessionRef;
    _webrtcSubs.addAll([
      ctx.webrtc.onLocalIceCandidate.listen((c) {
        final sessionId = ctx.activeSessionId;
        if (sessionId == null) return;
        sendLocalIceCandidate(
          c,
          sessionId: sessionId,
          isHosting: ctx.isHosting,
          server: ref.read(signalingServerServiceProvider),
          client: ref.read(signalingClientServiceProvider),
        );
      }),
      ctx.webrtc.onRemoteStream.listen((stream) {
        if (ctx.isNotifierMounted) {
          ctx.currentState = ctx.currentState.copyWith(
            remoteStream: stream,
            phase: .streaming,
            clearError: true,
          );
        }
      }),
      ctx.webrtc.onConnectionState.listen((connState) {
        if (!ctx.isNotifierMounted || ctx.activeSessionId == null) return;
        switch (connState) {
          case .RTCPeerConnectionStateConnected:
            ctx.currentState = ctx.currentState.copyWith(
              phase: .streaming,
              clearError: true,
            );
          case .RTCPeerConnectionStateDisconnected:
            if (ctx.currentState.phase == .streaming) {
              ctx.currentState = ctx.currentState.copyWith(
                phase: .reconnecting,
              );
            }
          case .RTCPeerConnectionStateFailed:
            unawaited(
              ctx.isHosting
                  ? onHostPeerFailed('WebRTC peer failed.')
                  : onSenderPeerFailed('WebRTC peer connection failed.'),
            );
          case .RTCPeerConnectionStateNew ||
              .RTCPeerConnectionStateConnecting ||
              .RTCPeerConnectionStateClosed:
            break;
        }
      }),
      ctx.webrtc.telemetryStream.listen((t) {
        if (ctx.isNotifierMounted) {
          ctx.currentState = ctx.currentState.copyWith(telemetry: t);
        }
      }),
      ctx.webrtc.incomingClipboard.listen((item) => _onClipboard(ctx, item)),
      ctx.webrtc.incomingTally.listen((tally) {
        if (ctx.isNotifierMounted && !ctx.isHosting) {
          ctx.currentState = ctx.currentState.copyWith(liveTally: tally);
        }
      }),
      ..._buildCameraControlSubs(ctx),
    ]);
  }

  List<StreamSubscription<dynamic>> _buildCameraControlSubs(
    SessionContext ctx,
  ) => [
    ctx.webrtc.incomingCameraCommands.listen((cmd) {
      if (!ctx.isNotifierMounted || ctx.activeSessionId == null) return;
      // Only a broadcasting Sender or WebBroadcast applies incoming cam_ctrl frames.
      final isBroadcaster = !ctx.isHosting || ctx.currentState.isWebBroadcast;
      if (!isBroadcaster) return;
      final handler = _onCameraCommand ?? ctx.applyLocalCameraCommand;
      unawaited(handler(cmd));
    }),
    ctx.webrtc.incomingCameraStates.listen((camState) {
      if (!ctx.isNotifierMounted) return;
      // Mirror authoritative broadcaster camera state into Receiver HUD state.
      ctx.currentState = ctx.currentState.copyWith(remoteCameraState: camState);
    }),
    ctx.webrtc.onControlChannelOpen.listen((_) {
      if (!ctx.isNotifierMounted || ctx.activeSessionId == null) return;
      // Publish initial lens, torch, mute, and hardware support on channel open.
      final isBroadcaster = !ctx.isHosting || ctx.currentState.isWebBroadcast;
      if (isBroadcaster) ctx.publishCurrentCameraState();
      if (ctx.isHosting && !ctx.currentState.isWebBroadcast && _readHostTally != null) {
        ctx.webrtc.sendTally(_readHostTally!());
      }
    }),
  ];

  void _onClipboard(SessionContext ctx, ClipboardItem item) {
    if (!ctx.isNotifierMounted) return;
    ctx.currentState = ctx.currentState.copyWith(
      clipboardHistory: [
        item,
        ...ctx.currentState.clipboardHistory,
      ].take(50).toList(),
    );
    if (ctx.sessionRef.read(appSettingsProvider).autoCopyClipboard) {
      unawaited(
        Clipboard.setData(ClipboardData(text: item.text)).catchError((_) {}),
      );
    }
  }

  /// Replaces active signaling subscriptions for Receiver hosting mode.
  Future<void> listenServer(
    SignalingServerService server, {
    required Future<void> Function(SignalingMessage msg) onMessage,
    required Future<void> Function(bool connected) onClientEvent,
  }) async {
    await cancelSessionSubs();
    _sessionSubs.addAll([
      server.messages.listen((msg) => unawaited(onMessage(msg))),
      server.clientConnectionEvents.listen(
        (connected) => unawaited(onClientEvent(connected)),
      ),
    ]);
  }

  /// Replaces active signaling subscriptions for Sender client mode.
  Future<void> listenClient(
    SignalingClientService client, {
    required Future<void> Function(SignalingMessage msg) onMessage,
    required Future<void> Function() onDisconnected,
  }) async {
    await cancelSessionSubs();
    _sessionSubs.addAll([
      client.messages.listen((msg) => unawaited(onMessage(msg))),
      client.onDisconnected.listen((_) => unawaited(onDisconnected())),
    ]);
  }

  /// Forwards a local ICE candidate over server or client signaling.
  void sendLocalIceCandidate(
    RTCIceCandidate candidate, {
    required String sessionId,
    required bool isHosting,
    required SignalingServerService server,
    required SignalingClientService client,
  }) {
    final message = SignalingMessage(
      type: .ice,
      sessionId: sessionId,
      payload: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    );
    if (isHosting) {
      server.send(message);
    } else {
      client.send(message);
    }
  }

  /// Sends an SDP offer from the Sender client.
  void sendOffer(
    RTCSessionDescription offer, {
    required SignalingClientService client,
    required String sessionId,
  }) {
    client.send(
      SignalingMessage(
        type: .offer,
        sessionId: sessionId,
        payload: {'sdp': offer.sdp, 'type': offer.type},
      ),
    );
  }

  /// Routes an authenticated host-side signaling message (Receiver or Web Broadcast).
  Future<void> dispatchServerMessage(
    SignalingMessage msg, {
    required WebRtcSessionService webrtc,
    required SignalingServerService server,
    required String sessionId,
    required bool Function() isActive,
    required FutureOr<void> Function(String peerName) onHello,
    required Future<void> Function() onBye,
  }) async {
    if (!isActive()) return;
    switch (msg.type) {
      case .hello:
        final rawName = (msg.payload['deviceName'] as String?)?.trim();
        await onHello(
          (rawName == null || rawName.isEmpty) ? 'Sender' : rawName,
        );
      case .offer:
        final sdp = msg.payload['sdp'] as String?;
        final type = (msg.payload['type'] as String?) ?? 'offer';
        if (sdp == null || sdp.isEmpty) return;
        final answer = await webrtc.acceptOfferAndCreateAnswer(
          RTCSessionDescription(sdp, type),
        );
        if (!isActive()) return;
        server.send(
          SignalingMessage(
            type: .answer,
            sessionId: sessionId,
            payload: {'sdp': answer.sdp, 'type': answer.type},
          ),
        );
      case .answer:
        final sdp = msg.payload['sdp'] as String?;
        final type = (msg.payload['type'] as String?) ?? 'answer';
        if (sdp == null || sdp.isEmpty) return;
        await webrtc.applyRemoteAnswer(RTCSessionDescription(sdp, type));
      case .ice:
        await _applyIcePayload(msg.payload, webrtc);
      case .bye:
        await onBye();
      case .welcome || .error:
        break;
    }
  }

  /// Routes a Sender-side signaling message from the Receiver.
  Future<void> dispatchClientMessage(
    SignalingMessage msg, {
    required WebRtcSessionService webrtc,
    required bool Function() isActive,
    required void Function(String hostName) onWelcome,
    required Future<void> Function(String reason) onError,
    required Future<void> Function() onBye,
  }) async {
    if (!isActive()) return;
    switch (msg.type) {
      case .welcome:
        final hostName = (msg.payload['deviceName'] as String?)?.trim();
        if (hostName != null && hostName.isNotEmpty) onWelcome(hostName);
      case .answer:
        final sdp = msg.payload['sdp'] as String?;
        final type = (msg.payload['type'] as String?) ?? 'answer';
        if (sdp == null || sdp.isEmpty) return;
        await webrtc.applyRemoteAnswer(RTCSessionDescription(sdp, type));
      case .ice:
        await _applyIcePayload(msg.payload, webrtc);
      case .error:
        final reason =
            (msg.payload['message'] as String?) ??
            'Signaling error from receiver.';
        await onError(reason);
      case .bye:
        await onBye();
      case .hello || .offer:
        break;
    }
  }

  Future<void> _applyIcePayload(
    Map<String, dynamic> payload,
    WebRtcSessionService webrtc,
  ) async {
    final candidate = payload['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) return;
    final sdpMid = payload['sdpMid'] as String?;
    final sdpMLineIndex = (payload['sdpMLineIndex'] as num?)?.toInt();
    await webrtc.addRemoteIceCandidate(
      RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
    );
  }

  /// Cancels active host/client signaling subscriptions.
  Future<void> cancelSessionSubs() async {
    final subs = List<StreamSubscription<dynamic>>.of(_sessionSubs);
    _sessionSubs.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
  }

  /// Synchronously cancels all subscriptions on provider disposal.
  void dispose() {
    final sessionSubs = List<StreamSubscription<dynamic>>.of(_sessionSubs);
    _sessionSubs.clear();
    for (final sub in sessionSubs) {
      unawaited(sub.cancel());
    }
    final webrtcSubs = List<StreamSubscription<dynamic>>.of(_webrtcSubs);
    _webrtcSubs.clear();
    for (final sub in webrtcSubs) {
      unawaited(sub.cancel());
    }
  }
}
