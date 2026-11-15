import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants/stream_constants.dart';
import '../models/audio_routing_config.dart';
import '../models/camera_rig_preset.dart';
import '../models/media_source_type.dart';
import '../models/stream_config.dart';
import '../models/viewer_display_config.dart';
import 'preferences_provider.dart';

/// Persistent application preferences for hosting, pairing, and UI theme.
class const AppSettings({
  final ThemeMode themeMode = .dark,
  final int preferredPort = StreamConstants.defaultSignalingPort,
  final String pin = '',
  final bool autoCopyClipboard = true,
  final bool ecoDimPreview = false,
}) {
  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'preferredPort': preferredPort,
    'pin': pin,
    'autoCopyClipboard': autoCopyClipboard,
    'ecoDimPreview': ecoDimPreview,
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
    );
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? preferredPort,
    String? pin,
    bool? autoCopyClipboard,
    bool? ecoDimPreview,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    preferredPort: preferredPort ?? this.preferredPort,
    pin: pin ?? this.pin,
    autoCopyClipboard: autoCopyClipboard ?? this.autoCopyClipboard,
    ecoDimPreview: ecoDimPreview ?? this.ecoDimPreview,
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
          ecoDimPreview == other.ecoDimPreview;

  @override
  int get hashCode =>
      Object.hash(themeMode, preferredPort, pin, autoCopyClipboard, ecoDimPreview);
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

/// Receiver video viewport transformation and overlay state provider.
final viewerDisplayProvider =
    NotifierProvider<ViewerDisplayNotifier, ViewerDisplayConfig>(
      ViewerDisplayNotifier.new,
    );

/// Notifier managing receiver fit, mirror, rotation, framing, color, and HUD.
class ViewerDisplayNotifier extends Notifier<ViewerDisplayConfig> {
  @override
  ViewerDisplayConfig build() {
    final raw = ref.watch(localPreferencesServiceProvider).loadJsonSection('audioStudio');
    if (raw == null) return const ViewerDisplayConfig();
    final audio = AudioStudioConfig.fromJson(raw);
    return ViewerDisplayConfig(audioGain: audio.gain, audioDelayMs: audio.lipSyncDelayMs);
  }

  void toggleFit() => state = state.copyWith(coverFit: !state.coverFit);

  void toggleMirror() => state = state.copyWith(mirrored: !state.mirrored);

  void rotate90() =>
      state = state.copyWith(quarterTurns: (state.quarterTurns + 1) % 4);

  void toggleMute() => state = state.copyWith(audioMuted: !state.audioMuted);

  void toggleFullscreen() {
    final next = !state.isFullscreen;
    state = state.copyWith(
      isFullscreen: next,
      fullscreenHudVisible: next ? true : state.fullscreenHudVisible,
    );
  }

  void setFullscreen(bool value) => state = state.copyWith(
    isFullscreen: value,
    fullscreenHudVisible: value ? true : state.fullscreenHudVisible,
  );

  void toggleFullscreenHud() =>
      state = state.copyWith(fullscreenHudVisible: !state.fullscreenHudVisible);

  void setFullscreenHudVisible(bool visible) =>
      state = state.copyWith(fullscreenHudVisible: visible);

  void toggleTelemetry() =>
      state = state.copyWith(showTelemetry: !state.showTelemetry);

  /// Enters clean fullscreen with HUD controls hidden (used by `--clean-feed` window launch).
  void enterCleanFullscreen() =>
      state = state.copyWith(isFullscreen: true, fullscreenHudVisible: false);

  void toggleGrid() => state = state.copyWith(showGrid: !state.showGrid);

  void setAspectPreset(AspectPreset preset) =>
      state = state.copyWith(aspectPreset: preset);

  void setDigitalZoom(double zoom) =>
      state = state.copyWith(digitalZoom: zoom.clamp(1.0, 3.0));

  void setPan(double x, double y) =>
      state = state.copyWith(panX: x.clamp(-1.0, 1.0), panY: y.clamp(-1.0, 1.0));

  void setBrightness(double value) =>
      state = state.copyWith(brightness: value.clamp(-0.5, 0.5));

  void setContrast(double value) =>
      state = state.copyWith(contrast: value.clamp(0.5, 1.5));

  void setSaturation(double value) =>
      state = state.copyWith(saturation: value.clamp(0.0, 2.0));

  void setLookPreset(StudioLookPreset preset) =>
      state = state.copyWith(lookPreset: preset);

  void toggleVignette() => state = state.copyWith(vignette: !state.vignette);

  void setAudioGain(double gain) =>
      state = state.copyWith(audioGain: gain.clamp(0.0, 2.0).toDouble());

  void setAudioDelayMs(int delayMs) =>
      state = state.copyWith(audioDelayMs: delayMs.clamp(0, 500));

  void resetFramingAndColor() => state = state.copyWith(
    aspectPreset: .free,
    digitalZoom: 1.0,
    panX: 0.0,
    panY: 0.0,
    brightness: 0.0,
    contrast: 1.0,
    saturation: 1.0,
    lookPreset: .natural,
    vignette: false,
  );

  void reset() => state = const ViewerDisplayConfig();
}
