/// Aspect-ratio crop presets for the studio receiver stage.
enum AspectPreset {
  free,
  widescreen16x9,
  vertical9x16,
  classic4x3;

  String get label => switch (this) {
    .free => 'Free',
    .widescreen16x9 => '16:9',
    .vertical9x16 => '9:16',
    .classic4x3 => '4:3',
  };

  double? get aspectRatio => switch (this) {
    .free => null,
    .widescreen16x9 => 16 / 9,
    .vertical9x16 => 9 / 16,
    .classic4x3 => 4 / 3,
  };
}

/// Lightweight GPU color-grading look presets (4x5 RGBA matrices).
enum StudioLookPreset {
  natural,
  streamPunch,
  warmKeylight,
  coolCyber,
  noirBw;

  String get label => switch (this) {
    .natural => 'Natural',
    .streamPunch => 'Stream Punch',
    .warmKeylight => 'Warm Keylight',
    .coolCyber => 'Cool Cyber',
    .noirBw => 'Noir B&W',
  };

  List<double> get matrix => switch (this) {
    .natural => const [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ],
    // +12% contrast around 128 and +18% BT.709 saturation boost.
    .streamPunch => const [
      1.2787, -0.1442, -0.0146, 0, -15.36,
      -0.0429, 1.1774, -0.0146, 0, -15.36,
      -0.0429, -0.1442, 1.3070, 0, -15.36,
      0, 0, 0, 1, 0,
    ],
    // Golden tungsten warmth (+R/G) with subtle cool shadow trim on blue.
    .warmKeylight => const [
      1.08, 0.02, 0.00, 0, 6,
      0.01, 1.03, 0.00, 0, 2,
      0.00, 0.00, 0.90, 0, -6,
      0, 0, 0, 1, 0,
    ],
    // Crisp neon teal-magenta cool tint tuned for gaming overlays.
    .coolCyber => const [
      1.02, -0.04, 0.08, 0, -4,
      -0.02, 1.06, 0.04, 0, -2,
      0.02, 0.06, 1.14, 0, 4,
      0, 0, 0, 1, 0,
    ],
    // ITU-R BT.709 monochrome with 1.18x crisp contrast.
    .noirBw => const [
      0.2509, 0.8439, 0.0852, 0, -23.04,
      0.2509, 0.8439, 0.0852, 0, -23.04,
      0.2509, 0.8439, 0.0852, 0, -23.04,
      0, 0, 0, 1, 0,
    ],
  };
}

/// GPU portrait background blur levels layered around the subject center.
enum PortraitBokehMode {
  off,
  soft,
  strong;

  String get label => switch (this) {
    .off => 'Off',
    .soft => 'Soft Bokeh',
    .strong => 'Strong Blur',
  };

  double get sigma => switch (this) {
    .off => 0.0,
    .soft => 7.0,
    .strong => 15.0,
  };

  PortraitBokehMode get next => switch (this) {
    .off => .soft,
    .soft => .strong,
    .strong => .off,
  };
}

