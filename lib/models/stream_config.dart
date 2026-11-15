import '../core/constants/stream_constants.dart';
import 'media_source_type.dart';

/// Output resolution presets supported by WebRTC capture and encoding.
enum StreamResolution {
  p720,
  p1080,
  p4k;

  int get width => switch (this) {
    .p720 => StreamConstants.width720p,
    .p1080 => StreamConstants.width1080p,
    .p4k => StreamConstants.width4K,
  };

  int get height => switch (this) {
    .p720 => StreamConstants.height720p,
    .p1080 => StreamConstants.height1080p,
    .p4k => StreamConstants.height4K,
  };

  String get label => switch (this) {
    .p720 => '720p HD',
    .p1080 => '1080p FHD',
    .p4k => '4K UHD',
  };

  int get recommendedBitrate => switch (this) {
    .p720 => StreamConstants.videoBitrate720p,
    .p1080 => StreamConstants.videoBitrate1080p,
    .p4k => StreamConstants.videoBitrate4K,
  };
}

/// Active media capture and encoding configuration for a sender stream.
class const StreamConfig({
  final StreamResolution resolution = .p1080,
  final int frameRate = 30,
  final int videoBitrate = 3_500_000,
  final bool enableAudio = true,
  final bool voiceCleanAudio = true,
  final CameraLens cameraLens = .back,
  final MediaSourceType sourceType = .camera,
  final String? desktopSourceId,
}) {
  int get width => resolution.width;
  int get height => resolution.height;

  StreamConfig copyWith({
    StreamResolution? resolution,
    int? frameRate,
    int? videoBitrate,
    bool? enableAudio,
    bool? voiceCleanAudio,
    CameraLens? cameraLens,
    MediaSourceType? sourceType,
    String? desktopSourceId,
    bool clearDesktopSource = false,
  }) {
    return StreamConfig(
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      enableAudio: enableAudio ?? this.enableAudio,
      voiceCleanAudio: voiceCleanAudio ?? this.voiceCleanAudio,
      cameraLens: cameraLens ?? this.cameraLens,
      sourceType: sourceType ?? this.sourceType,
      desktopSourceId: clearDesktopSource
          ? null
          : (desktopSourceId ?? this.desktopSourceId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamConfig &&
          runtimeType == other.runtimeType &&
          resolution == other.resolution &&
          frameRate == other.frameRate &&
          videoBitrate == other.videoBitrate &&
          enableAudio == other.enableAudio &&
          voiceCleanAudio == other.voiceCleanAudio &&
          cameraLens == other.cameraLens &&
          sourceType == other.sourceType &&
          desktopSourceId == other.desktopSourceId;

  @override
  int get hashCode => Object.hash(
    resolution,
    frameRate,
    videoBitrate,
    enableAudio,
    voiceCleanAudio,
    cameraLens,
    sourceType,
    desktopSourceId,
  );
}
