import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/app.dart';
import 'package:phone2screen/models/camera_control_state.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/discovered_peer.dart';
import 'package:phone2screen/models/network_interface_info.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/providers/discovery_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/providers/obs_sync_provider.dart';
import 'package:phone2screen/services/network/lan_discovery_service.dart';
import 'package:phone2screen/services/network/network_address_service.dart';
import 'package:phone2screen/services/network/usb_bridge_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/services/webrtc/webrtc_session_service.dart';
import 'package:phone2screen/services/windowing/windows_studio_service.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_controls_bar.dart';
import 'package:phone2screen/views/receiver/widgets/simple_webcam_card.dart';
import 'package:phone2screen/views/shared/workspace_mode_pill.dart';

class const _FakeDesktopPlatform() extends PlatformDetectionService {
  @override DeviceRole get defaultRole => .receiver;
  @override bool get canHostServer => true;
  @override bool get isDesktop => true;
  @override bool get isMobile => false;
  @override bool get supportsQrScanner => false;
  @override bool get supportsDesktopPicker => true;
  @override Future<String> resolveDeviceName() async => 'Studio Desktop';
}

class const _FakeNetAddress() implements NetworkAddressService {
  @override Future<List<NetworkInterfaceInfo>> listInterfaces() async => const [
    NetworkInterfaceInfo(name: 'Wi-Fi', address: '192.168.1.40', isPreferred: true),
  ];
  @override Future<String> resolvePrimaryIp() async => '192.168.1.40';
}

class _FakeDiscovery implements LanDiscoveryService {
  final _ctrl = StreamController<List<DiscoveredPeer>>.broadcast();
  @override Stream<List<DiscoveredPeer>> get peersStream => _ctrl.stream;
  @override List<DiscoveredPeer> get currentPeers => const [];
  @override Future<void> startBroadcasting(SignalingData hostInfo) async {}
  @override Future<void> stopBroadcasting() async {}
  @override Future<void> startListening() async { if (!_ctrl.isClosed) _ctrl.add(const []); }
  @override Future<void> stopListening() async {}
  @override Future<void> dispose() => _ctrl.close();
}

class _FakeServer implements SignalingServerService {
  final _msgs = StreamController<SignalingMessage>.broadcast();
  final _events = StreamController<bool>.broadcast();
  final _pMsgs = StreamController<PeerSignalingEvent>.broadcast();
  final _pEvents = StreamController<PeerConnectionEvent>.broadcast();
  int? _port;
  @override Stream<SignalingMessage> get messages => _msgs.stream;
  @override Stream<bool> get clientConnectionEvents => _events.stream;
  @override Stream<PeerSignalingEvent> get peerMessages => _pMsgs.stream;
  @override Stream<PeerConnectionEvent> get peerConnectionEvents => _pEvents.stream;
  @override int? get boundPort => _port;
  @override int? get boundHttpsPort => 8443;
  @override WebCompanionMode get companionMode => .sendToReceiver;
  @override bool get isRunning => _port != null;
  @override Future<int> start({int preferredPort = 8080, int? preferredHttpsPort = 8443, WebCompanionMode companionMode = .sendToReceiver, required String sessionId, required String deviceName, String? pin, int maxPeers = 1}) async => _port = preferredPort == 0 ? 8080 : preferredPort;
  @override void send(SignalingMessage message, {String? peerId}) {}
  @override Future<void> disconnectClient([String reason = 'Host ended', String? peerId]) async {}
  @override Future<void> stop() async => _port = null;
  @override Future<void> dispose() => Future.wait([_msgs.close(), _events.close(), _pMsgs.close(), _pEvents.close()]);
}

class _FakeClient implements SignalingClientService {
  final _msgs = StreamController<SignalingMessage>.broadcast();
  final _disc = StreamController<void>.broadcast();
  @override Stream<SignalingMessage> get messages => _msgs.stream;
  @override Stream<void> get onDisconnected => _disc.stream;
  @override bool get isConnected => false;
  @override Future<void> connect({required SignalingData target, required String clientDeviceName, String? pin}) async {}
  @override void send(SignalingMessage message) {}
  @override Future<void> disconnect() async {}
  @override Future<void> dispose() => Future.wait([_msgs.close(), _disc.close()]);
}

class _FakeUsbBridge extends UsbBridgeService {
  @override Future<UsbBridgeStatus> syncAdbReversePorts(List<int> ports) async => const UsbBridgeStatus(adbAvailable: false);
  @override Future<List<DiscoveredPeer>> probeLoopbackReceivers({List<int> ports = const [8080, 8081, 8082, 8083], String? ignoreSessionId, Duration timeout = const Duration(milliseconds: 350)}) async => const [];
}

