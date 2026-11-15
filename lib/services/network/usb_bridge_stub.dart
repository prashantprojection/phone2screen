import 'dart:async';

import '../../models/discovered_peer.dart';
import 'usb_bridge_service.dart';

/// Web stub: browser sandboxes cannot execute `adb` or probe loopback TCP.
class UsbBridgeImpl {
  UsbBridgeImpl({UsbProcessRunner? processRunner, bool? allowInTestOverride});

  final _statusController = StreamController<UsbBridgeStatus>.broadcast();

  Stream<UsbBridgeStatus> get statusStream => _statusController.stream;

  UsbBridgeStatus get currentStatus => const UsbBridgeStatus();

  Future<UsbBridgeStatus> syncAdbReversePorts(List<int> ports) async =>
      const UsbBridgeStatus();

  Future<List<DiscoveredPeer>> probeLoopbackReceivers({
    List<int> ports = const [8080, 8081, 8082, 8083],
    String? ignoreSessionId,
    Duration timeout = const Duration(milliseconds: 350),
  }) async => const [];

  Future<void> dispose() => _statusController.close();
}
