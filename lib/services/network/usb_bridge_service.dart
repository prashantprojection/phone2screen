import 'package:flutter/foundation.dart';

import '../../models/discovered_peer.dart';
import 'usb_bridge_stub.dart'
    if (dart.library.io) 'usb_bridge_io.dart'
    as impl;

/// Snapshot of local ADB reverse-tunnel availability and connected devices.
class const UsbBridgeStatus({
  final bool adbAvailable = false,
  final List<String> connectedSerials = const [],
  final List<String> unauthorizedSerials = const [],
  final List<int> forwardedPorts = const [],
}) {
  bool get hasActiveTunnel =>
      connectedSerials.isNotEmpty && forwardedPorts.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbBridgeStatus &&
          runtimeType == other.runtimeType &&
          adbAvailable == other.adbAvailable &&
          listEquals(connectedSerials, other.connectedSerials) &&
          listEquals(unauthorizedSerials, other.unauthorizedSerials) &&
          listEquals(forwardedPorts, other.forwardedPorts);

  @override
  int get hashCode => Object.hash(
    adbAvailable,
    Object.hashAll(connectedSerials),
    Object.hashAll(unauthorizedSerials),
    Object.hashAll(forwardedPorts),
  );
}

/// Injectable command runner used to execute `adb` without spawning real
/// processes during unit tests.
typedef UsbProcessRunner =
    Future<({int exitCode, String stdout, String stderr})> Function(
      String exe,
      List<String> args,
    );

/// Zero-config USB plug-and-play helper managing `adb reverse` port tunnels on
/// desktop and fast `127.0.0.1` loopback `/p2s-info` receiver probing on phones.
class UsbBridgeService {
  UsbBridgeService({UsbProcessRunner? processRunner, bool? allowInTestOverride})
    : _impl = impl.UsbBridgeImpl(
        processRunner: processRunner,
        allowInTestOverride: allowInTestOverride,
      );

  final impl.UsbBridgeImpl _impl;

  /// Broadcast stream emitting updated [UsbBridgeStatus] after each ADB sync.
  Stream<UsbBridgeStatus> get statusStream => _impl.statusStream;

  /// Latest cached [UsbBridgeStatus].
  UsbBridgeStatus get currentStatus => _impl.currentStatus;

  /// Probes `adb devices` and forwards each TCP port in [ports] via
  /// `adb -s <serial> reverse tcp:<port> tcp:<port>` for connected phones.
  Future<UsbBridgeStatus> syncAdbReversePorts(List<int> ports) =>
      _impl.syncAdbReversePorts(ports);

  /// Queries `http://127.0.0.1:<port>/p2s-info` in parallel to auto-discover
  /// desktop receivers tunneled over USB (`adb reverse`).
  Future<List<DiscoveredPeer>> probeLoopbackReceivers({
    List<int> ports = const [8080, 8081, 8082, 8083],
    String? ignoreSessionId,
    Duration timeout = const Duration(milliseconds: 350),
  }) => _impl.probeLoopbackReceivers(
    ports: ports,
    ignoreSessionId: ignoreSessionId,
    timeout: timeout,
  );

  /// Releases status stream resources.
  Future<void> dispose() => _impl.dispose();
}
