import 'package:web/web.dart' as web;

const String _webStorageKey = 'phone2screen.preferences.v2';

/// Raw string storage backend for [LocalPreferencesService] on Web.
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

class _WebLocalStorageStore implements PreferencesStore {
  String? _fallback;

  @override
  Future<String?> readRaw() async {
    try {
      return web.window.localStorage.getItem(_webStorageKey) ?? _fallback;
    } catch (_) {
      return _fallback;
    }
  }

  @override
  Future<void> writeRaw(String content) async {
    _fallback = content;
    try {
      web.window.localStorage.setItem(_webStorageKey, content);
    } catch (_) {
      // Ignore storage quota or private-mode security errors.
    }
  }

  @override
  Future<void> clearRaw() async {
    _fallback = null;
    try {
      web.window.localStorage.removeItem(_webStorageKey);
    } catch (_) {}
  }
}

PreferencesStore createMemoryStore() => _MemoryPreferencesStore();

PreferencesStore createFileStore(String path) => _MemoryPreferencesStore();

Future<PreferencesStore> createDefaultStore() async => _WebLocalStorageStore();
