import '../../models/network_interface_info.dart';
import 'network_address_stub.dart'
    if (dart.library.io) 'network_address_io.dart'
    as impl;

/// Enumerates and ranks local IPv4 network interfaces for LAN hosting.
class const NetworkAddressService() {
  /// Returns filtered and ranked IPv4 interface candidates, with the top choice
  /// marked `isPreferred: true`.
  Future<List<NetworkInterfaceInfo>> listInterfaces() => impl.listInterfaces();

  /// Resolves the best local IPv4 address for LAN signaling, falling back to
  /// `'127.0.0.1'` when no usable network interface is available.
  Future<String> resolvePrimaryIp() => impl.resolvePrimaryIp();
}
