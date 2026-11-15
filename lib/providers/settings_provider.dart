import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants/stream_constants.dart';
import '../models/camera_rig_preset.dart';
import '../models/media_source_type.dart';
import '../models/stream_config.dart';
import '../models/workspace_mode.dart';

export '../models/workspace_mode.dart';
export 'viewer_display_provider.dart';

/// Persistent application preferences for hosting, pairing, and UI theme.
class const AppSettings({
  final ThemeMode themeMode = .dark,
  final int preferredPort = StreamConstants.defaultSignalingPort,
  final String pin = '',
  final bool autoCopyClipboard = true,
  final bool ecoDimPreview = false,
  final WorkspaceMode workspaceMode = .simple,
}) {
  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'preferredPort': preferredPort,
    'pin': pin,
    'autoCopyClipboard': autoCopyClipboard,
    'ecoDimPreview': ecoDimPreview,
    'workspaceMode': workspaceMode.name,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final rawPort = json['preferredPort'];
    return AppSettings(
      themeMode: _parseEnum(ThemeMode.values, json['themeMode']) ?? .dark,
      preferredPort: rawPort is num
          ? rawPort.toInt().clamp(0, 65535)
          : StreamConstants.defaultSignalingPort,
      pin: json['pin'] is String ? (json['pin'] as String).trim() : '',
      autoCopyClipboard: (json['autoCopyClipboard'] as bool?) ?? true,
      ecoDimPreview: (json['ecoDimPreview'] as bool?) ?? false,
      workspaceMode:
          _parseEnum(WorkspaceMode.values, json['workspaceMode']) ?? .simple,
    );
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? preferredPort,
    String? pin,
    bool? autoCopyClipboard,
    bool? ecoDimPreview,
    WorkspaceMode? workspaceMode,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    preferredPort: preferredPort ?? this.preferredPort,
    pin: pin ?? this.pin,
    autoCopyClipboard: autoCopyClipboard ?? this.autoCopyClipboard,
    ecoDimPreview: ecoDimPreview ?? this.ecoDimPreview,
    workspaceMode: workspaceMode ?? this.workspaceMode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          preferredPort == other.preferredPort &&
          pin == other.pin &&
          autoCopyClipboard == other.autoCopyClipboard &&
          ecoDimPreview == other.ecoDimPreview &&
          workspaceMode == other.workspaceMode;

  @override
  int get hashCode => Object.hash(
    themeMode,
    preferredPort,
    pin,
    autoCopyClipboard,
    ecoDimPreview,
    workspaceMode,
  );
}

/// Serializes [StreamConfig] to a JSON map for local preference persistence.
Map<String, dynamic> streamConfigToJson(StreamConfig config) => {
  'resolution': config.resolution.name,
  'frameRate': config.frameRate,
  'videoBitrate': config.videoBitrate,
  'enableAudio': config.enableAudio,
  'voiceCleanAudio': config.voiceCleanAudio,
  'cameraLens': config.cameraLens.name,
  'sourceType': config.sourceType.name,
  if (config.desktopSourceId != null) 'desktopSourceId': config.desktopSourceId,
};

/// Deserializes a [StreamConfig] from [json], falling back safely on bad values.
StreamConfig streamConfigFromJson(Map<String, dynamic> json) {
  final rawFps = json['frameRate'];
  final rawBitrate = json['videoBitrate'];
  return StreamConfig(
    resolution: _parseEnum(StreamResolution.values, json['resolution']) ?? .p1080,
    frameRate: rawFps is num && rawFps.toInt() > 0 ? rawFps.toInt() : 30,
    videoBitrate: rawBitrate is num
        ? rawBitrate.toInt().clamp(
            StreamConstants.minVideoBitrate,
            StreamConstants.maxVideoBitrate,
          )
        : StreamConstants.defaultVideoBitrate,
    enableAudio: (json['enableAudio'] as bool?) ?? true,
    voiceCleanAudio: (json['voiceCleanAudio'] as bool?) ?? true,
    cameraLens: _parseEnum(CameraLens.values, json['cameraLens']) ?? .back,
    sourceType: _parseEnum(MediaSourceType.values, json['sourceType']) ?? .camera,
    desktopSourceId: json['desktopSourceId'] is String
        ? json['desktopSourceId'] as String
        : null,
  );
}

T? _parseEnum<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

/// Global application settings provider.
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// Notifier updating [AppSettings].
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void replace(AppSettings next) => state = next;

  void setThemeMode(ThemeMode themeMode) =>
      state = state.copyWith(themeMode: themeMode);

  void setPreferredPort(int port) =>
      state = state.copyWith(preferredPort: port.clamp(0, 65535));

  void setPin(String pin) => state = state.copyWith(pin: pin.trim());

  void setAutoCopyClipboard(bool enabled) =>
      state = state.copyWith(autoCopyClipboard: enabled);

  void setEcoDimPreview(bool enabled) =>
      state = state.copyWith(ecoDimPreview: enabled);

  void setWorkspaceMode(WorkspaceMode mode) =>
      state = state.copyWith(workspaceMode: mode);

  void toggleWorkspaceMode() => state = state.copyWith(
    workspaceMode: state.workspaceMode == .simple ? .studio : .simple,
  );
}

/// Active media capture & encoding configuration provider.
final streamConfigProvider =
    NotifierProvider<StreamConfigNotifier, StreamConfig>(
      StreamConfigNotifier.new,
    );

/// Notifier updating [StreamConfig] presets and capture sources.
class StreamConfigNotifier extends Notifier<StreamConfig> {
  @override
  StreamConfig build() => const StreamConfig();

  void replace(StreamConfig next) => state = next;

  void applyPreset(CameraRigPreset preset) => state = preset.applyTo(state);

  void setResolution(StreamResolution resolution) {
    final nextBitrate = state.videoBitrate == state.resolution.recommendedBitrate
        ? resolution.recommendedBitrate
        : state.videoBitrate;
    state = state.copyWith(resolution: resolution, videoBitrate: nextBitrate);
  }

  void setFrameRate(int frameRate) =>
      state = state.copyWith(frameRate: frameRate);

  void setBitrate(int bitrate) => state = state.copyWith(
    videoBitrate: bitrate.clamp(
      StreamConstants.minVideoBitrate,
      StreamConstants.maxVideoBitrate,
    ),
  );

  void setSourceType(MediaSourceType sourceType) =>
      state = state.copyWith(sourceType: sourceType);

  void setCameraLens(CameraLens cameraLens) =>
      state = state.copyWith(cameraLens: cameraLens);

  void setEnableAudio(bool enableAudio) =>
      state = state.copyWith(enableAudio: enableAudio);

  void setVoiceCleanAudio(bool enabled) =>
      state = state.copyWith(voiceCleanAudio: enabled);

  void setDesktopSourceId(String? id) => state = state.copyWith(
    desktopSourceId: id,
    clearDesktopSource: id == null,
  );
}
