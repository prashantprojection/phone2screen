import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/discovered_peer.dart';
import '../models/network_interface_info.dart';
import '../services/network/lan_discovery_service.dart';
import '../services/network/network_address_service.dart';
import '../services/network/usb_bridge_service.dart';
import '../services/signaling/signaling_client_service.dart';
import '../services/signaling/signaling_server_service.dart';

/// Injectable local IPv4 interface resolver service.
final networkAddressServiceProvider = Provider<NetworkAddressService>(
  (ref) => const NetworkAddressService(),
);

/// Injectable UDP LAN discovery service (port 41234, `P2S_V1`).
final lanDiscoveryServiceProvider = Provider<LanDiscoveryService>((ref) {
  final service = LanDiscoveryService();
  ref.onDispose(service.dispose);
  return service;
});

/// Injectable USB ADB reverse-tunnel & 127.0.0.1 loopback bridge service.
final usbBridgeServiceProvider = Provider<UsbBridgeService>((ref) {
  final service = UsbBridgeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Injectable embedded HTTP + `/ws` WebSocket signaling server.
final signalingServerServiceProvider = Provider<SignalingServerService>((ref) {
  final service = SignalingServerService();
  ref.onDispose(service.dispose);
  return service;
});

/// Injectable WebSocket signaling client for Sender sessions.
final signalingClientServiceProvider = Provider<SignalingClientService>((ref) {
  final service = SignalingClientService();
  ref.onDispose(service.dispose);
  return service;
});

/// Enumerated local IPv4 interfaces ranked with preferred LAN NICs first.
final networkInterfacesProvider = FutureProvider<List<NetworkInterfaceInfo>>(
  (ref) => ref.watch(networkAddressServiceProvider).listInterfaces(),
);

/// User-selected override IP address for hosting, or null for automatic NIC.
final selectedIpProvider = NotifierProvider<SelectedIpNotifier, String?>(
  SelectedIpNotifier.new,
);

/// Notifier storing an explicit host IP selection from the network card.
class SelectedIpNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Selects a specific local IPv4 address, or null for automatic selection.
  void selectIp(String? ip) => state = ip;
}

/// Live stream of LAN Receiver peers discovered via UDP broadcast beacons.
final discoveredPeersProvider = StreamProvider<List<DiscoveredPeer>>(
  (ref) => ref.watch(lanDiscoveryServiceProvider).peersStream,
);

/// Live stream of desktop ADB reverse-tunnel availability and forwarded ports.
final usbBridgeStatusProvider = StreamProvider<UsbBridgeStatus>(
  (ref) => ref.watch(usbBridgeServiceProvider).statusStream,
);

/// USB `127.0.0.1` loopback Receiver peers discovered via `adb reverse`.
final usbLoopbackPeersProvider =
    NotifierProvider<UsbLoopbackPeersNotifier, List<DiscoveredPeer>>(
      UsbLoopbackPeersNotifier.new,
    );

/// Probes loopback ports for USB-tunneled Receivers without blocking LAN scan.
class UsbLoopbackPeersNotifier extends Notifier<List<DiscoveredPeer>> {
  @override
  List<DiscoveredPeer> build() => const [];

  /// Probes `127.0.0.1` loopback receivers and updates the cached list.
  Future<void> refresh({String? ignoreSessionId}) async {
    final peers = await ref
        .read(usbBridgeServiceProvider)
        .probeLoopbackReceivers(ignoreSessionId: ignoreSessionId);
    if (!ref.mounted) return;
    state = List.unmodifiable(peers);
  }
}

/// Combined list of USB loopback peers (first) and UDP LAN peers, deduped.
final allDiscoveredPeersProvider = Provider<List<DiscoveredPeer>>((ref) {
  final usbPeers = ref.watch(usbLoopbackPeersProvider);
  final lanPeers = ref.watch(discoveredPeersProvider).value ?? const [];
  final merged = <DiscoveredPeer>[];
  final seen = <String>{};
  for (final peer in [...usbPeers, ...lanPeers]) {
    final sid = peer.endpoint.sessionId.trim();
    final key = sid.isNotEmpty ? sid : '${peer.endpoint.ip}:${peer.endpoint.port}';
    if (seen.add(key)) merged.add(peer);
  }
  return List.unmodifiable(merged);
});