class _FakeWinStudio extends WindowsStudioService {
  _FakeWinStudio() : super(isSupportedOverride: true);
  bool registered = false;
  int registerCalls = 0;
  int unregisterCalls = 0;
  int camState = 0;

  @override Future<NativeVirtualCamStatus> getVirtualCamStatus() async => NativeVirtualCamStatus(
    isSupported: true, isRegistered: registered, dllFound: true,
    dllPath: r'D:\bin\p2s_vcam.dll', activeState: camState,
  );
  @override Future<bool> registerVirtualCam() async { registerCalls++; registered = true; return true; }
  @override Future<bool> unregisterVirtualCam() async { unregisterCalls++; registered = false; camState = 0; return true; }
  @override Future<bool> setVirtualCamState(int state) async { camState = state.clamp(0, 2); return true; }
  @override Future<List<VideoCaptureDeviceInfo>> listVideoCaptureDevices() async => [
    if (registered) const VideoCaptureDeviceInfo(name: 'Phone2Screen Camera', devicePath: 'p2s://0', isVirtualCam: true),
  ];
}

class _FakeWebRtc extends WebRtcSessionService {
  final List<RemoteCameraCommand> sentCommands = [];
  @override bool sendCameraCommand(RemoteCameraCommand cmd) { sentCommands.add(cmd); return true; }
  @override Future<void> close() async {}
  @override Future<void> dispose() async {}
}

