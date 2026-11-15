import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/camera_control_state.dart';
import '../models/clipboard_item.dart';
import '../models/device_role.dart';
import '../models/media_source_type.dart';
import '../models/obs_sync_state.dart';
import '../models/signaling_data.dart';
import '../models/signaling_message.dart';
import '../services/webrtc/media_capture_service.dart';
import '../services/webrtc/webrtc_session_service.dart';
import 'discovery_provider.dart';
import 'platform_provider.dart';
import 'session_host_flow.dart';
import 'session_sender_flow.dart';
import 'session_signaling_bridge.dart';
import 'session_state.dart';
import 'session_web_broadcast_flow.dart';
import 'settings_provider.dart';

export '../services/webrtc/media_capture_service.dart' show DesktopSourceItem;
export 'session_state.dart';

/// Injectable local camera/screen capture service.
final mediaCaptureServiceProvider = Provider<MediaCaptureService>((ref) {
  final service = MediaCaptureService();
  ref.onDispose(service.stopCapture);
  return service;
});

/// Injectable WebRTC PeerConnection & DataChannel session manager.
final webrtcSessionServiceProvider = Provider<WebRtcSessionService>((ref) {
  final service = WebRtcSessionService();
  ref.onDispose(service.dispose);
  return service;
});

/// Primary session orchestration provider for Receiver hosting & Sender casting.
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

/// Coordinates LAN discovery, WebSocket signaling, media capture, and WebRTC.
class SessionNotifier extends Notifier<SessionState> implements SessionContext {
  final SessionSignalingBridge _bridge = SessionSignalingBridge();
  late final SessionSenderFlow _senderFlow = SessionSenderFlow(_bridge);
  late final SessionHostFlow _hostFlow = SessionHostFlow(_bridge, _senderFlow);
  late final SessionWebBroadcastFlow _webBroadcastFlow =
      SessionWebBroadcastFlow(_bridge, _senderFlow);

  bool _isHosting = false;
  String? _activeSessionId;
  int _epoch = 0;

  @override
  Ref get sessionRef => ref;

  @override
  SessionState get currentState => state;

  @override
  set currentState(SessionState value) => state = value;

  @override
  bool get isNotifierMounted => ref.mounted;

  @override
  bool get isHosting => _isHosting;

  @override
  set isHosting(bool value) => _isHosting = value;

  @override
  String? get activeSessionId => _activeSessionId;

  @override
  set activeSessionId(String? value) => _activeSessionId = value;

  @override
  int get epoch => _epoch;

  @override
  int bumpEpoch() => ++_epoch;

  @override
  MediaCaptureService get mediaCapture => ref.read(mediaCaptureServiceProvider);

  @override
  WebRtcSessionService get webrtc => ref.read(webrtcSessionServiceProvider);

  @override
  SessionState build() {
    ref.onDispose(_bridge.dispose);
    ref.listen<DeviceRole>(activeRoleProvider, (prev, next) {
      if (prev != null && prev != next) {
        unawaited(
          prev == .receiver
              ? stopHosting()
              : (_isHosting
                    ? stopWebBroadcast()
                    : _senderFlow.teardown(this, .idle, stopListening: true)),
        );
      }
    });
    ref.listen<int>(streamConfigProvider.select((c) => c.videoBitrate), (
      _,
      bps,
    ) {
      if ((!_isHosting || state.isWebBroadcast) &&
          (state.phase == .streaming || state.phase == .connecting)) {
        unawaited(webrtc.applyBitrateLimit(bps));
      }
    });
    return const SessionState();
  }

  /// Starts embedded HTTP/WS signaling server and UDP LAN broadcast (Receiver).
  Future<void> startHosting({bool forceRestart = false}) =>
      _hostFlow.startHosting(this, forceRestart: forceRestart);

  /// Restarts Receiver hosting after adapter IP, port, or PIN updates.
  Future<void> restartHosting() async {
    await stopHosting();
    if (ref.mounted) await startHosting(forceRestart: true);
  }

  /// Stops Receiver signaling server and UDP LAN broadcast.
  Future<void> stopHosting() => _hostFlow.stopHosting(this);

  /// Hosts a local web viewer page so any browser on Wi-Fi can watch Sender.
  Future<void> startWebBroadcast() => _webBroadcastFlow.startWebBroadcast(this);

  /// Stops the Sender's local browser broadcast and releases camera/screen.
  Future<void> stopWebBroadcast() => _webBroadcastFlow.stopWebBroadcast(this);

  /// Starts UDP LAN discovery listener for Sender mode.
  Future<void> startDiscovery() async {
    final epoch = _epoch;
    try {
      await ref.read(lanDiscoveryServiceProvider).startListening();
      if (_epoch != epoch || !ref.mounted) return;
      unawaited(
        ref.read(usbLoopbackPeersProvider.notifier).refresh(ignoreSessionId: _activeSessionId),
      );
      if (state.phase == .idle || state.phase == .failed) {
        state = state.copyWith(phase: .discovering, clearError: true);
      }
    } catch (e) {
      if (_epoch != epoch || !ref.mounted) return;
      state = state.copyWith(
        phase: .failed,
        errorMessage: friendlySessionError(e),
      );
    }
  }

  /// Stops UDP LAN discovery listener.
  Future<void> stopDiscovery() async {
    await ref.read(lanDiscoveryServiceProvider).stopListening();
    if (ref.mounted && state.phase == .discovering) {
      state = state.copyWith(phase: .idle);
    }
  }

