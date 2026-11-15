/// Aspect-ratio crop presets for the studio receiver stage.
enum AspectPreset {
  free,
  widescreen16x9,
  vertical9x16,
  classic4x3;

  /// Human-readable label shown on framing chips.
  String get label => switch (this) {
    .free => 'Free',
    .widescreen16x9 => '16:9',
    .vertical9x16 => '9:16',
    .classic4x3 => '4:3',
  };

  /// Target width-over-height ratio, or `null` when unconstrained.
  double? get aspectRatio => switch (this) {
    .free => null,
    .widescreen16x9 => 16 / 9,
    .vertical9x16 => 9 / 16,
    .classic4x3 => 4 / 3,
  };
}

/// Presentation, framing, and color-grading options for the receiver stage.
class const ViewerDisplayConfig({
  final bool coverFit = false,
  final bool mirrored = false,
  final int quarterTurns = 0,
  final bool audioMuted = false,
  final bool isFullscreen = false,
  final bool fullscreenHudVisible = true,
  final bool showTelemetry = false,
  final bool cleanFeedMode = false,
  final bool showGrid = false,
  final AspectPreset aspectPreset = .free,
  final double digitalZoom = 1.0,
  final double panX = 0.0,
  final double panY = 0.0,
  final double brightness = 0.0,
  final double contrast = 1.0,
  final double saturation = 1.0,
}) {
  /// Whether any non-default brightness, contrast, or saturation grade is active.
  bool get hasColorAdjustments =>
      brightness != 0.0 || contrast != 1.0 || saturation != 1.0;

  /// Whether aspect lock, digital zoom, or pan offset differs from defaults.
  bool get hasFramingAdjustments =>
      aspectPreset != .free || digitalZoom != 1.0 || panX != 0.0 || panY != 0.0;

  /// Builds a 20-element 4x5 `ColorFilter.matrix` combining BT.709 saturation,
  /// contrast pivoted around 128, and brightness offset (`brightness * 255`).
  List<double> get colorMatrix {
    const rw = 0.2126;
    const gw = 0.7152;
    const bw = 0.0722;
    final invSat = 1.0 - saturation;
    final c = contrast;
    final offset = 128.0 * (1.0 - c) + brightness * 255.0;

    final sr = rw * invSat;
    final sg = gw * invSat;
    final sb = bw * invSat;

    return <double>[
      c * (sr + saturation), c * sg, c * sb, 0, offset,
      c * sr, c * (sg + saturation), c * sb, 0, offset,
      c * sr, c * sg, c * (sb + saturation), 0, offset,
      0, 0, 0, 1, 0,
    ];
  }

  /// Returns a copy with any provided viewport, framing, or color flags updated.
  ViewerDisplayConfig copyWith({
    bool? coverFit,
    bool? mirrored,
    int? quarterTurns,
    bool? audioMuted,
    bool? isFullscreen,
    bool? fullscreenHudVisible,
    bool? showTelemetry,
    bool? cleanFeedMode,
    bool? showGrid,
    AspectPreset? aspectPreset,
    double? digitalZoom,
    double? panX,
    double? panY,
    double? brightness,
    double? contrast,
    double? saturation,
  }) {
    return ViewerDisplayConfig(
      coverFit: coverFit ?? this.coverFit,
      mirrored: mirrored ?? this.mirrored,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      audioMuted: audioMuted ?? this.audioMuted,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      fullscreenHudVisible: fullscreenHudVisible ?? this.fullscreenHudVisible,
      showTelemetry: showTelemetry ?? this.showTelemetry,
      cleanFeedMode: cleanFeedMode ?? this.cleanFeedMode,
      showGrid: showGrid ?? this.showGrid,
      aspectPreset: aspectPreset ?? this.aspectPreset,
      digitalZoom: digitalZoom ?? this.digitalZoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
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
          showTelemetry == other.showTelemetry &&
          cleanFeedMode == other.cleanFeedMode &&
          showGrid == other.showGrid &&
          aspectPreset == other.aspectPreset &&
          digitalZoom == other.digitalZoom &&
          panX == other.panX &&
          panY == other.panY &&
          brightness == other.brightness &&
          contrast == other.contrast &&
          saturation == other.saturation;

  @override
  int get hashCode => Object.hash(
    coverFit,
    mirrored,
    quarterTurns,
    audioMuted,
    isFullscreen,
    fullscreenHudVisible,
    showTelemetry,
    cleanFeedMode,
    showGrid,
    aspectPreset,
    digitalZoom,
    panX,
    panY,
    brightness,
    contrast,
    saturation,
  );
}
