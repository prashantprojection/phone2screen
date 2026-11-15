import '../../core/constants/stream_constants.dart';
import 'desktop_window_stub.dart'
    if (dart.library.io) 'desktop_window_io.dart'
    as impl;

/// Descriptor for a secondary desktop camera receiver window managed by
/// [DesktopWindowService].
class const DesktopWindowEntry({
  required final int slot,
  required final int port,
  required final String title,
  final bool cleanFeed = false,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopWindowEntry &&
          runtimeType == other.runtimeType &&
          slot == other.slot &&
          port == other.port &&
          title == other.title &&
          cleanFeed == other.cleanFeed;

  @override
  int get hashCode => Object.hash(slot, port, title, cleanFeed);
}

/// Handle representing a spawned desktop window process in a window registry.
abstract interface class DesktopWindowHandle {
  Future<int> get exitCode;
  bool kill();
}

/// Callback spawning an auxiliary desktop window with CLI [arguments].
typedef DesktopWindowLauncher = Future<DesktopWindowHandle> Function(
  String executable,
  List<String> arguments,
);

/// Manages secondary desktop camera receiver windows via isolated OS process
/// launches (`WindowController`/`WindowRegistry` pattern without private SDK APIs).
class DesktopWindowService {
  DesktopWindowService({
    DesktopWindowLauncher? launcher,
    bool? isSupportedOverride,
  }) : _impl = impl.DesktopWindowImpl(
         launcher: launcher,
         isSupportedOverride: isSupportedOverride,
       );

  final impl.DesktopWindowImpl _impl;

  /// Whether secondary desktop camera windows can be launched on this platform.
  bool get isSupported => _impl.isSupported;

  /// Snapshot list of currently active secondary camera windows ordered by slot.
  List<DesktopWindowEntry> get activeWindows => _impl.activeWindows;

  /// Broadcast stream emitting updated active window lists on open/close/exit.
  Stream<List<DesktopWindowEntry>> get windowsStream => _impl.windowsStream;

  /// Opens a secondary camera receiver window for [slot] (or the next free slot
  /// in `2..maxDesktopReceiverPeers`), returning its entry or `null` if unavailable.
  Future<DesktopWindowEntry?> openCameraWindow({
    int? slot,
    int basePort = StreamConstants.defaultSignalingPort,
    bool cleanFeed = false,
  }) => _impl.openCameraWindow(
    slot: slot,
    basePort: basePort,
    cleanFeed: cleanFeed,
  );

  /// Closes the secondary camera window occupying [slot].
  Future<bool> closeWindow(int slot) => _impl.closeWindow(slot);

  /// Closes all tracked secondary camera windows.
  Future<void> closeAllWindows() => _impl.closeAllWindows();

  /// Closes all secondary windows and releases stream resources.
  Future<void> dispose() => _impl.dispose();
}
