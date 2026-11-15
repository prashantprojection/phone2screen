import 'dart:async';
import 'dart:convert';

import '../../models/camera_rig_preset.dart';
import '../../models/obs_sync_state.dart';
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

  static const Set<String> _reservedSnapshotKeys = {
    'version',
    'appSettings',
    'streamConfig',
    'shortcutConfig',
    'customPresets',
    'lastEndpoint',
  };

  final impl.PreferencesStore _store;
  PreferencesSnapshot _snapshot;
  final Map<String, Map<String, dynamic>> _sections = {};
  Future<void> _writeQueue = Future.value();

  PreferencesSnapshot get snapshot => _snapshot;

  Future<PreferencesSnapshot> load() async {
    try {
      final raw = await _store.readRaw();
      if (raw == null || raw.trim().isEmpty) return _snapshot;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final root = Map<String, dynamic>.from(decoded);
        _snapshot = PreferencesSnapshot.fromJson(root);
        _sections.clear();
        for (final entry in root.entries) {
          if (_reservedSnapshotKeys.contains(entry.key)) continue;
          if (entry.value is Map) {
            _sections[entry.key] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
    } catch (_) {}
    return _snapshot;
  }

  Future<void> save(PreferencesSnapshot next) {
    _snapshot = next;
    return _persistCurrent();
  }

  /// Reads a raw JSON preference section stored under [key], or `null` if unset.
  Map<String, dynamic>? loadJsonSection(String key) {
    final section = _sections[key];
    return section == null ? null : Map<String, dynamic>.from(section);
  }

  /// Stores a raw JSON preference section under [key] and persists to storage.
  Future<void> saveJsonSection(String key, Map<String, dynamic> value) {
    if (_reservedSnapshotKeys.contains(key)) return Future.value();
    _sections[key] = Map<String, dynamic>.from(value);
    return _persistCurrent();
  }

  /// Loads persisted OBS WebSocket v5 connection settings (defaults if unset).
  ObsConnectionConfig loadObsConfig() {
    final raw = loadJsonSection('obsConfig');
    return raw == null
        ? const ObsConnectionConfig()
        : ObsConnectionConfig.fromJson(raw);
  }

  /// Saves OBS WebSocket v5 connection settings under `'obsConfig'`.
  Future<void> saveObsConfig(ObsConnectionConfig config) =>
      saveJsonSection('obsConfig', config.toJson());

  Future<void> _persistCurrent() {
    final payload = <String, dynamic>{
      ..._snapshot.toJson(),
      for (final entry in _sections.entries) entry.key: entry.value,
    };
    final encoded = jsonEncode(payload);
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
    _sections.clear();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _store.clearRaw();
      } catch (_) {}
    });
    return _writeQueue;
  }
}
