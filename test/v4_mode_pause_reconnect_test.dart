import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/models/camera_control_state.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/discovered_peer.dart';
import 'package:phone2screen/models/session_phase.dart';
import 'package:phone2screen/models/shortcut_config.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/models/stream_config.dart';
import 'package:phone2screen/providers/discovery_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/preferences_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/services/network/lan_discovery_service.dart';
import 'package:phone2screen/services/network/usb_bridge_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/storage/local_preferences_service.dart';
import 'package:phone2screen/services/webrtc/camera_control_service.dart';
import 'package:phone2screen/services/webrtc/media_capture_service.dart';
import 'package:phone2screen/services/webrtc/webrtc_session_service.dart';
import 'package:phone2screen/views/shared/keyboard_shortcuts_scope.dart';

class _FakeVideoTrack implements MediaStreamTrack {
  @override bool enabled = true;
  @override String get kind => 'video';
  @override String get id => 'video-track-1';
  @override Future<void> stop() async {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaStream implements MediaStream {
  final _FakeVideoTrack track;
  _FakeMediaStream(this.track);
  @override String get id => 'fake-stream-1';
  @override List<MediaStreamTrack> getVideoTracks() => [track];
  @override List<MediaStreamTrack> getAudioTracks() => const [];
  @override List<MediaStreamTrack> getTracks() => [track];
  @override Future<void> dispose() async {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaCaptureService extends MediaCaptureService {
  final _FakeVideoTrack track = _FakeVideoTrack();
  late final _FakeMediaStream stream = _FakeMediaStream(track);
  @override Future<MediaStream> startCapture(StreamConfig config) async => stream;
  @override Future<void> stopCapture() async {}
}

class _FakeWebRtcService extends WebRtcSessionService {
  final _iceCtrl = StreamController<RTCIceCandidate>.broadcast();
  final _remoteCtrl = StreamController<MediaStream>.broadcast();
  final _connCtrl = StreamController<RTCPeerConnectionState>.broadcast();
  final _camCmdCtrl = StreamController<RemoteCameraCommand>.broadcast();
  final _camStateCtrl = StreamController<RemoteCameraState>.broadcast();
  final List<RemoteCameraCommand> sentCommands = [];
  final List<RemoteCameraState> sentStates = [];

  @override Stream<RTCIceCandidate> get onLocalIceCandidate => _iceCtrl.stream;
  @override Stream<MediaStream> get onRemoteStream => _remoteCtrl.stream;
  @override Stream<RTCPeerConnectionState> get onConnectionState => _connCtrl.stream;
  @override Stream<RemoteCameraCommand> get incomingCameraCommands => _camCmdCtrl.stream;
  @override Stream<RemoteCameraState> get incomingCameraStates => _camStateCtrl.stream;
  @override bool sendCameraCommand(RemoteCameraCommand cmd) { sentCommands.add(cmd); return true; }
  @override bool sendCameraState(RemoteCameraState state) { sentStates.add(state); return true; }
  @override Future<RTCSessionDescription> createOfferForStream(MediaStream s, {required int maxBitrateBps}) async => RTCSessionDescription('v=0', 'offer');
  @override Future<void> applyBitrateLimit(int bps) async {}
  @override Future<void> close() async {}
  void emitConnection(RTCPeerConnectionState state) => _connCtrl.add(state);
  @override Future<void> dispose() async => Future.wait([_iceCtrl.close(), _remoteCtrl.close(), _connCtrl.close(), _camCmdCtrl.close(), _camStateCtrl.close()]);
}

class _FakeSignalingClient extends SignalingClientService {
  final _msgCtrl = StreamController<SignalingMessage>.broadcast();
  final _discCtrl = StreamController<void>.broadcast();
  int connectCalls = 0;
  bool failNextConnect = false;
  bool _connected = false;
  final List<SignalingData> connectedTargets = [];

  @override Stream<SignalingMessage> get messages => _msgCtrl.stream;
  @override Stream<void> get onDisconnected => _discCtrl.stream;
  @override bool get isConnected => _connected;
  @override Future<void> connect({required SignalingData target, required String clientDeviceName, String? pin}) async {
    connectCalls++;
    connectedTargets.add(target);
    if (failNextConnect) throw StateError('Connect refused');
    _connected = true;
  }
  @override void send(SignalingMessage message) {}
  @override Future<void> disconnect() async => _connected = false;
  void dropUnexpectedly() { _connected = false; _discCtrl.add(null); }
  @override Future<void> dispose() async { await _msgCtrl.close(); await _discCtrl.close(); }
}

class _FakeDiscoveryService extends LanDiscoveryService {
  @override Future<void> startListening() async {}
  @override Future<void> stopListening() async {}
}

class _FakeUsbBridge extends UsbBridgeService {
  List<DiscoveredPeer> nextPeers = const [];
  @override Future<List<DiscoveredPeer>> probeLoopbackReceivers({
    List<int> ports = const [8080, 8081, 8082, 8083], String? ignoreSessionId,
    Duration timeout = const Duration(milliseconds: 350),
  }) async => nextPeers;
}

class const _FakePlatform() extends PlatformDetectionService {
  @override DeviceRole get defaultRole => .sender;
  @override bool get canHostServer => false;
  @override Future<String> resolveDeviceName() async => 'Test Phone';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WorkspaceMode enum, AppSettings JSON & LocalPreferencesService persistence', () async {
    expect(WorkspaceMode.simple.label, 'Simple');
    expect(WorkspaceMode.simple.description, 'Plug-and-play webcam for Zoom, Meet, Teams & Discord');
    expect(WorkspaceMode.studio.label, 'Studio');
    expect(WorkspaceMode.studio.description, 'Multi-cam grid, OBS WebSocket tally & full studio rig');

    const defaults = AppSettings();
    expect(defaults.workspaceMode, WorkspaceMode.simple);
    expect(AppSettings.fromJson(const {'workspaceMode': 'bogus'}).workspaceMode, WorkspaceMode.simple);
    const studio = AppSettings(workspaceMode: .studio, pin: '4242');
    expect(AppSettings.fromJson(studio.toJson()), studio);
    expect(defaults == studio, isFalse);

    final dir = Directory('${Directory.current.path}/.dart_tool/test_tmp_v4_mode_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(() async { if (await dir.exists()) await dir.delete(recursive: true); });
    final path = '${dir.path}/prefs.json';
    final container = ProviderContainer(overrides: [localPreferencesServiceProvider.overrideWithValue(LocalPreferencesService.fromFilePath(path))]);
    addTearDown(container.dispose);
    container.read(preferencesAutoSaveProvider);

    container.read(appSettingsProvider.notifier).toggleWorkspaceMode();
    expect(container.read(appSettingsProvider).workspaceMode, WorkspaceMode.studio);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final reloaded = LocalPreferencesService.fromFilePath(path);
    await reloaded.load();
    expect(reloaded.snapshot.appSettings.workspaceMode, WorkspaceMode.studio);
    container.read(appSettingsProvider.notifier).setWorkspaceMode(.simple);
    expect(container.read(appSettingsProvider).workspaceMode, WorkspaceMode.simple);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });

  test('ViewerDisplayConfig.isVideoPaused, Shortcut P, & CameraControlState.videoPause', () async {
    expect(ShortcutAction.toggleVideoPause.label, 'Pause Camera');
    expect(ShortcutAction.toggleVideoPause.description, 'Freeze or resume camera feed with privacy slate');
    expect(defaultShortcutBindings.length, ShortcutAction.values.length);
    expect(defaultShortcutBindings[ShortcutAction.toggleVideoPause]?.displayLabel, 'P');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final displayNotifier = container.read(viewerDisplayProvider.notifier)
      ..setVideoPaused(true)
      ..setBrightness(0.3)
      ..resetFramingAndColor();
    expect(container.read(viewerDisplayProvider).isVideoPaused, isTrue);
    expect(container.read(viewerDisplayProvider).brightness, 0.0);
    displayNotifier.toggleVideoPause();
    expect(container.read(viewerDisplayProvider).isVideoPaused, isFalse);

    const cmd = RemoteCameraCommand(command: .videoPause, enabled: true);
    expect(RemoteCameraCommand.tryFromJson(cmd.toJson()), cmd);
    const camState = RemoteCameraState(videoPaused: true);
    expect(RemoteCameraState.tryFromJson(camState.toJson()), camState);
    expect(RemoteCameraState.tryFromJson(const {'kind': 'cam_state'})?.videoPaused, isFalse);

    final track = _FakeVideoTrack();
    final next = await CameraControlService().applyCommand(
      cmd, const RemoteCameraState(), stream: _FakeMediaStream(track),
      switchCamera: () async => false, toggleTorch: (_) async => false, setMicMuted: (_) {},
    );
    expect(next.videoPaused, isTrue);
    expect(track.enabled, isFalse);
  });

  testWidgets('SessionNotifier & KeyboardShortcutsScope P toggle videoPause bidirectionally', (tester) async {
    final (webrtc, capture) = (_FakeWebRtcService(), _FakeMediaCaptureService());
    final container = ProviderContainer(overrides: [
      platformServiceProvider.overrideWithValue(const _FakePlatform()),
      webrtcSessionServiceProvider.overrideWithValue(webrtc),
      mediaCaptureServiceProvider.overrideWithValue(capture),
      lanDiscoveryServiceProvider.overrideWithValue(_FakeDiscoveryService()),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(sessionProvider.notifier)
      ..currentState = SessionState(phase: .streaming, localStream: capture.stream);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: KeyboardShortcutsScope(child: SizedBox()))),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(container.read(sessionProvider).isVideoPaused, isTrue);
    expect(capture.track.enabled, isFalse);
    expect(webrtc.sentStates.last.videoPaused, isTrue);

    await notifier.applyLocalCameraCommand(const RemoteCameraCommand(command: .videoPause, enabled: false));
    expect(container.read(sessionProvider).isVideoPaused, isFalse);
    expect(capture.track.enabled, isTrue);

    container.read(activeRoleProvider.notifier).setRole(.receiver);
    await tester.pump();
    notifier.isHosting = true;
    notifier.currentState = const SessionState(phase: .streaming);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(container.read(viewerDisplayProvider).isVideoPaused, isTrue);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: true));

    notifier.currentState = container.read(sessionProvider).copyWith(remoteCameraState: const RemoteCameraState(videoPaused: true));
    notifier.currentState = container.read(sessionProvider).copyWith(remoteCameraState: const RemoteCameraState(videoPaused: false));
    expect(container.read(viewerDisplayProvider).isVideoPaused, isFalse);
    notifier.toggleVideoPause();
    expect(container.read(viewerDisplayProvider).isVideoPaused, isTrue);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: true));
  });

  group('SessionSenderFlow sub-second auto-reconnect resilience', () {
    const endpoint = SignalingData(ip: '192.168.1.50', port: 8080, sessionId: 'S1', deviceName: 'OBS PC');
    const usbEndpoint = SignalingData(ip: '127.0.0.1', port: 8080, sessionId: 'S1', deviceName: 'OBS PC');

    ({ProviderContainer c, _FakeWebRtcService rtc, _FakeSignalingClient ws, _FakeUsbBridge usb}) makeEnv() {
      final (rtc, ws, usb) = (_FakeWebRtcService(), _FakeSignalingClient(), _FakeUsbBridge());
      final c = ProviderContainer(overrides: [
        platformServiceProvider.overrideWithValue(const _FakePlatform()),
        webrtcSessionServiceProvider.overrideWithValue(rtc),
        mediaCaptureServiceProvider.overrideWithValue(_FakeMediaCaptureService()),
        signalingClientServiceProvider.overrideWithValue(ws),
        lanDiscoveryServiceProvider.overrideWithValue(_FakeDiscoveryService()),
        usbBridgeServiceProvider.overrideWithValue(usb),
      ]);
      addTearDown(c.dispose);
      return (c: c, rtc: rtc, ws: ws, usb: usb);
    }

    test('auto-reconnects once via USB loopback on transient drop during active stream', () async {
      final env = makeEnv();
      final notifier = env.c.read(sessionProvider.notifier);
      await notifier.connectAndStream(endpoint);
      env.rtc.emitConnection(.RTCPeerConnectionStateConnected);
      await Future<void>.delayed(Duration.zero);
      expect(env.c.read(sessionProvider).phase, SessionPhase.streaming);

      env.usb.nextPeers = [DiscoveredPeer(endpoint: usbEndpoint, lastSeen: DateTime.now(), isUsbLoopback: true)];
      env.ws.dropUnexpectedly();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(env.c.read(sessionProvider).phase, SessionPhase.reconnecting);
      expect(env.c.read(sessionProvider).activeEndpoint, endpoint);
      expect(env.c.read(sessionProvider).connectedPeerName, 'OBS PC');

      await Future<void>.delayed(const Duration(milliseconds: 780));
      expect(env.ws.connectCalls, 2);
      expect(env.ws.connectedTargets.last, usbEndpoint);
      env.rtc.emitConnection(.RTCPeerConnectionStateConnected);
      await Future<void>.delayed(Duration.zero);
      expect(env.c.read(sessionProvider).phase, SessionPhase.streaming);
    });

    test('falls back to .failed on retry failure, ignores pre-stream drop, and aborts on disconnect()', () async {
      final env = makeEnv();
      final notifier = env.c.read(sessionProvider.notifier);

      await notifier.connectAndStream(endpoint);
      env.ws.dropUnexpectedly();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(env.c.read(sessionProvider).phase, SessionPhase.failed);
      expect(env.ws.connectCalls, 1);

      env.ws.connectCalls = 0;
      await notifier.connectAndStream(endpoint);
      env.rtc.emitConnection(.RTCPeerConnectionStateConnected);
      await Future<void>.delayed(Duration.zero);
      env.ws.failNextConnect = true;
      env.ws.dropUnexpectedly();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(env.ws.connectCalls, 2);
      expect(env.c.read(sessionProvider).phase, SessionPhase.failed);

      env.ws.connectCalls = 0;
      env.ws.failNextConnect = false;
      await notifier.connectAndStream(endpoint);
      env.rtc.emitConnection(.RTCPeerConnectionStateConnected);
      await Future<void>.delayed(Duration.zero);
      env.ws.dropUnexpectedly();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(env.c.read(sessionProvider).phase, SessionPhase.reconnecting);
      await notifier.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 780));
      expect(env.ws.connectCalls, 1);
      expect(env.c.read(sessionProvider).phase, SessionPhase.discovering);
    });
  });
}
