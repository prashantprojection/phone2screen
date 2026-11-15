import 'signaling_data.dart';

/// LAN or USB-loopback peer discovered for connection.
class const DiscoveredPeer({
  required final SignalingData endpoint,
  required final DateTime lastSeen,
  final bool isUsbLoopback = false,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredPeer &&
          runtimeType == other.runtimeType &&
          endpoint == other.endpoint &&
          lastSeen == other.lastSeen &&
          isUsbLoopback == other.isUsbLoopback;

  @override
  int get hashCode => Object.hash(endpoint, lastSeen, isUsbLoopback);
}
