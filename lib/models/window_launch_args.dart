/// Command-line launch arguments for desktop multi-camera receiver windows.
class const WindowLaunchArgs({
  final int cameraSlot = 1,
  final int? preferredPortOverride,
  final String? windowTitle,
  final int windowOffset = 0,
  final bool cleanFeed = false,
}) {
  /// Whether this window was launched as an auxiliary camera receiver (`slot > 1`).
  bool get isSecondaryCameraWindow => cameraSlot > 1;

  /// Parses multi-window flags passed via `main(List<String> args)`.
  static WindowLaunchArgs parse(List<String> args) {
    var cameraSlot = 1;
    int? preferredPort;
    String? title;
    var offset = 0;
    var cleanFeed = false;

    for (final raw in args) {
      if (raw.startsWith('--camera-slot=')) {
        final parsed = int.tryParse(raw.substring('--camera-slot='.length));
        if (parsed != null && parsed >= 1) cameraSlot = parsed;
      } else if (raw.startsWith('--port=')) {
        final parsed = int.tryParse(raw.substring('--port='.length));
        if (parsed != null && parsed >= 0 && parsed <= 65535) {
          preferredPort = parsed;
        }
      } else if (raw.startsWith('--window-title=')) {
        final value = raw.substring('--window-title='.length).trim();
        if (value.isNotEmpty) title = value;
      } else if (raw.startsWith('--window-offset=')) {
        final parsed = int.tryParse(raw.substring('--window-offset='.length));
        if (parsed != null) offset = parsed;
      } else if (raw == '--clean-feed' || raw == '--clean-feed=true') {
        cleanFeed = true;
      } else if (raw == '--clean-feed=false') {
        cleanFeed = false;
      }
    }

    return WindowLaunchArgs(
      cameraSlot: cameraSlot,
      preferredPortOverride: preferredPort,
      windowTitle: title,
      windowOffset: offset,
      cleanFeed: cleanFeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowLaunchArgs &&
          runtimeType == other.runtimeType &&
          cameraSlot == other.cameraSlot &&
          preferredPortOverride == other.preferredPortOverride &&
          windowTitle == other.windowTitle &&
          windowOffset == other.windowOffset &&
          cleanFeed == other.cleanFeed;

  @override
  int get hashCode => Object.hash(
    cameraSlot,
    preferredPortOverride,
    windowTitle,
    windowOffset,
    cleanFeed,
  );
}
