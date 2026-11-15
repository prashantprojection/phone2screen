import '../core/constants/stream_constants.dart';
import 'media_source_type.dart';
import 'stream_config.dart';

/// Named capture quality and lens preset for creator camera rigs.
class const CameraRigPreset({
  required final String id,
  required final String name,
  required final String subtitle,
  required final StreamResolution resolution,
  required final int frameRate,
  required final int videoBitrate,
  final CameraLens cameraLens = .back,
  final bool isCustom = false,
}) {
  /// Applies this preset's resolution, FPS, bitrate, and lens onto [current].
  StreamConfig applyTo(StreamConfig current) => current.copyWith(
    resolution: resolution,
    frameRate: frameRate,
    videoBitrate: videoBitrate.clamp(
      StreamConstants.minVideoBitrate,
      StreamConstants.maxVideoBitrate,
    ),
    cameraLens: cameraLens,
  );

  /// Serializes this preset to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'resolution': resolution.name,
    'frameRate': frameRate,
    'videoBitrate': videoBitrate,
    'cameraLens': cameraLens.name,
    'isCustom': isCustom,
  };

  /// Parses a [CameraRigPreset] from [json], or `null` if required fields fail.
  static CameraRigPreset? tryFromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawName = json['name'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    if (rawName is! String || rawName.trim().isEmpty) return null;

    final resolution = _parseEnum(StreamResolution.values, json['resolution']);
    final rawFps = json['frameRate'];
    final rawBitrate = json['videoBitrate'];
    if (resolution == null || rawFps is! num || rawBitrate is! num) return null;
    final fps = rawFps.toInt();
    final bitrate = rawBitrate.toInt();
    if (fps <= 0 || bitrate <= 0) return null;

    return CameraRigPreset(
      id: rawId.trim(),
      name: rawName.trim(),
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      resolution: resolution,
      frameRate: fps,
      videoBitrate: bitrate.clamp(
        StreamConstants.minVideoBitrate,
        StreamConstants.maxVideoBitrate,
      ),
      cameraLens: _parseEnum(CameraLens.values, json['cameraLens']) ?? .back,
      isCustom: (json['isCustom'] as bool?) ?? false,
    );
  }

  static T? _parseEnum<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraRigPreset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          subtitle == other.subtitle &&
          resolution == other.resolution &&
          frameRate == other.frameRate &&
          videoBitrate == other.videoBitrate &&
          cameraLens == other.cameraLens &&
          isCustom == other.isCustom;

  @override
  int get hashCode => Object.hash(
    id, name, subtitle, resolution, frameRate, videoBitrate, cameraLens, isCustom,
  );
}

/// Curated built-in camera rig presets covering creator, USB, and eco setups.
const List<CameraRigPreset> builtInRigPresets = [
  CameraRigPreset(
    id: 'facecam_1080p60',
    name: 'Facecam 1080p60',
    subtitle: 'Smooth 60 FPS front camera for talking head',
    resolution: .p1080,
    frameRate: 60,
    videoBitrate: 6_000_000,
    cameraLens: .front,
  ),
  CameraRigPreset(
    id: 'overhead_4k30',
    name: 'Overhead 4K',
    subtitle: 'Crisp 4K rear sensor for desk and product demos',
    resolution: .p4k,
    frameRate: 30,
    videoBitrate: 12_000_000,
    cameraLens: .back,
  ),
  CameraRigPreset(
    id: 'usb_ultra',
    name: 'USB Ultra',
    subtitle: '20 Mbps low-compression feed for USB tethering',
    resolution: .p1080,
    frameRate: 60,
    videoBitrate: 20_000_000,
    cameraLens: .back,
  ),
  CameraRigPreset(
    id: 'vertical_cam',
    name: 'Vertical Cam',
    subtitle: '60 FPS front camera tuned for 9:16 framing',
    resolution: .p1080,
    frameRate: 60,
    videoBitrate: 6_000_000,
    cameraLens: .front,
  ),
  CameraRigPreset(
    id: 'eco_720p30',
    name: 'Eco 720p',
    subtitle: 'Battery-friendly 720p 30 FPS for long sessions',
    resolution: .p720,
    frameRate: 30,
    videoBitrate: 2_500_000,
    cameraLens: .back,
  ),
];
