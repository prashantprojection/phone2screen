import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/app.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/discovered_peer.dart';
import 'package:phone2screen/models/network_interface_info.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/models/stream_telemetry.dart';
import 'package:phone2screen/providers/discovery_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/services/network/lan_discovery_service.dart';
import 'package:phone2screen/services/network/network_address_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_controls_bar.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_streaming_stage.dart';
import 'package:phone2screen/views/receiver/widgets/remote_camera_panel.dart';
import 'package:phone2screen/views/sender/widgets/active_sender_controls.dart';
import 'package:phone2screen/views/sender/widgets/oled_tally_view.dart';
import 'package:phone2screen/views/sender/widgets/web_broadcast_card.dart';
import 'package:phone2screen/views/settings/settings_screen.dart';
import 'package:phone2screen/views/shared/app_shell_header.dart';
import 'package:phone2screen/views/shared/video_stage_widget.dart';

class const _FakePlatform({
  final DeviceRole role = .receiver,
  final bool desktop = true,
  final bool server = true,
}) extends PlatformDetectionService {
  @override DeviceRole get defaultRole => role;
  @override bool get canHostServer => server;
  @override bool get isDesktop => desktop;
  @override bool get isMobile => !desktop;
  @override bool get supportsQrScanner => !desktop;
  @override bool get supportsDesktopPicker => desktop;
  @override Future<String> resolveDeviceName() async => 'Studio Test Device';
}

class const _FakeNetService() implements NetworkAddressService {
  @override Future<List<NetworkInterfaceInfo>> listInterfaces() async => const [
    NetworkInterfaceInfo(name: 'USB Tether', address: '192.168.42.10', isPreferred: true, isUsbTethered: true),
  ];
  @override Future<String> resolvePrimaryIp() async => '192.168.42.10';
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

class _StaticSessionNotifier extends SessionNotifier {
  final SessionState initial;
  _StaticSessionNotifier(this.initial);
  @override SessionState build() => initial;
  @override Future<void> startHosting({bool forceRestart = false}) async {}
  @override Future<void> startDiscovery() async {}
}

Widget _scoped({
  Key? key,
  PlatformDetectionService platform = const _FakePlatform(),
  SessionState? staticSession,
  required Widget child,
}) => ProviderScope(
  key: key,
  overrides: [
    platformServiceProvider.overrideWithValue(platform),
    networkAddressServiceProvider.overrideWithValue(const _FakeNetService()),
    lanDiscoveryServiceProvider.overrideWith((ref) { final s = _FakeDiscovery(); ref.onDispose(s.dispose); return s; }),
    signalingServerServiceProvider.overrideWith((ref) { final s = _FakeServer(); ref.onDispose(s.dispose); return s; }),
    signalingClientServiceProvider.overrideWith((ref) { final s = _FakeClient(); ref.onDispose(s.dispose); return s; }),
    if (staticSession != null) sessionProvider.overrideWith(() => _StaticSessionNotifier(staticSession)),
  ],
  child: child,
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  testWidgets('Phone2ScreenApp hides AppShellHeader in OLED tally and uses edge-to-edge stages', (tester) async {
    _setViewport(tester, const Size(390, 844));
    addTearDown(() => _resetViewport(tester));

    const live = SessionState(
      phase: .streaming,
      connectedPeerName: 'Studio PC',
      telemetry: StreamTelemetry(connectedDuration: Duration(seconds: 42)),
    );
    await tester.pumpWidget(_scoped(
      platform: const _FakePlatform(role: .sender, desktop: false, server: true),
      staticSession: live,
      child: const Phone2ScreenApp(),
    ));
    await tester.pump();

    expect(find.byType(AppShellHeader), findsOneWidget);
    expect(find.byType(ActiveSenderControls), findsOneWidget);
    expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);

    await tester.tap(find.text('Battery Saver'));
    await tester.pump();
    expect(find.byType(OledTallyView), findsOneWidget);
    expect(find.text('ON AIR'), findsOneWidget);
    expect(find.byType(AppShellHeader), findsNothing);

    await tester.tap(find.text('Wake Preview'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(OledTallyView), findsNothing);
    expect(find.byType(AppShellHeader), findsOneWidget);
    expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);
  });

  testWidgets('RemoteCameraPanel.show uses right drawer on desktop and BottomSheet on compact', (tester) async {
    Future<void> pumpStage(Size size) async {
      _setViewport(tester, size);
      await tester.pumpWidget(_scoped(
        key: ValueKey(size),
        platform: _FakePlatform(desktop: size.width >= 640),
        staticSession: const SessionState(phase: .streaming, connectedPeerName: 'Pixel 8'),
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ReceiverStreamingStage(
                session: ref.watch(sessionProvider),
                display: ref.watch(viewerDisplayProvider),
                onExitFullscreen: () {},
                onDismissError: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    addTearDown(() => _resetViewport(tester));

    await pumpStage(const Size(1200, 800));
    expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);
    await tester.tap(find.text('Camera Rig'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteCameraPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.widget<Align>(find.ancestor(of: find.byType(RemoteCameraPanel), matching: find.byType(Align)).first).alignment,
      Alignment.centerRight,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await pumpStage(const Size(390, 844));
    expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);
    expect(find.byType(ReceiverControlsBar), findsOneWidget);
    expect(find.text('Camera Rig'), findsNothing);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(RemoteCameraPanel), findsOneWidget);
  });

  testWidgets('compact 390x844 and wide 1200x800 Receive, Send, Live & Settings have zero overflow', (tester) async {
    addTearDown(() => _resetViewport(tester));
    const ep = SignalingData(ip: '192.168.42.10', port: 8080, sessionId: 'UX1', deviceName: 'Studio PC');

    for (final size in const [Size(390, 844), Size(1200, 800)]) {
      _setViewport(tester, size);
      await tester.pumpWidget(_scoped(key: ValueKey('app-$size'), child: const Phone2ScreenApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Ready on Studio Test Device'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Share Camera or Screen'), findsOneWidget);

      await tester.pumpWidget(_scoped(
        key: ValueKey('live-rx-$size'),
        staticSession: const SessionState(phase: .streaming, connectedPeerName: 'Pixel 8'),
        child: const Phone2ScreenApp(),
      ));
      await tester.pump();
      expect(find.byType(ReceiverControlsBar), findsOneWidget);
      expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);

      await tester.pumpWidget(_scoped(
        key: ValueKey('live-tx-$size'),
        platform: const _FakePlatform(role: .sender, desktop: false, server: true),
        staticSession: const SessionState(phase: .streaming, connectedPeerName: 'Studio PC'),
        child: const Phone2ScreenApp(),
      ));
      await tester.pump();
      expect(find.byType(ActiveSenderControls), findsOneWidget);
      expect(tester.widget<VideoStageWidget>(find.byType(VideoStageWidget)).borderRadius, 0.0);

      await tester.pumpWidget(_scoped(
        key: ValueKey('web-$size'),
        child: const MaterialApp(
          home: Scaffold(body: WebBroadcastLobbyView(session: SessionState(phase: .hosting, activeEndpoint: ep, isWebBroadcast: true))),
        ),
      ));
      await tester.pump();
      expect(find.text('OBS Browser Source (Clean Feed)'), findsOneWidget);

      await tester.pumpWidget(_scoped(
        key: ValueKey('settings-$size'),
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Advanced & Security'), 220, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Advanced & Security'));
      await tester.pumpAndSettle();
      expect(find.text('4-Digit Pairing PIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