class _FakeMediaStream implements MediaStream {
  @override String get id => 'v4-test-stream';
  @override String get ownerTag => 'remote';
  @override List<MediaStreamTrack> getAudioTracks() => const [];
  @override List<MediaStreamTrack> getVideoTracks() => const [];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticSessionNotifier extends SessionNotifier {
  final SessionState initial;
  _StaticSessionNotifier(this.initial);
  @override SessionState build() => initial;
  @override Future<void> startHosting({bool forceRestart = false}) async {}
  @override Future<void> startDiscovery() async {}
}

class _StaticSettingsNotifier extends AppSettingsNotifier {
  final AppSettings initial;
  _StaticSettingsNotifier(this.initial);
  @override AppSettings build() => initial;
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void _mockWebRtcRenderer(WidgetTester tester) {
  const ch = MethodChannel('FlutterWebRTC.Method');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(ch, (c) async => c.method == 'createVideoRenderer' ? {'textureId': 1} : null);
  addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
}

Widget _buildScopedApp({
  Key? key,
  required _FakeWinStudio winStudio,
  _FakeWebRtc? webrtc,
  SessionState? staticSession,
  AppSettings? staticSettings,
}) => ProviderScope(
  key: key,
  overrides: [
    platformServiceProvider.overrideWithValue(const _FakeDesktopPlatform()),
    networkAddressServiceProvider.overrideWithValue(const _FakeNetAddress()),
    lanDiscoveryServiceProvider.overrideWith((ref) { final s = _FakeDiscovery(); ref.onDispose(s.dispose); return s; }),
    signalingServerServiceProvider.overrideWith((ref) { final s = _FakeServer(); ref.onDispose(s.dispose); return s; }),
    signalingClientServiceProvider.overrideWith((ref) { final s = _FakeClient(); ref.onDispose(s.dispose); return s; }),
    usbBridgeServiceProvider.overrideWithValue(_FakeUsbBridge()),
    windowsStudioServiceProvider.overrideWithValue(winStudio),
    if (webrtc != null) webrtcSessionServiceProvider.overrideWithValue(webrtc),
    if (staticSession != null) sessionProvider.overrideWith(() => _StaticSessionNotifier(staticSession)),
    if (staticSettings != null) appSettingsProvider.overrideWith(() => _StaticSettingsNotifier(staticSettings)),
  ],
  child: const Phone2ScreenApp(),
);

void main() {
  testWidgets('Simple mode lobby renders SimpleWebcamCard and 1-click registration toggles Phone2Screen Camera', (tester) async {
    _setViewport(tester, const Size(1200, 800));
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final winStudio = _FakeWinStudio();

    await tester.pumpWidget(_buildScopedApp(winStudio: winStudio));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleWebcamCard), findsOneWidget);
    expect(find.text('Use as PC Webcam — No OBS Required'), findsOneWidget);
    expect(find.text('1-Click Setup — No Admin Needed'), findsOneWidget);
    expect(find.text('Enable Windows Webcam'), findsOneWidget);
    expect(find.text('Virtual Cam & OBS'), findsNothing);
    expect(find.text('+ Open Camera Window'), findsNothing);

    await tester.tap(find.text('Enable Windows Webcam'));
    await tester.pumpAndSettle();
    expect(winStudio.registerCalls, 1);
    expect(find.text('Phone2Screen Camera Ready'), findsOneWidget);
    expect(find.textContaining('Phone2Screen Camera'), findsAtLeastNWidgets(1));
    expect(find.text('Disable Webcam'), findsOneWidget);

    await tester.tap(find.text('Disable Webcam'));
    await tester.pumpAndSettle();
    expect(winStudio.unregisterCalls, 1);
    expect(find.text('1-Click Setup — No Admin Needed'), findsOneWidget);
    expect(find.text('Enable Windows Webcam'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(WorkspaceModePill).first, matching: find.text('Studio')));
    await tester.pumpAndSettle();
    expect(find.text('Virtual Cam & OBS'), findsOneWidget);
    expect(find.text('+ Open Camera Window'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ReceiverControlsBar hides Studio tools in Simple mode and reveals them in Studio mode', (tester) async {
    _mockWebRtcRenderer(tester);
    _setViewport(tester, const Size(1200, 800));
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });

    await tester.pumpWidget(_buildScopedApp(
      winStudio: _FakeWinStudio(),
      webrtc: _FakeWebRtc(),
      staticSession: SessionState(phase: .streaming, connectedPeerName: 'Pixel 9', remoteStream: _FakeMediaStream()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ReceiverControlsBar), findsOneWidget);
    expect(find.text('Camera Rig'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('+ Window'), findsNothing);
    expect(find.byTooltip('Live Stats (S)'), findsNothing);
    expect(find.byTooltip('Share Text (C)'), findsNothing);

    await tester.tap(find.descendant(of: find.byType(WorkspaceModePill), matching: find.text('Studio')));
    await tester.pumpAndSettle();
    expect(find.text('+ Window'), findsOneWidget);
    expect(find.byTooltip('Live Stats (S)'), findsOneWidget);
    expect(find.byTooltip('Share Text (C)'), findsOneWidget);
    expect(find.text('Camera Rig'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Privacy Freeze-Frame via Pause button and P key toggles Camera Paused overlay and cam_ctrl', (tester) async {
    _mockWebRtcRenderer(tester);
    _setViewport(tester, const Size(1200, 800));
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final webrtc = _FakeWebRtc();

    await tester.pumpWidget(_buildScopedApp(
      winStudio: _FakeWinStudio(),
      webrtc: webrtc,
      staticSession: SessionState(phase: .streaming, connectedPeerName: 'Pixel 9', remoteStream: _FakeMediaStream()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Camera Paused'), findsNothing);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Camera Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: true));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Camera Paused'), findsNothing);
    expect(find.text('Pause'), findsOneWidget);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: false));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Camera Paused'), findsOneWidget);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: true));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Camera Paused'), findsNothing);
    expect(webrtc.sentCommands.last, const RemoteCameraCommand(command: .videoPause, enabled: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compact 390x844 and desktop 1200x800 layouts render Simple and Studio modes with zero overflow', (tester) async {
    _mockWebRtcRenderer(tester);
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });

    for (final size in const [Size(390, 844), Size(1200, 800)]) {
      final compact = size.width < 640;
      for (final mode in WorkspaceMode.values) {
        _setViewport(tester, size);
        await tester.pumpWidget(_buildScopedApp(
          key: ValueKey('lobby-${size.width}-${mode.name}'),
          winStudio: _FakeWinStudio(),
          staticSettings: AppSettings(workspaceMode: mode),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(SimpleWebcamCard), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(_buildScopedApp(
          key: ValueKey('stage-${size.width}-${mode.name}'),
          winStudio: _FakeWinStudio(),
          webrtc: _FakeWebRtc(),
          staticSettings: AppSettings(workspaceMode: mode),
          staticSession: SessionState(phase: .streaming, connectedPeerName: 'Pixel 9', remoteStream: _FakeMediaStream()),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(ReceiverControlsBar), findsOneWidget);
        if (compact) {
          expect(find.text('Camera Rig'), findsNothing);
          expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
        } else {
          expect(find.text('Camera Rig'), findsOneWidget);
          expect(find.text('+ Window'), mode == .studio ? findsOneWidget : findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
