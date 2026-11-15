import 'dart:async';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import 'desktop_window_service.dart';

class _ProcessWindowHandle implements DesktopWindowHandle {
  _ProcessWindowHandle(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();
}

class _TrackedWindow {
  _TrackedWindow({required this.entry, required this.handle});

  final DesktopWindowEntry entry;
  final DesktopWindowHandle handle;
  bool closing = false;
}

/// Native `dart:io` desktop window registry spawning isolated Phone2Screen
/// instances with `--camera-slot`, `--port`, `--window-title`, and `--window-offset`.
class DesktopWindowImpl {
  DesktopWindowImpl({
    DesktopWindowLauncher? launcher,
    this._isSupportedOverride,
  }) : _launcher = launcher ?? _defaultLauncher;

  final DesktopWindowLauncher _launcher;
  final bool? _isSupportedOverride;
  final _windowsController =
      StreamController<List<DesktopWindowEntry>>.broadcast();
  final Map<int, _TrackedWindow> _windows = {};
  bool _disposed = false;

  bool get isSupported =>
      _isSupportedOverride ??
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  List<DesktopWindowEntry> get activeWindows {
    final list = [for (final w in _windows.values) w.entry]
      ..sort((a, b) => a.slot.compareTo(b.slot));
    return List.unmodifiable(list);
  }

  Stream<List<DesktopWindowEntry>> get windowsStream =>
      _windowsController.stream;

  Future<DesktopWindowEntry?> openCameraWindow({
    int? slot,
    int basePort = StreamConstants.defaultSignalingPort,
    bool cleanFeed = false,
  }) async {
    if (_disposed || !isSupported) return null;

    final resolvedSlot = slot ?? _nextAvailableSlot();
    if (resolvedSlot == null ||
        resolvedSlot < 2 ||
        resolvedSlot > StreamConstants.maxDesktopReceiverPeers) {
      return null;
    }

    final existing = _windows[resolvedSlot];
    if (existing != null) return existing.entry;

    final targetPort = basePort + (resolvedSlot - 1);
    final title = 'Phone2Screen — Camera $resolvedSlot';
    final offset = (resolvedSlot - 1) * 36;
    final args = <String>[
      '--camera-slot=$resolvedSlot',
      '--port=$targetPort',
      '--window-title=$title',
      '--window-offset=$offset',
      if (cleanFeed) '--clean-feed',
    ];

    final entry = DesktopWindowEntry(
      slot: resolvedSlot,
      port: targetPort,
      title: title,
      cleanFeed: cleanFeed,
    );

    final DesktopWindowHandle handle;
    try {
      handle = await _launcher(Platform.resolvedExecutable, args);
    } catch (_) {
      return null;
    }

    if (_disposed) {
      handle.kill();
      return null;
    }

    final tracked = _TrackedWindow(entry: entry, handle: handle);
    _windows[resolvedSlot] = tracked;
    _emit();

    unawaited(
      handle.exitCode.then((_) {
        if (_windows[resolvedSlot] == tracked && !tracked.closing) {
          _windows.remove(resolvedSlot);
          _emit();
        }
      }, onError: (_) {}),
    );

    return entry;
  }

  Future<bool> closeWindow(int slot) async {
    final tracked = _windows.remove(slot);
    if (tracked == null) return false;
    tracked.closing = true;
    tracked.handle.kill();
    _emit();
    return true;
  }

  Future<void> closeAllWindows() async {
    if (_windows.isEmpty) return;
    final entries = _windows.values.toList();
    _windows.clear();
    for (final tracked in entries) {
      tracked.closing = true;
      tracked.handle.kill();
    }
    _emit();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await closeAllWindows();
    await _windowsController.close();
  }

  int? _nextAvailableSlot() {
    for (var s = 2; s <= StreamConstants.maxDesktopReceiverPeers; s++) {
      if (!_windows.containsKey(s)) return s;
    }
    return null;
  }

  void _emit() {
    if (!_disposed && !_windowsController.isClosed) {
      _windowsController.add(activeWindows);
    }
  }

  static Future<DesktopWindowHandle> _defaultLauncher(
    String executable,
    List<String> arguments,
  ) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      throw UnsupportedError('Avoid spawning child processes during flutter test.');
    }
    final process = await Process.start(executable, arguments);
    return _ProcessWindowHandle(process);
  }
}
