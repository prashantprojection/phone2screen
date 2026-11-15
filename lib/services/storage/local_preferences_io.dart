import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _androidFilesChannel = MethodChannel(
  'phone2screen/projection_service',
);

/// Raw string storage backend for [LocalPreferencesService].
abstract interface class PreferencesStore {
  Future<String?> readRaw();
  Future<void> writeRaw(String content);
  Future<void> clearRaw();
}

class _MemoryPreferencesStore implements PreferencesStore {
  String? _raw;

  @override
  Future<String?> readRaw() async => _raw;

  @override
  Future<void> writeRaw(String content) async => _raw = content;

  @override
  Future<void> clearRaw() async => _raw = null;
}

class _FilePreferencesStore implements PreferencesStore {
  _FilePreferencesStore(this._path);

  final String _path;

  @override
  Future<String?> readRaw() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeRaw(String content) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<void> clearRaw() async {
    try {
      final file = File(_path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

PreferencesStore createMemoryStore() => _MemoryPreferencesStore();

PreferencesStore createFileStore(String path) => _FilePreferencesStore(path);

Future<PreferencesStore> createDefaultStore() async {
  // Keep flutter test isolated from the host machine's user profile directory.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return createMemoryStore();
  }

  final sep = Platform.pathSeparator;
  if (Platform.isAndroid) {
    try {
      final dir = await _androidFilesChannel.invokeMethod<String>(
        'getFilesDir',
      );
      if (dir != null && dir.trim().isNotEmpty) {
        return createFileStore('$dir${sep}phone2screen_prefs.json');
      }
    } catch (_) {}
  }

  if (Platform.isWindows) {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['USERPROFILE'];
    if (base != null && base.isNotEmpty) {
      return createFileStore('$base${sep}Phone2Screen${sep}preferences.json');
    }
  } else {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return createFileStore('$home${sep}Documents${sep}phone2screen_prefs.json');
    }
  }

  return createMemoryStore();
}
