/// Presentation and viewport options for the receiver video stage.
class const ViewerDisplayConfig({
  final bool coverFit = false,
  final bool mirrored = false,
  final int quarterTurns = 0,
  final bool audioMuted = false,
  final bool isFullscreen = false,
  final bool fullscreenHudVisible = true,
  final bool showTelemetry = true,
}) {
  /// Returns a copy with any provided viewport flags updated.
  ViewerDisplayConfig copyWith({
    bool? coverFit,
    bool? mirrored,
    int? quarterTurns,
    bool? audioMuted,
    bool? isFullscreen,
    bool? fullscreenHudVisible,
    bool? showTelemetry,
  }) {
    return ViewerDisplayConfig(
      coverFit: coverFit ?? this.coverFit,
      mirrored: mirrored ?? this.mirrored,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      audioMuted: audioMuted ?? this.audioMuted,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      fullscreenHudVisible: fullscreenHudVisible ?? this.fullscreenHudVisible,
      showTelemetry: showTelemetry ?? this.showTelemetry,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewerDisplayConfig &&
          runtimeType == other.runtimeType &&
          coverFit == other.coverFit &&
          mirrored == other.mirrored &&
          quarterTurns == other.quarterTurns &&
          audioMuted == other.audioMuted &&
          isFullscreen == other.isFullscreen &&
          fullscreenHudVisible == other.fullscreenHudVisible &&
          showTelemetry == other.showTelemetry;

  @override
  int get hashCode => Object.hash(
    coverFit,
    mirrored,
    quarterTurns,
    audioMuted,
    isFullscreen,
    fullscreenHudVisible,
    showTelemetry,
  );
}
