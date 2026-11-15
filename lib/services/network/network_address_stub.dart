import '../../models/network_interface_info.dart';

/// Web stub: browsers cannot enumerate local NICs via `dart:io`.
Future<List<NetworkInterfaceInfo>> listInterfaces() async => const [];

/// Web stub fallback address when local interface enumeration is unavailable.
Future<String> resolvePrimaryIp() async => '127.0.0.1';
