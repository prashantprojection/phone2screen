import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_role.dart';
import '../services/platform_detection_service.dart';

/// Singleton platform capability detector.
final platformServiceProvider = Provider<PlatformDetectionService>(
  (ref) => const PlatformDetectionService(),
);

/// Active runtime role (`receiver` vs `sender`) toggled by the user.
final activeRoleProvider = NotifierProvider<ActiveRoleNotifier, DeviceRole>(
  ActiveRoleNotifier.new,
);

/// Notifier managing manual runtime role switches between Receiver and Sender.
class ActiveRoleNotifier extends Notifier<DeviceRole> {
  @override
  DeviceRole build() => ref.watch(platformServiceProvider).defaultRole;

  /// Explicitly sets the active [DeviceRole].
  void setRole(DeviceRole role) => state = role;

  /// Toggles between [DeviceRole.receiver] and [DeviceRole.sender].
  void toggleRole() => state = state == .receiver ? .sender : .receiver;
}

/// Asynchronous friendly name for this device used during LAN pairing.
final deviceNameProvider = FutureProvider<String>(
  (ref) => ref.watch(platformServiceProvider).resolveDeviceName(),
);
