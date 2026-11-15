import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/camera_rig_preset.dart';
import '../models/signaling_data.dart';
import '../models/window_launch_args.dart';
import '../services/storage/local_preferences_service.dart';
import 'settings_provider.dart';
import 'shortcut_provider.dart';

/// CLI launch arguments for primary vs secondary desktop camera windows.
final windowLaunchArgsProvider = Provider<WindowLaunchArgs>(
  (ref) => const WindowLaunchArgs(),
);

/// Persistent preferences service (overridden at startup with `loadDefault()`).
final localPreferencesServiceProvider = Provider<LocalPreferencesService>(
  (ref) => LocalPreferencesService.inMemory(),
);

/// User-saved custom [CameraRigPreset] list synced with local preferences.
final customRigPresetsProvider =
    NotifierProvider<CustomRigPresetsNotifier, List<CameraRigPreset>>(
      CustomRigPresetsNotifier.new,
    );

/// Combined list of built-in and user-created camera rig presets.
final allRigPresetsProvider = Provider<List<CameraRigPreset>>((ref) {
  final custom = ref.watch(customRigPresetsProvider);
  return List.unmodifiable([...builtInRigPresets, ...custom]);
});

/// Notifier managing user-created custom camera rig presets.
class CustomRigPresetsNotifier extends Notifier<List<CameraRigPreset>> {
  @override
  List<CameraRigPreset> build() =>
      ref.watch(localPreferencesServiceProvider).snapshot.customPresets;

  /// Adds or updates a custom preset (forcing `isCustom: true`) and persists it.
  Future<void> savePreset(CameraRigPreset preset) async {
    final normalized = CameraRigPreset(
      id: preset.id,
      name: preset.name,
      subtitle: preset.subtitle,
      resolution: preset.resolution,
      frameRate: preset.frameRate,
      videoBitrate: preset.videoBitrate,
      cameraLens: preset.cameraLens,
      isCustom: true,
    );
    final updated = [
      for (final existing in state)
        if (existing.id != normalized.id) existing,
      normalized,
    ];
    state = List.unmodifiable(updated);
    await ref.read(localPreferencesServiceProvider).saveCustomPresets(state);
  }

  /// Removes any custom preset matching [presetId] and persists the change.
  Future<void> removePreset(String presetId) async {
    final updated = [
      for (final existing in state)
        if (existing.id != presetId) existing,
    ];
    state = List.unmodifiable(updated);
    await ref.read(localPreferencesServiceProvider).saveCustomPresets(state);
  }
}

/// Most recently connected sender/receiver endpoint for quick 1-tap reconnect.
final lastEndpointProvider =
    NotifierProvider<LastEndpointNotifier, SignalingData?>(
      LastEndpointNotifier.new,
    );

/// Notifier tracking and persisting the last paired [SignalingData] endpoint.
class LastEndpointNotifier extends Notifier<SignalingData?> {
  @override
  SignalingData? build() =>
      ref.watch(localPreferencesServiceProvider).snapshot.lastEndpoint;

  /// Updates the last connected endpoint and persists it.
  Future<void> setLastEndpoint(SignalingData? endpoint) async {
    state = endpoint;
    await ref.read(localPreferencesServiceProvider).saveLastEndpoint(endpoint);
  }

  /// Clears the persisted last connected endpoint.
  Future<void> clear() => setLastEndpoint(null);
}

/// Hydrates settings, stream config, and shortcut providers from [snapshot].
void hydrateProvidersFromPreferences(
  ProviderContainer container,
  PreferencesSnapshot snapshot,
) {
  container.read(appSettingsProvider.notifier).replace(snapshot.appSettings);
  container.read(streamConfigProvider.notifier).replace(snapshot.streamConfig);
  container.read(shortcutProvider.notifier).replaceConfig(snapshot.shortcutConfig);
}

/// Listens to app settings, stream config, and shortcut updates and persists
/// them asynchronously to [localPreferencesServiceProvider].
final preferencesAutoSaveProvider = Provider<void>((ref) {
  final prefs = ref.watch(localPreferencesServiceProvider);
  ref.listen(appSettingsProvider, (_, next) {
    unawaited(prefs.saveAppSettings(next));
  });
  ref.listen(streamConfigProvider, (_, next) {
    unawaited(prefs.saveStreamConfig(next));
  });
  ref.listen(shortcutProvider, (_, next) {
    unawaited(prefs.saveShortcutConfig(next));
  });
});
