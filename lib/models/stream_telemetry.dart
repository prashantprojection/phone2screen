/// Live WebRTC connection quality and media metrics sampled during streaming.
class const StreamTelemetry({
  final int latencyMs = 0,
  final double bitrateMbps = 0.0,
  final int width = 0,
  final int height = 0,
  final int fps = 0,
  final Duration connectedDuration = .zero,
}) {
  StreamTelemetry copyWith({
    int? latencyMs,
    double? bitrateMbps,
    int? width,
    int? height,
    int? fps,
    Duration? connectedDuration,
  }) {
    return StreamTelemetry(
      latencyMs: latencyMs ?? this.latencyMs,
      bitrateMbps: bitrateMbps ?? this.bitrateMbps,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      connectedDuration: connectedDuration ?? this.connectedDuration,
    );
  }
}
