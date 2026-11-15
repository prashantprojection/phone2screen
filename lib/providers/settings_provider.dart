import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants/stream_constants.dart';
import '../models/media_source_type.dart';
import '../models/stream_config.dart';
import '../models/viewer_display_config.dart';

/// Persistent-style application preferences for hosting, pairing, and UI theme.
class const AppSettings({
  final ThemeMode themeMode = .dark,
  final int preferredPort = StreamConstants.defaultSignalingPort,
  final String pin = '',
  final bool autoCopyClipboard = true,
  final bool ecoDimPreview = false,
}) {
  /// Returns an updated copy of [AppSettings].
  AppSettings copyWith({
    ThemeMode? themeMode,
    int? preferredPort,
    String? pin,
    bool? autoCopyClipboard,
    bool? ecoDimPreview,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      preferredPort: preferredPort ?? this.preferredPort,
      pin: pin ?? this.pin,
      autoCopyClipboard: autoCopyClipboard ?? this.autoCopyClipboard,
      ecoDimPreview: ecoDimPreview ?? this.ecoDimPreview,
    );
  }

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
  int get hashCode => Object.hash(
    themeMode,
    preferredPort,
    pin,
    autoCopyClipboard,
    ecoDimPreview,
  );
}

/// Global application settings provider.
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// Notifier updating [AppSettings].
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  /// Sets the app [ThemeMode].
  void setThemeMode(ThemeMode themeMode) =>
      state = state.copyWith(themeMode: themeMode);

  /// Sets preferred HTTP/WS signaling port within valid TCP bounds.
  void setPreferredPort(int port) =>
      state = state.copyWith(preferredPort: port.clamp(0, 65535));

  /// Sets optional pairing PIN (empty string disables PIN requirement).
  void setPin(String pin) => state = state.copyWith(pin: pin.trim());

  /// Toggles automatic OS clipboard copying for incoming DataChannel text.
  void setAutoCopyClipboard(bool enabled) =>
      state = state.copyWith(autoCopyClipboard: enabled);

  /// Toggles Eco Dim Preview to unmount local video preview while streaming.
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

  /// Updates target capture resolution and scales default bitrate if unchanged.
  void setResolution(StreamResolution resolution) {
    final nextBitrate = state.videoBitrate == state.resolution.recommendedBitrate
        ? resolution.recommendedBitrate
        : state.videoBitrate;
    state = state.copyWith(
      resolution: resolution,
      videoBitrate: nextBitrate,
    );
  }

  /// Updates target video frame rate (`30` or `60`).
  void setFrameRate(int frameRate) =>
      state = state.copyWith(frameRate: frameRate);

  /// Updates target maximum video bitrate clamped to protocol limits.
  void setBitrate(int bitrate) => state = state.copyWith(
    videoBitrate: bitrate.clamp(
      StreamConstants.minVideoBitrate,
      StreamConstants.maxVideoBitrate,
    ),
  );

  /// Selects camera vs screen sharing source.
  void setSourceType(MediaSourceType sourceType) =>
      state = state.copyWith(sourceType: sourceType);

  /// Selects front vs back camera lens.
  void setCameraLens(CameraLens cameraLens) =>
      state = state.copyWith(cameraLens: cameraLens);

  /// Toggles audio capture inclusion for outgoing streams.
  void setEnableAudio(bool enableAudio) =>
      state = state.copyWith(enableAudio: enableAudio);

  /// Selects or clears the desktop screen/window source ID.
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

/// Notifier managing receiver fit, mirror, rotation, mute, and fullscreen state.
class ViewerDisplayNotifier extends Notifier<ViewerDisplayConfig> {
  @override
  ViewerDisplayConfig build() => const ViewerDisplayConfig();

  /// Toggles `contain` vs `cover` scaling on the receiver stage.
  void toggleFit() => state = state.copyWith(coverFit: !state.coverFit);

  /// Mirrors the received video horizontally.
  void toggleMirror() => state = state.copyWith(mirrored: !state.mirrored);

  /// Rotates the receiver video viewport clockwise by 90 degrees.
  void rotate90() =>
      state = state.copyWith(quarterTurns: (state.quarterTurns + 1) % 4);

  /// Mutes or unmutes receiver playback audio.
  void toggleMute() => state = state.copyWith(audioMuted: !state.audioMuted);

  /// Toggles immersive fullscreen receiver display.
  void toggleFullscreen() =>
      state = state.copyWith(isFullscreen: !state.isFullscreen);

  /// Explicitly sets immersive fullscreen state.
  void setFullscreen(bool value) => state = state.copyWith(isFullscreen: value);

  /// Shows or hides live telemetry overlay chips.
  void toggleTelemetry() =>
      state = state.copyWith(showTelemetry: !state.showTelemetry);

  /// Restores default receiver viewport settings.
  void reset() => state = const ViewerDisplayConfig();
}
