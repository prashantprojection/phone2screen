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
    'iriun', 'camo', 'ndi', 'elgato', 'xsplit', 'phone2screen',
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

/// Status of the zero-OBS native Windows DirectShow Virtual Camera (`p2s_vcam.dll`).
class const NativeVirtualCamStatus({
  final bool isSupported = false,
  final bool isRegistered = false,
  final bool dllFound = false,
  final String dllPath = '',
  final int activeState = 0,
  final String deviceName = 'Phone2Screen Camera',
}) {
  bool get isStreaming => activeState == 1;
  bool get isPaused => activeState == 2;

  NativeVirtualCamStatus copyWith({
    bool? isSupported,
    bool? isRegistered,
    bool? dllFound,
    String? dllPath,
    int? activeState,
    String? deviceName,
  }) => NativeVirtualCamStatus(
    isSupported: isSupported ?? this.isSupported,
    isRegistered: isRegistered ?? this.isRegistered,
    dllFound: dllFound ?? this.dllFound,
    dllPath: dllPath ?? this.dllPath,
    activeState: activeState ?? this.activeState,
    deviceName: deviceName ?? this.deviceName,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeVirtualCamStatus &&
          runtimeType == other.runtimeType &&
          isSupported == other.isSupported &&
          isRegistered == other.isRegistered &&
          dllFound == other.dllFound &&
          dllPath == other.dllPath &&
          activeState == other.activeState &&
          deviceName == other.deviceName;

  @override
  int get hashCode => Object.hash(
    isSupported,
    isRegistered,
    dllFound,
    dllPath,
    activeState,
    deviceName,
  );
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

  /// Queries HKCU registration and shared-memory status for `p2s_vcam.dll`.
  Future<NativeVirtualCamStatus> getVirtualCamStatus() async {
    if (!isSupported) return const NativeVirtualCamStatus();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getVirtualCamStatus',
      );
      if (raw == null) return const NativeVirtualCamStatus(isSupported: true);
      final name = raw['deviceName'];
      return NativeVirtualCamStatus(
        isSupported: true,
        isRegistered: raw['registered'] == true,
        dllFound: raw['dllFound'] == true,
        dllPath: raw['dllPath'] is String ? raw['dllPath'] as String : '',
        activeState: raw['state'] is int ? raw['state'] as int : 0,
        deviceName: (name is String && name.trim().isNotEmpty)
            ? name
            : 'Phone2Screen Camera',
      );
    } on MissingPluginException {
      return const NativeVirtualCamStatus();
    } on PlatformException {
      return const NativeVirtualCamStatus();
    }
  }

  /// Registers `p2s_vcam.dll` per-user in `HKCU` and enters Standby (`0`).
  Future<bool> registerVirtualCam() => _invokeBool('registerVirtualCam');

  /// Unregisters `p2s_vcam.dll` from `HKCU` without requiring elevation.
  Future<bool> unregisterVirtualCam() => _invokeBool('unregisterVirtualCam');

  /// Updates the virtual camera shared memory state (`0`=Standby, `1`=Live, `2`=Paused).
  Future<bool> setVirtualCamState(int state) =>
      _invokeBool('setVirtualCamState', {'state': state.clamp(0, 2)});

  /// Pushes a top-down RGBA8888 frame to the 1280x720 DirectShow shared memory.
  Future<bool> pushVirtualCamFrame({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
  }) {
    if (!isSupported ||
        width <= 0 ||
        height <= 0 ||
        rgbaBytes.length < width * height * 4) {
      return Future.value(false);
    }
    return _invokeBool('pushVirtualCamFrame', {
      'bytes': rgbaBytes,
      'width': width,
      'height': height,
    });
  }

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
