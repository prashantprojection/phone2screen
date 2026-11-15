import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/stream_constants.dart';
import '../models/signaling_data.dart';
import 'discovery_provider.dart';
import 'multi_cam_provider.dart';
import 'obs_sync_provider.dart';
import 'platform_provider.dart';
import 'preferences_provider.dart';
import 'session_sender_flow.dart';
import 'session_signaling_bridge.dart';
import 'session_state.dart';
import 'settings_provider.dart';

/// Executes Receiver hosting lifecycle operations for [SessionNotifier].
class SessionHostFlow {
  final SessionSignalingBridge bridge;
  final SessionSenderFlow senderFlow;

  const SessionHostFlow(this.bridge, this.senderFlow);

  /// Starts embedded HTTP/WS server and UDP LAN broadcast in Receiver mode.
  Future<void> startHosting(
    SessionContext ctx, {
    required bool forceRestart,
  }) async {
    final ref = ctx.sessionRef;
    final platform = ref.read(platformServiceProvider);
    if (!platform.canHostServer) return;
    final phase = ctx.currentState.phase;
    if (!forceRestart &&
        (phase == .hosting || phase == .streaming || phase == .connecting)) {
      return;
    }

    final epoch = ctx.bumpEpoch();
    ctx.isHosting = true;
    await senderFlow.teardownResources(ctx, clearUi: false);
    if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

    try {
      final sessionId = const Uuid().v4().substring(0, 8).toUpperCase();
      ctx.activeSessionId = sessionId;
      final deviceName = await platform.resolveDeviceName();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      final selectedIp = ref.read(selectedIpProvider);
      final ip = (selectedIp != null && selectedIp.isNotEmpty)
          ? selectedIp
          : await ref.read(networkAddressServiceProvider).resolvePrimaryIp();
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;

      final settings = ref.read(appSettingsProvider);
      final launchArgs = ref.read(windowLaunchArgsProvider);
      final preferredPort = launchArgs.preferredPortOverride ?? settings.preferredPort;
      final effectiveName = launchArgs.isSecondaryCameraWindow
          ? '$deviceName • Cam ${launchArgs.cameraSlot}'
          : deviceName;
      final maxPeers =
          (!platform.isWeb && platform.isDesktop && !launchArgs.isSecondaryCameraWindow)
          ? StreamConstants.maxDesktopReceiverPeers
          : StreamConstants.maxActivePeers;
      final pin = settings.pin.trim();
      final server = ref.read(signalingServerServiceProvider);
      final port = await server.start(
        preferredPort: preferredPort,
        companionMode: .sendToReceiver,
        sessionId: sessionId,
        deviceName: effectiveName,
        pin: pin.isEmpty ? null : pin,
        maxPeers: maxPeers,
      );
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      if (!platform.isWeb && platform.isDesktop) {
        unawaited(ref.read(usbBridgeServiceProvider).syncAdbReversePorts([port]));
      }

      final endpoint = SignalingData(
        ip: ip, port: port, httpsPort: server.boundHttpsPort,
        sessionId: sessionId, deviceName: effectiveName, requiresPin: pin.isNotEmpty,
      );

      bridge.wireWebRtc(
        ctx,
        onHostPeerFailed: (err) => resetPeerToLobby(ctx, errorMessage: err),
        onSenderPeerFailed: (err) => senderFlow.teardown(ctx, .failed, errorMessage: err),
        readHostTally: () => _readHostTally(ref),
      );
      await bridge.listenServer(
        server,
        onMessage: (m) => bridge.dispatchServerMessage(
          m,
          webrtc: ctx.webrtc,
          server: server,
          sessionId: ctx.activeSessionId ?? m.sessionId,
          isActive: () => ctx.epoch == epoch && ctx.isNotifierMounted && ctx.isHosting,
          onHello: (name) => ctx.currentState = ctx.currentState.copyWith(
            phase: .connecting, connectedPeerName: name, clearError: true,
          ),
          onBye: () => resetPeerToLobby(ctx),
        ),
        onClientEvent: (connected) async {
          if (ctx.epoch != epoch || !ctx.isNotifierMounted || !ctx.isHosting) return;
          final p = ctx.currentState.phase;
          if (!connected && (p == .connecting || p == .streaming || p == .reconnecting)) {
            await resetPeerToLobby(ctx);
          }
        },
      );
      await ref.read(lanDiscoveryServiceProvider).startBroadcasting(endpoint);
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      ctx.currentState = ctx.currentState.reset(phase: .hosting, activeEndpoint: endpoint);
    } catch (e) {
      if (ctx.epoch != epoch || !ctx.isNotifierMounted) return;
      ctx.isHosting = false;
      ctx.activeSessionId = null;
      ctx.currentState = ctx.currentState.copyWith(phase: .failed, errorMessage: friendlySessionError(e));
    }
  }

  /// Stops Receiver signaling server and UDP LAN broadcast.
  Future<void> stopHosting(SessionContext ctx) async {
    final ref = ctx.sessionRef;
    final webrtc = ctx.webrtc;
    final discovery = ref.read(lanDiscoveryServiceProvider);
    final server = ref.read(signalingServerServiceProvider);
    ctx.bumpEpoch();
    ctx.isHosting = false;
    ctx.activeSessionId = null;
    if (ctx.isNotifierMounted) {
      ctx.currentState = ctx.currentState.reset();
    }
    await bridge.cancelSessionSubs();
    await webrtc.close();
    await discovery.stopBroadcasting();
    await server.stop();
  }

  /// Returns Receiver from a disconnected peer back to the QR lobby.
  Future<void> resetPeerToLobby(
    SessionContext ctx, {
    String? errorMessage,
  }) async {
    await ctx.webrtc.close();
    if (!ctx.isNotifierMounted || !ctx.isHosting) return;
    final running = ctx.sessionRef.read(signalingServerServiceProvider).isRunning;
    ctx.currentState = ctx.currentState.reset(
      phase: running ? .hosting : .idle,
      activeEndpoint: ctx.currentState.activeEndpoint,
      errorMessage: errorMessage,
    );
  }

  LiveTallyMessage _readHostTally(Ref ref) {
    final obs = ref.read(obsSyncProvider);
    if (obs.connected) {
      return LiveTallyMessage(state: obs.tallyState == .off ? .program : obs.tallyState, sceneName: obs.programScene);
    }
    final multiCam = ref.read(multiCamProvider);
    final focused = multiCam.secondarySlots.isEmpty || multiCam.selectedPeerId == null;
    return LiveTallyMessage(state: focused ? .program : .preview);
  }
}
