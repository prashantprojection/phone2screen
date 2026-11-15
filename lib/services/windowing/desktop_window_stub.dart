import 'dart:async';

import '../../core/constants/stream_constants.dart';
import 'desktop_window_service.dart';

/// Web stub: browser tabs cannot spawn native multi-window OS processes.
class DesktopWindowImpl {
  DesktopWindowImpl({
    DesktopWindowLauncher? launcher,
    this._isSupportedOverride,
  });

  final bool? _isSupportedOverride;
  final _windowsController =
      StreamController<List<DesktopWindowEntry>>.broadcast();

  bool get isSupported => _isSupportedOverride ?? false;

  List<DesktopWindowEntry> get activeWindows => const [];

  Stream<List<DesktopWindowEntry>> get windowsStream =>
      _windowsController.stream;

  Future<DesktopWindowEntry?> openCameraWindow({
    int? slot,
    int basePort = StreamConstants.defaultSignalingPort,
    bool cleanFeed = false,
  }) async => null;

  Future<bool> closeWindow(int slot) async => false;

  Future<void> closeAllWindows() async {}

  Future<void> dispose() => _windowsController.close();
}
