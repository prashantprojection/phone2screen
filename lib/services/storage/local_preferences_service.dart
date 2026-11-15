import 'dart:async';
import 'dart:convert';

import '../../models/camera_rig_preset.dart';
import '../../models/shortcut_config.dart';
import '../../models/signaling_data.dart';
import '../../models/stream_config.dart';
import '../../providers/settings_provider.dart';
import 'local_preferences_stub.dart'
    if (dart.library.io) 'local_preferences_io.dart'
    as impl;

/// Immutable snapshot of all persisted Phone2Screen preferences.
class const PreferencesSnapshot({
  final AppSettings appSettings = const AppSettings(),
  final StreamConfig streamConfig = const StreamConfig(),
  final ShortcutConfig shortcutConfig = const ShortcutConfig(),
  final List<CameraRigPreset> customPresets = const [],
  final SignalingData? lastEndpoint,
}) {
  PreferencesSnapshot copyWith({
    AppSettings? appSettings,
    StreamConfig? streamConfig,
    ShortcutConfig? shortcutConfig,
    List<CameraRigPreset>? customPresets,
    SignalingData? lastEndpoint,
    bool clearLastEndpoint = false,
  }) => PreferencesSnapshot(
    appSettings: appSettings ?? this.appSettings,
    streamConfig: streamConfig ?? this.streamConfig,
    shortcutConfig: shortcutConfig ?? this.shortcutConfig,
    customPresets: customPresets ?? this.customPresets,
    lastEndpoint: clearLastEndpoint ? null : (lastEndpoint ?? this.lastEndpoint),
  );

  Map<String, dynamic> toJson() => {
    'version': 2,
    'appSettings': appSettings.toJson(),
    'streamConfig': streamConfigToJson(streamConfig),
    'shortcutConfig': shortcutConfig.toJson(),
    'customPresets': [for (final p in customPresets) p.toJson()],
    if (lastEndpoint != null) 'lastEndpoint': lastEndpoint!.toJson(),
  };

  static PreferencesSnapshot fromJson(Map<String, dynamic> json) {
    final presets = <CameraRigPreset>[];
    if (json['customPresets'] is List) {
      for (final item in json['customPresets'] as List) {
        if (item is Map) {
          final parsed = CameraRigPreset.tryFromJson(Map<String, dynamic>.from(item));
          if (parsed != null) presets.add(parsed);
        }
      }
    }
    SignalingData? lastEndpoint;
    if (json['lastEndpoint'] is Map) {
      try {
        lastEndpoint = SignalingData.fromJson(
          Map<String, dynamic>.from(json['lastEndpoint'] as Map),
        );
      } catch (_) {}
    }
    return PreferencesSnapshot(
      appSettings: json['appSettings'] is Map
          ? AppSettings.fromJson(Map<String, dynamic>.from(json['appSettings'] as Map))
          : const AppSettings(),
      streamConfig: json['streamConfig'] is Map
          ? streamConfigFromJson(Map<String, dynamic>.from(json['streamConfig'] as Map))
          : const StreamConfig(),
      shortcutConfig: json['shortcutConfig'] is Map
          ? ShortcutConfig.fromJson(Map<String, dynamic>.from(json['shortcutConfig'] as Map))
          : const ShortcutConfig(),
      customPresets: List.unmodifiable(presets),
      lastEndpoint: lastEndpoint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreferencesSnapshot &&
          runtimeType == other.runtimeType &&
          appSettings == other.appSettings &&
          streamConfig == other.streamConfig &&
          shortcutConfig == other.shortcutConfig &&
          _presetsEqual(customPresets, other.customPresets) &&
          lastEndpoint == other.lastEndpoint;

  @override
  int get hashCode => Object.hash(
    appSettings,
    streamConfig,
    shortcutConfig,
    Object.hashAll(customPresets),
    lastEndpoint,
  );

  static bool _presetsEqual(List<CameraRigPreset> a, List<CameraRigPreset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Cross-platform JSON preference persistence backed by app files or web storage.
class LocalPreferencesService {
  LocalPreferencesService._(this._store, this._snapshot);

  factory LocalPreferencesService.inMemory([
    PreferencesSnapshot initial = const PreferencesSnapshot(),
  ]) => LocalPreferencesService._(impl.createMemoryStore(), initial);

  factory LocalPreferencesService.fromFilePath(String path) =>
      LocalPreferencesService._(impl.createFileStore(path), const PreferencesSnapshot());

  static Future<LocalPreferencesService> loadDefault() async {
    final service = LocalPreferencesService._(
      await impl.createDefaultStore(),
      const PreferencesSnapshot(),
    );
    await service.load();
    return service;
  }

  final impl.PreferencesStore _store;
  PreferencesSnapshot _snapshot;
  Future<void> _writeQueue = Future.value();

  PreferencesSnapshot get snapshot => _snapshot;

  Future<PreferencesSnapshot> load() async {
    try {
      final raw = await _store.readRaw();
      if (raw == null || raw.trim().isEmpty) return _snapshot;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _snapshot = PreferencesSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return _snapshot;
  }

  Future<void> save(PreferencesSnapshot next) {
    _snapshot = next;
    final encoded = jsonEncode(next.toJson());
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _store.writeRaw(encoded);
      } catch (_) {}
    });
    return _writeQueue;
  }

  Future<void> saveAppSettings(AppSettings settings) =>
      save(_snapshot.copyWith(appSettings: settings));

  Future<void> saveStreamConfig(StreamConfig config) =>
      save(_snapshot.copyWith(streamConfig: config));

  Future<void> saveShortcutConfig(ShortcutConfig config) =>
      save(_snapshot.copyWith(shortcutConfig: config));

  Future<void> saveCustomPresets(List<CameraRigPreset> presets) =>
      save(_snapshot.copyWith(customPresets: List.unmodifiable(presets)));

  Future<void> saveLastEndpoint(SignalingData? endpoint) => save(
    _snapshot.copyWith(lastEndpoint: endpoint, clearLastEndpoint: endpoint == null),
  );

  Future<void> clear() {
    _snapshot = const PreferencesSnapshot();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _store.clearRaw();
      } catch (_) {}
    });
    return _writeQueue;
  }
}
