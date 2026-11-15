import 'package:uuid/uuid.dart';

import '../models/signaling_data.dart';
import '../models/signaling_message.dart';
import 'discovery_provider.dart';
import 'platform_provider.dart';
import 'session_sender_flow.dart';
import 'session_signaling_bridge.dart';
import 'session_state.dart';
import 'settings_provider.dart';

/// Hosts the Sender camera/screen stream at `http://<ip>:<port>` so any LAN
/// browser can watch via `viewSenderStream` over plain HTTP (zero HTTPS setup).
class SessionWebBroadcastFlow {
  final SessionSignalingBridge bridge;
  final SessionSenderFlow senderFlow;

  const SessionWebBroadcastFlow(this.bridge, this.senderFlow);

  /// Captures local media, starts embedded HTTP/WS in `viewSenderStream` mode,
  /// and sends WebRTC offers to each browser viewer that connects.
  Future<void> startWebBroadcast(SessionContext ctx) async {
    final ref = ctx.sessionRef;
    final platform = ref.read(platformServiceProvider);
    if (!platform.canHostServer) return;

    final epoch = ctx.bumpEpoch();
    ctx.isHosting = true;
    final server = ref.read(signalingServerServiceProvider);

    try {
      await senderFlow.teardownResources(ctx, clearUi: false, stopListening: true);
      if (server.isRunning) await server.stop();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      final config = ref.read(streamConfigProvider);
      final localStream = await ctx.mediaCapture.startCapture(config);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }

      final sessionId = const Uuid().v4().substring(0, 8).toUpperCase();
      ctx.activeSessionId = sessionId;
      final deviceName = await platform.resolveDeviceName();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }

      final selectedIp = ref.read(selectedIpProvider);
      final ip = (selectedIp != null && selectedIp.isNotEmpty)
          ? selectedIp
          : await ref.read(networkAddressServiceProvider).resolvePrimaryIp();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await ctx.mediaCapture.stopCapture();
        return;
      }

      final settings = ref.read(appSettingsProvider);
      final pin = settings.pin.trim();
      final port = await server.start(
        preferredPort: settings.preferredPort,
        preferredHttpsPort: null,
        companionMode: .viewSenderStream,
        sessionId: sessionId,
        deviceName: deviceName,
        pin: pin.isEmpty ? null : pin,
      );
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) {
        await server.stop();
        await ctx.mediaCapture.stopCapture();
        return;
      }

      final endpoint = SignalingData(
        ip: ip,
        port: port,
        httpsPort: server.boundHttpsPort,
        sessionId: sessionId,
        deviceName: deviceName,
        requiresPin: pin.isNotEmpty,
      );

      bridge.wireWebRtc(
        ctx,
        onHostPeerFailed: (err) => resetViewerToLobby(ctx, errorMessage: err),
        onSenderPeerFailed: (err) =>
            senderFlow.teardown(ctx, .failed, errorMessage: err),
      );
      await bridge.listenServer(
        server,
        onMessage: (m) => bridge.dispatchServerMessage(
          m,
          webrtc: ctx.webrtc,
          server: server,
          sessionId: ctx.activeSessionId ?? m.sessionId,
          isActive: () =>
              ctx.epoch == epoch && ctx.isNotifierMounted && ctx.isHosting,
          onHello: (name) async {
            ctx.currentState = ctx.currentState.copyWith(
              phase: .connecting,
              connectedPeerName: name,
              isWebBroadcast: true,
              clearError: true,
            );
            final stream = ctx.mediaCapture.activeStream;
            if (stream == null || ctx.epoch != epoch || !ctx.isHosting) return;
            final offer = await ctx.webrtc.createOfferForStream(
              stream,
              maxBitrateBps: ref.read(streamConfigProvider).videoBitrate,
            );
            if (ctx.epoch != epoch || !ctx.isNotifierMounted || !ctx.isHosting) {
              return;
            }
            server.send(
              SignalingMessage(
                type: .offer,
                sessionId: sessionId,
                payload: {'sdp': offer.sdp, 'type': offer.type},
              ),
            );
          },
          onBye: () => resetViewerToLobby(ctx),
        ),
        onClientEvent: (connected) async {
          if (ctx.epoch != epoch || !ctx.isNotifierMounted || !ctx.isHosting) {
            return;
          }
          final p = ctx.currentState.phase;
          if (!connected &&
              (p == .connecting || p == .streaming || p == .reconnecting)) {
            await resetViewerToLobby(ctx);
          }
        },
      );
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      ctx.currentState = ctx.currentState
          .reset(
            phase: .hosting,
            activeEndpoint: endpoint,
            isWebBroadcast: true,
          )
          .copyWith(localStream: localStream);
    } catch (e) {
      await ctx.webrtc.close();
      await ctx.mediaCapture.stopCapture();
      await server.stop();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      ctx.isHosting = false;
      ctx.activeSessionId = null;
      ctx.currentState = ctx.currentState.reset(
        phase: .failed,
        errorMessage: friendlySessionError(e),
      );
    }
  }

  /// Drops the current browser viewer back to the QR lobby while keeping media live.
  Future<void> resetViewerToLobby(
    SessionContext ctx, {
    String? errorMessage,
  }) async {
    await ctx.webrtc.close();
    if (!ctx.isNotifierMounted || !ctx.isHosting) return;
    final running = ctx.sessionRef.read(signalingServerServiceProvider).isRunning;
    ctx.currentState = ctx.currentState
        .reset(
          phase: running ? .hosting : .idle,
          activeEndpoint: ctx.currentState.activeEndpoint,
          isWebBroadcast: running,
          errorMessage: errorMessage,
        )
        .copyWith(localStream: ctx.mediaCapture.activeStream);
  }

  /// Stops local media capture, WebRTC, and embedded web viewer server.
  Future<void> stopWebBroadcast(SessionContext ctx) async {
    final ref = ctx.sessionRef;
    final server = ref.read(signalingServerServiceProvider);
    ctx.bumpEpoch();
    ctx.isHosting = false;
    ctx.activeSessionId = null;
    if (ctx.isNotifierMounted) {
      ctx.currentState = ctx.currentState.reset();
    }
    await bridge.cancelSessionSubs();
    await ctx.webrtc.close();
    await ctx.mediaCapture.stopCapture();
    await server.stop();
  }
}
