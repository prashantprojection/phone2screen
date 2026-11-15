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
import 'package:phone2screen/providers/discovery_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/services/network/lan_discovery_service.dart';
import 'package:phone2screen/services/network/network_address_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/views/shared/app_shell_header.dart';

class const _FakePlatformService() extends PlatformDetectionService {
  @override
  DeviceRole get defaultRole => .receiver;
  @override
  bool get canHostServer => true;
  @override
  bool get supportsQrScanner => false;
  @override
  bool get supportsDesktopPicker => true;
  @override
  Future<String> resolveDeviceName() async => 'Test Desktop';
}

class const _FakeNetworkAddressService() implements NetworkAddressService {
  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() async => const [
    NetworkInterfaceInfo(
      name: 'Wi-Fi',
      address: '192.168.1.55',
      isPreferred: true,
    ),
  ];
  @override
  Future<String> resolvePrimaryIp() async => '192.168.1.55';
}

class _FakeLanDiscoveryService implements LanDiscoveryService {
  final _controller = StreamController<List<DiscoveredPeer>>.broadcast();
  @override
  Stream<List<DiscoveredPeer>> get peersStream => _controller.stream;
  @override
  List<DiscoveredPeer> get currentPeers => const [];
  @override
  Future<void> startBroadcasting(SignalingData hostInfo) async {}
  @override
  Future<void> stopBroadcasting() async {}
  @override
  Future<void> startListening() async {
    if (!_controller.isClosed) _controller.add(const []);
  }
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> dispose() => _controller.close();
}

class _FakeSignalingServerService implements SignalingServerService {
  final _messages = StreamController<SignalingMessage>.broadcast();
  final _events = StreamController<bool>.broadcast();
  int? _port;
  int? _httpsPort;
  WebCompanionMode _companionMode = .sendToReceiver;

  @override
  Stream<SignalingMessage> get messages => _messages.stream;
  @override
  Stream<bool> get clientConnectionEvents => _events.stream;
  @override
  int? get boundPort => _port;
  @override
  int? get boundHttpsPort => _httpsPort;
  @override
  WebCompanionMode get companionMode => _companionMode;
  @override
  bool get isRunning => _port != null;

  @override
  Future<int> start({
    int preferredPort = 8080,
    int? preferredHttpsPort = 8443,
    WebCompanionMode companionMode = .sendToReceiver,
    required String sessionId,
    required String deviceName,
    String? pin,
  }) async {
    _httpsPort = preferredHttpsPort;
    _companionMode = companionMode;
    return _port = preferredPort == 0 ? 8080 : preferredPort;
  }

  @override
  void send(SignalingMessage message) {}
  @override
  Future<void> disconnectClient([String reason = 'Host ended session']) async {}
  @override
  Future<void> stop() async {
    _port = null;
    _httpsPort = null;
  }

  @override
  Future<void> dispose() async {
    await _messages.close();
    await _events.close();
  }
}

class _FakeSignalingClientService implements SignalingClientService {
  final _messages = StreamController<SignalingMessage>.broadcast();
  final _disconnected = StreamController<void>.broadcast();
  @override
  Stream<SignalingMessage> get messages => _messages.stream;
  @override
  Stream<void> get onDisconnected => _disconnected.stream;
  @override
  bool get isConnected => false;
  @override
  Future<void> connect({
    required SignalingData target,
    required String clientDeviceName,
    String? pin,
  }) async {}
  @override
  void send(SignalingMessage message) {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {
    await _messages.close();
    await _disconnected.close();
  }
}

class _StreamingSessionNotifier extends SessionNotifier {
  @override
  SessionState build() =>
      const SessionState(phase: .streaming, connectedPeerName: 'Pixel Phone');
}

Widget _buildTestApp() {
  return ProviderScope(
    overrides: [
      platformServiceProvider.overrideWithValue(const _FakePlatformService()),
      networkAddressServiceProvider.overrideWithValue(
        const _FakeNetworkAddressService(),
      ),
      lanDiscoveryServiceProvider.overrideWith((ref) {
        final s = _FakeLanDiscoveryService();
        ref.onDispose(s.dispose);
        return s;
      }),
      signalingServerServiceProvider.overrideWith((ref) {
        final s = _FakeSignalingServerService();
        ref.onDispose(s.dispose);
        return s;
      }),
      signalingClientServiceProvider.overrideWith((ref) {
        final s = _FakeSignalingClientService();
        ref.onDispose(s.dispose);
        return s;
      }),
    ],
    child: const Phone2ScreenApp(),
  );
}

void main() {
  testWidgets(
    'renders simplified Receiver, How to Use guide, Send tab, and Settings',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Phone2Screen'), findsOneWidget);
      expect(find.text('Ready on Test Desktop'), findsOneWidget);
      expect(find.text('192.168.1.55'), findsAtLeastNWidgets(1));
      expect(find.textContaining('UDP 41234'), findsNothing);

      final advancedDetails = find.text('Advanced Network Details');
      await tester.ensureVisible(advancedDetails);
      await tester.pumpAndSettle();
      await tester.tap(advancedDetails);
      await tester.pumpAndSettle();
      expect(find.text('http://192.168.1.55:8080'), findsOneWidget);

      await tester.tap(find.byTooltip('How to Use (G)'));
      await tester.pumpAndSettle();
      expect(find.text('How to Use Phone2Screen'), findsOneWidget);
      expect(find.text('Phone to PC'), findsOneWidget);
      expect(find.text('Watch in Any Browser'), findsOneWidget);
      expect(find.text('Phone Browser to PC'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('How to Use Phone2Screen'), findsNothing);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Share Camera or Screen'), findsOneWidget);
      expect(find.text('What to Share'), findsOneWidget);
      expect(find.text('Nearby Screens'), findsOneWidget);
      expect(find.text('Cast to Web Browser'), findsOneWidget);
      expect(find.text('Enter IP Manually'), findsOneWidget);
      expect(find.textContaining('UDP 41234'), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Video & Audio'), findsOneWidget);
      expect(find.text('Battery Saver Preview'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Keyboard Shortcuts'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('How to Use Phone2Screen'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('How to Use Phone2Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'renders compact phone layout across Receive, Send, and Settings with zero overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Ready on Test Desktop'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Share Camera or Screen'), findsOneWidget);
      expect(find.text('What to Share'), findsOneWidget);
      expect(find.text('Nearby Screens'), findsOneWidget);
      expect(find.text('Cast to Web Browser'), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Customize Shortcut Keys'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Customize Shortcut Keys'), findsOneWidget);
      expect(find.text('Fullscreen'), findsNothing);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('streaming-scope'),
          overrides: [
            platformServiceProvider.overrideWithValue(
              const _FakePlatformService(),
            ),
            sessionProvider.overrideWith(_StreamingSessionNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(appBar: AppShellHeader(onOpenSettings: () {})),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Fullscreen (F)'), findsOneWidget);
    },
  );
}
