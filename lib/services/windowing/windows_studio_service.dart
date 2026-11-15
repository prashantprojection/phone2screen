import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native DirectShow video capture endpoint reported by Windows.
class const VideoCaptureDeviceInfo({
  required final String name,
  final String devicePath = '',
  final bool isVirtualCam = false,
}) {
  static const List<String> _virtualCamTokens = [
    'obs', 'virtual', 'unitycapture', 'droidcam',
    'iriun', 'camo', 'ndi', 'elgato', 'xsplit',
  ];

  /// Returns `true` when [name] matches a known virtual camera driver token.
  static bool detectVirtualCamName(String name) {
    final lower = name.toLowerCase();
    return _virtualCamTokens.any(lower.contains);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoCaptureDeviceInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          devicePath == other.devicePath &&
          isVirtualCam == other.isVirtualCam;

  @override
  int get hashCode => Object.hash(name, devicePath, isVirtualCam);
}

/// Native WinMM wave-out audio playback device reported by Windows.
class const WinAudioDeviceInfo({
  required final String id,
  required final String name,
  final bool isVirtualCable = false,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WinAudioDeviceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isVirtualCable == other.isVirtualCable;

  @override
  int get hashCode => Object.hash(id, name, isVirtualCable);
}

/// Flutter MethodChannel client for the Windows `phone2screen/windows_studio`
/// Win32 bridge (DirectShow cameras, WaveOut outputs, and Always-On-Top).
class WindowsStudioService {
  WindowsStudioService({MethodChannel? channel, this._isSupportedOverride})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'phone2screen/windows_studio',
  );

  final MethodChannel _channel;
  final bool? _isSupportedOverride;

  /// Whether the Windows native studio bridge is available on this target.
  bool get isSupported =>
      _isSupportedOverride ?? (!kIsWeb && defaultTargetPlatform == .windows);

  /// Enumerates DirectShow video capture devices and tags virtual cameras.
  Future<List<VideoCaptureDeviceInfo>> listVideoCaptureDevices() async {
    final raw = await _invokeList('listVideoCaptureDevices');
    final devices = <VideoCaptureDeviceInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is! String || name.trim().isEmpty) continue;
      final path = item['devicePath'] is String ? item['devicePath'] as String : '';
      final isVirtual = item['isVirtualCam'] is bool
          ? item['isVirtualCam'] as bool
          : VideoCaptureDeviceInfo.detectVirtualCamName(name);
      devices.add(VideoCaptureDeviceInfo(
        name: name,
        devicePath: path,
        isVirtualCam: isVirtual,
      ));
    }
    return List.unmodifiable(devices);
  }

  /// Enumerates Win32 waveOut audio output devices and tags virtual cables.
  Future<List<WinAudioDeviceInfo>> listAudioOutputDevices() async {
    final raw = await _invokeList('listAudioOutputDevices');
    final devices = <WinAudioDeviceInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is! String || name is! String || name.trim().isEmpty) continue;
      final isVirtual = item['isVirtualCable'] is bool
          ? item['isVirtualCable'] as bool
          : false;
      devices.add(WinAudioDeviceInfo(id: id, name: name, isVirtualCable: isVirtual));
    }
    return List.unmodifiable(devices);
  }

  /// Pins or unpins the native Win32 window above other windows.
  Future<bool> setAlwaysOnTop(bool enabled) =>
      _invokeBool('setAlwaysOnTop', {'enabled': enabled});

  /// Queries whether the native Win32 window currently has `WS_EX_TOPMOST`.
  Future<bool> getAlwaysOnTop() => _invokeBool('getAlwaysOnTop');

  Future<List<Object?>> _invokeList(String method) async {
    if (!isSupported) return const [];
    try {
      return await _channel.invokeListMethod<Object?>(method) ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
