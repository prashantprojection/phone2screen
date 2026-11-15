import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/device_role.dart';

/// Platform capability detector and safe device-name resolver.
class const PlatformDetectionService() {
  /// Defaults desktop and browser builds to Receiver, and phones to Sender.
  DeviceRole get defaultRole => (kIsWeb || isDesktop) ? .receiver : .sender;

  /// True on Windows, macOS, and Linux targets (native or web user-agent).
  bool get isDesktop =>
      defaultTargetPlatform == .windows ||
      defaultTargetPlatform == .macOS ||
      defaultTargetPlatform == .linux;

  /// True on Android, iOS, and Fuchsia targets.
  bool get isMobile =>
      defaultTargetPlatform == .android ||
      defaultTargetPlatform == .iOS ||
      defaultTargetPlatform == .fuchsia;

  /// True when compiled for web browsers.
  bool get isWeb => kIsWeb;

  /// Native builds can bind an embedded HTTP/WS server and UDP discovery socket.
  bool get canHostServer => !kIsWeb;

  /// Camera QR scanning is enabled on native mobile devices.
  bool get supportsQrScanner => !kIsWeb && isMobile;

  /// Screen/window thumbnail picking is supported on native desktop targets.
  bool get supportsDesktopPicker => !kIsWeb && isDesktop;

  /// Human-readable platform label used as fallback device identity.
  String get platformLabel {
    final os = switch (defaultTargetPlatform) {
      .android => 'Android',
      .iOS => 'iOS',
      .windows => 'Windows',
      .macOS => 'macOS',
      .linux => 'Linux',
      .fuchsia => 'Fuchsia',
    };
    return kIsWeb ? 'Web ($os)' : os;
  }

  /// Resolves a friendly local device name with safe fallback for tests/web.
  Future<String> resolveDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        final browser = info.browserName.name;
        return browser.isEmpty ? platformLabel : 'Web ($browser)';
      }

      final raw = switch (defaultTargetPlatform) {
        .android => _formatAndroidName(await plugin.androidInfo),
        .iOS => (await plugin.iosInfo).name,
        .windows => (await plugin.windowsInfo).computerName,
        .macOS => (await plugin.macOsInfo).computerName,
        .linux => (await plugin.linuxInfo).prettyName,
        .fuchsia => platformLabel,
      };
      final trimmed = raw.trim();
      return trimmed.isEmpty ? platformLabel : trimmed;
    } catch (_) {
      return platformLabel;
    }
  }

  static String _formatAndroidName(AndroidDeviceInfo info) {
    final model = info.model.trim();
    final brand = info.brand.trim();
    if (model.isEmpty) return brand;
    if (brand.isEmpty || model.toLowerCase().startsWith(brand.toLowerCase())) {
      return model;
    }
    return '$brand $model';
  }
}