  /// Connects to [target] over `/ws`, captures media, and starts WebRTC cast.
  Future<void> connectAndStream(SignalingData target, {String? pin}) =>
      _senderFlow.connectAndStream(
        this,
        target,
        pin: pin,
        onHostPeerFailed: (err) =>
            _hostFlow.resetPeerToLobby(this, errorMessage: err),
      );

  /// Enumerates desktop screens and windows for screen-share selection.
  Future<List<DesktopSourceItem>> loadDesktopSources() =>
      mediaCapture.getDesktopSources();

  /// Switches front/back camera during an active camera broadcast.
  Future<void> switchCamera() =>
      applyLocalCameraCommand(const RemoteCameraCommand(command: .flip));

  /// Mutes or unmutes outgoing microphone audio.
  void toggleMicMute() {
    final nextMuted = !state.isMicMuted;
    mediaCapture.setMicMuted(nextMuted);
    _syncCameraState(
      state.remoteCameraState.copyWith(micMuted: nextMuted),
      isMicMuted: nextMuted,
    );
  }

  /// Toggles the mobile camera flash torch when supported.
  Future<void> toggleTorch() =>
      applyLocalCameraCommand(const RemoteCameraCommand(command: .torch));

  /// Switches between camera and screen share, replacing track seamlessly.
  Future<void> changeSource(
    MediaSourceType source, {
    String? desktopSourceId,
  }) async {
    await _senderFlow.changeSource(
      this,
      source,
      desktopSourceId: desktopSourceId,
    );
    if (!ref.mounted) return;
    _syncCameraState(
      state.remoteCameraState.copyWith(
        torchOn: state.isTorchOn,
        zoom: 1.0,
        exposureOffset: 0.0,
        focusLocked: false,
        controlsSupported:
            source == .camera && mediaCapture.isCameraControlPlatform,
      ),
    );
  }

  /// Sends a remote camera command (`cam_ctrl`) from the Receiver HUD.
  bool sendRemoteCameraCommand(RemoteCameraCommand cmd) =>
      webrtc.sendCameraCommand(cmd);

  /// Sends a live OBS tally status (`tally`) to the connected Sender.
  bool sendTally(LiveTallyMessage tally) => webrtc.sendTally(tally);

  @override
  void publishCurrentCameraState() {
    if (!ref.mounted) return;
    final cfg = ref.read(streamConfigProvider);
    _syncCameraState(
      state.remoteCameraState.copyWith(
        lens: cfg.cameraLens,
        torchOn: state.isTorchOn,
        micMuted: state.isMicMuted,
        voiceClean: cfg.voiceCleanAudio,
        controlsSupported:
            cfg.sourceType == .camera && mediaCapture.isCameraControlPlatform,
      ),
    );
  }

  @override
  Future<void> applyLocalCameraCommand(RemoteCameraCommand cmd) async {
    if (!ref.mounted) return;
    final cfg = ref.read(streamConfigProvider);
    final prev = state.remoteCameraState.copyWith(
      lens: cfg.cameraLens,
      voiceClean: cfg.voiceCleanAudio,
    );
    final next = await mediaCapture.applyCameraCommand(cmd, prev);
    if (!ref.mounted) return;
    if (next.lens != cfg.cameraLens) {
      ref.read(streamConfigProvider.notifier).setCameraLens(next.lens);
    }
    if (next.voiceClean != prev.voiceClean) {
      ref.read(streamConfigProvider.notifier).setVoiceCleanAudio(next.voiceClean);
    }
    _syncCameraState(next, isMicMuted: next.micMuted, isTorchOn: next.torchOn);
  }

  void _syncCameraState(
    RemoteCameraState camState, {
    bool? isMicMuted,
    bool? isTorchOn,
  }) {
    state = state.copyWith(
      remoteCameraState: camState,
      isMicMuted: isMicMuted,
      isTorchOn: isTorchOn,
    );
    if (!_isHosting || state.isWebBroadcast) webrtc.sendCameraState(camState);
  }

  /// Sends clipboard text over the active WebRTC control DataChannel.
  void sendClipboardText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!webrtc.sendClipboard(trimmed)) {
      state = state.copyWith(
        errorMessage: 'Control channel is not connected yet.',
      );
      return;
    }
    final item = ClipboardItem(
      text: trimmed,
      timestamp: DateTime.now(),
      fromRemote: false,
    );
    state = state.copyWith(
      clipboardHistory: [item, ...state.clipboardHistory].take(50).toList(),
    );
  }

  /// Gracefully disconnects the active stream or stops hosting/discovery.
  Future<void> disconnect() async {
    if (_isHosting && state.isWebBroadcast) {
      await stopWebBroadcast();
      if (ref.mounted && ref.read(activeRoleProvider) == .sender) {
        await startDiscovery();
      }
      return;
    }
    if (_isHosting) {
      final server = ref.read(signalingServerServiceProvider);
      if (state.phase == .streaming ||
          state.phase == .connecting ||
          state.phase == .reconnecting) {
        await server.disconnectClient('Host ended session');
        if (ref.mounted) await _hostFlow.resetPeerToLobby(this);
      } else {
        await stopHosting();
      }
      return;
    }
    final client = ref.read(signalingClientServiceProvider);
    final sessionId = _activeSessionId;
    if (client.isConnected && sessionId != null) {
      client.send(
        SignalingMessage(
          type: .bye,
          sessionId: sessionId,
          payload: const {'reason': 'Sender disconnected'},
        ),
      );
    }
    final shouldRediscover = ref.read(activeRoleProvider) == .sender;
    await _senderFlow.teardown(this, .idle);
    if (ref.mounted && shouldRediscover) {
      await startDiscovery();
    }
  }

  /// Dismisses the current error banner message.
  void clearError() => state = state.copyWith(clearError: true);
}
