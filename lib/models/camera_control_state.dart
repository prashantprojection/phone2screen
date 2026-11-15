import 'dart:math' as math;

import 'media_source_type.dart';

/// Remote camera actions sent from a Receiver HUD to the broadcasting Sender.
enum RemoteCameraCommandType {
  flip,
  torch,
  micMute,
  zoom,
  exposure,
  focusLock,
  voiceMode,
  videoPause,
}

/// Control command transmitted over the `phone2screen-control` DataChannel.
class const RemoteCameraCommand({
  required final RemoteCameraCommandType command,
  final double? value,
  final bool? enabled,
}) {
  /// Encodes this command as a `cam_ctrl` JSON frame.
  Map<String, dynamic> toJson() => {
    'kind': 'cam_ctrl',
    'cmd': command.name,
    if (value != null) 'value': value,
    if (enabled != null) 'enabled': enabled,
  };

  /// Parses a `cam_ctrl` JSON frame, returning `null` if malformed or unknown.
  static RemoteCameraCommand? tryFromJson(Map<String, dynamic> map) {
    if (map['kind'] != 'cam_ctrl') return null;
    final parsed = _findEnum(RemoteCameraCommandType.values, map['cmd']);
    if (parsed == null) return null;
    return RemoteCameraCommand(
      command: parsed,
      value: _asFiniteDouble(map['value']),
      enabled: map['enabled'] is bool ? map['enabled'] as bool : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteCameraCommand &&
          runtimeType == other.runtimeType &&
          command == other.command &&
          value == other.value &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(command, value, enabled);
}

/// Authoritative remote camera hardware state broadcast by the active Sender.
class const RemoteCameraState({
  final CameraLens lens = .back,
  final bool torchOn = false,
  final bool micMuted = false,
  final double zoom = 1.0,
  final double minZoom = 1.0,
  final double maxZoom = 5.0,
  final double exposureOffset = 0.0,
  final bool focusLocked = false,
  final bool controlsSupported = true,
  final bool voiceClean = true,
  final bool videoPaused = false,
}) {
  /// Returns an updated copy of [RemoteCameraState].
  RemoteCameraState copyWith({
    CameraLens? lens,
    bool? torchOn,
    bool? micMuted,
    double? zoom,
    double? minZoom,
    double? maxZoom,
    double? exposureOffset,
    bool? focusLocked,
    bool? controlsSupported,
    bool? voiceClean,
    bool? videoPaused,
  }) => RemoteCameraState(
    lens: lens ?? this.lens,
    torchOn: torchOn ?? this.torchOn,
    micMuted: micMuted ?? this.micMuted,
    zoom: zoom ?? this.zoom,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    exposureOffset: exposureOffset ?? this.exposureOffset,
    focusLocked: focusLocked ?? this.focusLocked,
    controlsSupported: controlsSupported ?? this.controlsSupported,
    voiceClean: voiceClean ?? this.voiceClean,
    videoPaused: videoPaused ?? this.videoPaused,
  );

  /// Encodes this state as a `cam_state` JSON frame.
  Map<String, dynamic> toJson() => {
    'kind': 'cam_state',
    'lens': lens.name,
    'torchOn': torchOn,
    'micMuted': micMuted,
    'zoom': zoom,
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'exposureOffset': exposureOffset,
    'focusLocked': focusLocked,
    'controlsSupported': controlsSupported,
    'voiceClean': voiceClean,
    'videoPaused': videoPaused,
  };

  /// Parses a `cam_state` JSON frame, returning `null` when invalid.
  static RemoteCameraState? tryFromJson(Map<String, dynamic> map) {
    if (map['kind'] != 'cam_state') return null;
    final minZ = math.max(1.0, _asFiniteDouble(map['minZoom']) ?? 1.0);
    final maxZ = math.max(minZ, _asFiniteDouble(map['maxZoom']) ?? 5.0);
    return RemoteCameraState(
      lens: _findEnum(CameraLens.values, map['lens']) ?? .back,
      torchOn: _asBool(map['torchOn']),
      micMuted: _asBool(map['micMuted']),
      zoom: (_asFiniteDouble(map['zoom']) ?? 1.0).clamp(minZ, maxZ),
      minZoom: minZ,
      maxZoom: maxZ,
      exposureOffset: (_asFiniteDouble(map['exposureOffset']) ?? 0.0).clamp(
        -4.0,
        4.0,
      ),
      focusLocked: _asBool(map['focusLocked']),
      controlsSupported: _asBool(map['controlsSupported'], true),
      voiceClean: _asBool(map['voiceClean'], true),
      videoPaused: _asBool(map['videoPaused']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteCameraState &&
          runtimeType == other.runtimeType &&
          lens == other.lens &&
          torchOn == other.torchOn &&
          micMuted == other.micMuted &&
          zoom == other.zoom &&
          minZoom == other.minZoom &&
          maxZoom == other.maxZoom &&
          exposureOffset == other.exposureOffset &&
          focusLocked == other.focusLocked &&
          controlsSupported == other.controlsSupported &&
          voiceClean == other.voiceClean &&
          videoPaused == other.videoPaused;

  @override
  int get hashCode => Object.hash(
    lens,
    torchOn,
    micMuted,
    zoom,
    minZoom,
    maxZoom,
    exposureOffset,
    focusLocked,
    controlsSupported,
    voiceClean,
    videoPaused,
  );
}

T? _findEnum<T extends Enum>(List<T> values, Object? raw) =>
    raw is String ? values.where((v) => v.name == raw).firstOrNull : null;

bool _asBool(Object? raw, [bool fallback = false]) =>
    raw is bool ? raw : fallback;

double? _asFiniteDouble(Object? raw) {
  final parsed = switch (raw) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };
  return (parsed != null && parsed.isFinite) ? parsed : null;
}
