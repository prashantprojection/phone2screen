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
import 'package:phone2screen/services/network/lan_discovery_service.dart';
import 'package:phone2screen/services/network/network_address_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';

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
    NetworkInterfaceInfo(name: 'Wi-Fi', address: '192.168.1.55', isPreferred: true),
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
  @override
  Stream<SignalingMessage> get messages => _messages.stream;
  @override
  Stream<bool> get clientConnectionEvents => _events.stream;
  @override
  int? get boundPort => _port;
  @override
  bool get isRunning => _port != null;
  @override
  Future<int> start({
    int preferredPort = 8080,
    required String sessionId,
    required String deviceName,
    String? pin,
  }) async => _port = preferredPort == 0 ? 8080 : preferredPort;
  @override
  void send(SignalingMessage message) {}
  @override
  Future<void> disconnectClient([String reason = 'Host ended session']) async {}
  @override
  Future<void> stop() async => _port = null;
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

void main() {
  testWidgets('renders ReceiverScreen, switches to SenderScreen, opens SettingsScreen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(const _FakePlatformService()),
          networkAddressServiceProvider.overrideWithValue(const _FakeNetworkAddressService()),
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
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Phone2Screen'), findsOneWidget);
    expect(find.textContaining('Ready to Receive'), findsOneWidget);
    expect(find.text('192.168.1.55'), findsAtLeastNWidgets(1));
    expect(find.text('http://192.168.1.55:8080'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Broadcast Source'), findsOneWidget);
    expect(find.text('Nearby Receivers'), findsOneWidget);
    expect(find.text('Manual IP Connect'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Stream Quality'), findsOneWidget);
    expect(find.text('Eco Dim Preview'), findsOneWidget);
  });
}