/// Presentation, framing, color-grading, FX, and audio options for the receiver stage.
class const ViewerDisplayConfig({
  final bool coverFit = false,
  final bool mirrored = false,
  final int quarterTurns = 0,
  final bool audioMuted = false,
  final bool isFullscreen = false,
  final bool fullscreenHudVisible = true,
  final bool showTelemetry = false,
  final bool showGrid = false,
  final AspectPreset aspectPreset = .free,
  final double digitalZoom = 1.0,
  final double panX = 0.0,
  final double panY = 0.0,
  final double brightness = 0.0,
  final double contrast = 1.0,
  final double saturation = 1.0,
  final StudioLookPreset lookPreset = .natural,
  final bool vignette = false,
  final double audioGain = 1.0,
  final int audioDelayMs = 0,
  final bool isVideoPaused = false,
  final PortraitBokehMode bokehMode = .off,
  final double faceFillLight = 0.0,
  final bool deskCamMode = false,
  final double keystoneVertical = 0.0,
  final double keystoneHorizontal = 0.0,
}) {
  bool get hasColorMatrix =>
      brightness != 0.0 || contrast != 1.0 || saturation != 1.0 || lookPreset != .natural;

  bool get hasColorAdjustments =>
      hasColorMatrix || vignette || bokehMode != .off || faceFillLight > 0.0;

  bool get hasFramingAdjustments =>
      aspectPreset != .free || digitalZoom != 1.0 || panX != 0.0 || panY != 0.0 ||
      deskCamMode || keystoneVertical != 0.0 || keystoneHorizontal != 0.0;

  ViewerDisplayConfig resetLookAndFraming() => copyWith(
    aspectPreset: .free, digitalZoom: 1.0, panX: 0.0, panY: 0.0,
    deskCamMode: false, keystoneVertical: 0.0, keystoneHorizontal: 0.0,
    brightness: 0.0, contrast: 1.0, saturation: 1.0, lookPreset: .natural,
    vignette: false, bokehMode: .off, faceFillLight: 0.0,
  );

  /// Builds a 20-element 4x5 `ColorFilter.matrix` combining [lookPreset]
  /// followed by user BT.709 saturation, contrast, and brightness adjustments.
  List<double> get colorMatrix {
    final bcs = _userBcsMatrix;
    if (lookPreset == .natural) return bcs;
    if (brightness == 0.0 && contrast == 1.0 && saturation == 1.0) {
      return lookPreset.matrix;
    }
    return _composeColorMatrices(bcs, lookPreset.matrix);
  }

  List<double> get _userBcsMatrix {
    const rw = 0.2126, gw = 0.7152, bw = 0.0722;
    final invSat = 1.0 - saturation;
    final c = contrast;
    final offset = 128.0 * (1.0 - c) + brightness * 255.0;
    final sr = rw * invSat, sg = gw * invSat, sb = bw * invSat;
    return <double>[
      c * (sr + saturation), c * sg, c * sb, 0, offset,
      c * sr, c * (sg + saturation), c * sb, 0, offset,
      c * sr, c * sg, c * (sb + saturation), 0, offset,
      0, 0, 0, 1, 0,
    ];
  }

  // Composes 4x5 affine color transform `outer(inner(rgba))` in 0..255 space.
  static List<double> _composeColorMatrices(
    List<double> outer,
    List<double> inner,
  ) {
    final result = List<double>.filled(20, 0.0);
    for (var r = 0; r < 4; r++) {
      final ro = r * 5;
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += outer[ro + k] * inner[k * 5 + c];
        }
        result[ro + c] = sum;
      }
      var tx = outer[ro + 4];
      for (var k = 0; k < 4; k++) {
        tx += outer[ro + k] * inner[k * 5 + 4];
      }
      result[ro + 4] = tx;
    }
    return result;
  }

  ViewerDisplayConfig copyWith({
    bool? coverFit,
    bool? mirrored,
    int? quarterTurns,
    bool? audioMuted,
    bool? isFullscreen,
    bool? fullscreenHudVisible,
    bool? showTelemetry,
    bool? showGrid,
    AspectPreset? aspectPreset,
    double? digitalZoom,
    double? panX,
    double? panY,
    double? brightness,
    double? contrast,
    double? saturation,
    StudioLookPreset? lookPreset,
    bool? vignette,
    double? audioGain,
    int? audioDelayMs,
    bool? isVideoPaused,
    PortraitBokehMode? bokehMode,
    double? faceFillLight,
    bool? deskCamMode,
    double? keystoneVertical,
    double? keystoneHorizontal,
  }) => ViewerDisplayConfig(
    coverFit: coverFit ?? this.coverFit,
    mirrored: mirrored ?? this.mirrored,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    audioMuted: audioMuted ?? this.audioMuted,
    isFullscreen: isFullscreen ?? this.isFullscreen,
    fullscreenHudVisible: fullscreenHudVisible ?? this.fullscreenHudVisible,
    showTelemetry: showTelemetry ?? this.showTelemetry,
    showGrid: showGrid ?? this.showGrid,
    aspectPreset: aspectPreset ?? this.aspectPreset,
    digitalZoom: digitalZoom ?? this.digitalZoom,
    panX: panX ?? this.panX,
    panY: panY ?? this.panY,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    lookPreset: lookPreset ?? this.lookPreset,
    vignette: vignette ?? this.vignette,
    audioGain: audioGain ?? this.audioGain,
    audioDelayMs: audioDelayMs ?? this.audioDelayMs,
    isVideoPaused: isVideoPaused ?? this.isVideoPaused,
    bokehMode: bokehMode ?? this.bokehMode,
    faceFillLight: faceFillLight ?? this.faceFillLight,
    deskCamMode: deskCamMode ?? this.deskCamMode,
    keystoneVertical: keystoneVertical ?? this.keystoneVertical,
    keystoneHorizontal: keystoneHorizontal ?? this.keystoneHorizontal,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewerDisplayConfig &&
          runtimeType == other.runtimeType &&
          coverFit == other.coverFit && mirrored == other.mirrored &&
          quarterTurns == other.quarterTurns && audioMuted == other.audioMuted &&
          isFullscreen == other.isFullscreen &&
          fullscreenHudVisible == other.fullscreenHudVisible &&
          showTelemetry == other.showTelemetry && showGrid == other.showGrid &&
          aspectPreset == other.aspectPreset &&
          digitalZoom == other.digitalZoom &&
          panX == other.panX && panY == other.panY &&
          brightness == other.brightness && contrast == other.contrast &&
          saturation == other.saturation && lookPreset == other.lookPreset &&
          vignette == other.vignette && audioGain == other.audioGain &&
          audioDelayMs == other.audioDelayMs &&
          isVideoPaused == other.isVideoPaused &&
          bokehMode == other.bokehMode && faceFillLight == other.faceFillLight &&
          deskCamMode == other.deskCamMode &&
          keystoneVertical == other.keystoneVertical &&
          keystoneHorizontal == other.keystoneHorizontal;

  @override
  int get hashCode => Object.hashAll([
    coverFit, mirrored, quarterTurns, audioMuted, isFullscreen,
    fullscreenHudVisible, showTelemetry, showGrid, aspectPreset, digitalZoom,
    panX, panY, brightness, contrast, saturation, lookPreset, vignette,
    audioGain, audioDelayMs, isVideoPaused, bokehMode, faceFillLight,
    deskCamMode, keystoneVertical, keystoneHorizontal,
  ]);
}
