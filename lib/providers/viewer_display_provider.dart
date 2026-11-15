import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_routing_config.dart';
import '../models/viewer_display_config.dart';
import 'preferences_provider.dart';

/// Receiver video viewport transformation, framing, color, and FX provider.
final viewerDisplayProvider =
    NotifierProvider<ViewerDisplayNotifier, ViewerDisplayConfig>(
      ViewerDisplayNotifier.new,
    );

/// Notifier managing receiver fit, mirror, rotation, framing, color, FX, and HUD.
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

  void setBokehMode(PortraitBokehMode mode) =>
      state = state.copyWith(bokehMode: mode);

  void cycleBokehMode() =>
      state = state.copyWith(bokehMode: state.bokehMode.next);

  void setFaceFillLight(double value) =>
      state = state.copyWith(faceFillLight: value.clamp(0.0, 1.0));

  void toggleDeskCamMode() =>
      state = state.copyWith(deskCamMode: !state.deskCamMode);

  void setDeskCamMode(bool enabled) =>
      state = state.copyWith(deskCamMode: enabled);

  void setKeystoneVertical(double value) =>
      state = state.copyWith(keystoneVertical: value.clamp(-0.35, 0.35));

  void setKeystoneHorizontal(double value) =>
      state = state.copyWith(keystoneHorizontal: value.clamp(-0.35, 0.35));

  void setAudioGain(double gain) =>
      state = state.copyWith(audioGain: gain.clamp(0.0, 2.0).toDouble());

  void setAudioDelayMs(int delayMs) =>
      state = state.copyWith(audioDelayMs: delayMs.clamp(0, 500));

  void toggleVideoPause() =>
      state = state.copyWith(isVideoPaused: !state.isVideoPaused);

  void setVideoPaused(bool paused) =>
      state = state.copyWith(isVideoPaused: paused);

  void resetFramingAndColor() => state = state.resetLookAndFraming();

  void reset() => state = const ViewerDisplayConfig();
}
