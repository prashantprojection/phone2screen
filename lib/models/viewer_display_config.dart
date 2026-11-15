/// Presentation and viewport options for the receiver video stage.
class const ViewerDisplayConfig({
  final bool coverFit = false,
  final bool mirrored = false,
  final int quarterTurns = 0,
  final bool audioMuted = false,
  final bool isFullscreen = false,
  final bool showTelemetry = true,
}) {
  ViewerDisplayConfig copyWith({
    bool? coverFit,
    bool? mirrored,
    int? quarterTurns,
    bool? audioMuted,
    bool? isFullscreen,
    bool? showTelemetry,
  }) {
    return ViewerDisplayConfig(
      coverFit: coverFit ?? this.coverFit,
      mirrored: mirrored ?? this.mirrored,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      audioMuted: audioMuted ?? this.audioMuted,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      showTelemetry: showTelemetry ?? this.showTelemetry,
    );
  }
}
