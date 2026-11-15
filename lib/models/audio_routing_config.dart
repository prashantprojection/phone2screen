/// Sender microphone DSP preset toggling WebRTC speech processing vs raw feed.
enum MicProcessingMode {
  voiceClean,
  studioRaw;

  String get label => switch (this) {
    .voiceClean => 'Voice Clean',
    .studioRaw => 'Studio Raw',
  };
}

/// Selectable local audio playback endpoint (speakers, headset, virtual cable).
class const AudioEndpointDevice({
  required final String id,
  required final String label,
  final bool isVirtualCable = false,
}) {
  static const List<String> _virtualCableTokens = [
    'vb-audio',
    'cable',
    'voicemeeter',
    'wave link',
    'sonar',
    'virtual audio',
    'blackhole',
  ];

  /// Returns `true` when [label] matches a known virtual audio cable driver.
  static bool detectVirtualCableLabel(String label) {
    final lower = label.toLowerCase();
    for (final token in _virtualCableTokens) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioEndpointDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          isVirtualCable == other.isVirtualCable;

  @override
  int get hashCode => Object.hash(id, label, isVirtualCable);
}

/// Persistent studio audio routing, gain, lip-sync offset, and mic DSP mode.
class const AudioStudioConfig({
  final String? outputDeviceId,
  final double gain = 1.0,
  final int lipSyncDelayMs = 0,
  final MicProcessingMode micMode = .voiceClean,
}) {
  AudioStudioConfig copyWith({
    String? outputDeviceId,
    bool clearOutputDevice = false,
    double? gain,
    int? lipSyncDelayMs,
    MicProcessingMode? micMode,
  }) => AudioStudioConfig(
    outputDeviceId: clearOutputDevice
        ? null
        : (outputDeviceId ?? this.outputDeviceId),
    gain: (gain ?? this.gain).clamp(0.0, 2.0).toDouble(),
    lipSyncDelayMs: (lipSyncDelayMs ?? this.lipSyncDelayMs).clamp(0, 500),
    micMode: micMode ?? this.micMode,
  );

  Map<String, dynamic> toJson() => {
    if (outputDeviceId != null) 'outputDeviceId': outputDeviceId,
    'gain': gain,
    'lipSyncDelayMs': lipSyncDelayMs,
    'micMode': micMode.name,
  };

  factory AudioStudioConfig.fromJson(Map<String, dynamic> json) {
    final rawId = json['outputDeviceId'];
    final rawGain = json['gain'];
    final parsedGain = rawGain is num && rawGain.toDouble().isFinite
        ? rawGain.toDouble().clamp(0.0, 2.0).toDouble()
        : 1.0;
    final rawDelay = json['lipSyncDelayMs'];
    final parsedDelay = rawDelay is num && rawDelay.toDouble().isFinite
        ? rawDelay.toInt().clamp(0, 500)
        : 0;
    return AudioStudioConfig(
      outputDeviceId: rawId is String && rawId.isNotEmpty ? rawId : null,
      gain: parsedGain,
      lipSyncDelayMs: parsedDelay,
      micMode: _parseMicMode(json['micMode']),
    );
  }

  static MicProcessingMode _parseMicMode(Object? raw) {
    if (raw is! String) return .voiceClean;
    for (final mode in MicProcessingMode.values) {
      if (mode.name == raw) return mode;
    }
    return .voiceClean;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioStudioConfig &&
          runtimeType == other.runtimeType &&
          outputDeviceId == other.outputDeviceId &&
          gain == other.gain &&
          lipSyncDelayMs == other.lipSyncDelayMs &&
          micMode == other.micMode;

  @override
  int get hashCode =>
      Object.hash(outputDeviceId, gain, lipSyncDelayMs, micMode);
}
