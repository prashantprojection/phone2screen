import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/constants/stream_constants.dart';
import '../../models/stream_telemetry.dart';

/// Polls WebRTC `getStats()` at 1Hz to compute video Mbps, resolution, fps,
/// and connected duration while driving DataChannel ping heartbeats.
class RtcStatsSampler {
  final StreamController<StreamTelemetry> _controller =
      StreamController<StreamTelemetry>.broadcast();

  Timer? _timer;
  DateTime? _connectedAt;
  DateTime? _lastSampleTime;
  int _lastBytes = 0;
  bool _disposed = false;

  /// Broadcast stream of 1Hz [StreamTelemetry] samples.
  Stream<StreamTelemetry> get stream => _controller.stream;

  /// Begins 1Hz telemetry polling for [pc].
  void start(
    RTCPeerConnection pc, {
    required bool isSender,
    required int Function() readDataChannelRttMs,
    required void Function() onTick,
  }) {
    stop();
    _connectedAt = DateTime.now();
    _timer = Timer.periodic(StreamConstants.pingInterval, (_) {
      onTick();
      unawaited(
        _sample(pc, isSender: isSender, readRttMs: readDataChannelRttMs),
      );
    });
  }

  /// Stops periodic stats polling and resets byte/duration baselines.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _connectedAt = null;
    _lastSampleTime = null;
    _lastBytes = 0;
  }

  Future<void> _sample(
    RTCPeerConnection pc, {
    required bool isSender,
    required int Function() readRttMs,
  }) async {
    if (_disposed) return;
    try {
      final reports = await pc.getStats();
      final targetType = isSender ? 'outbound-rtp' : 'inbound-rtp';
      final byteKey = isSender ? 'bytesSent' : 'bytesReceived';

      var bytes = 0;
      var width = 0;
      var height = 0;
      var fps = 0;
      var pairRttMs = 0;

      for (final report in reports) {
        final values = report.values;
        if (report.type == targetType &&
            (values['kind'] == 'video' || values['mediaType'] == 'video')) {
          bytes = _asInt(values[byteKey]);
          width = _asInt(values['frameWidth']);
          height = _asInt(values['frameHeight']);
          fps = _asInt(values['framesPerSecond']);
        } else if (report.type == 'candidate-pair' &&
            values['state'] == 'succeeded' &&
            values['nominated'] == true) {
          final rttSec = _asDouble(values['currentRoundTripTime']);
          if (rttSec > 0) pairRttMs = (rttSec * 1000).round();
        }
      }

      final now = DateTime.now();
      var bitrateMbps = 0.0;
      if (_lastSampleTime != null && bytes >= _lastBytes) {
        final elapsedMs = now.difference(_lastSampleTime!).inMilliseconds;
        if (elapsedMs > 0) {
          bitrateMbps = ((bytes - _lastBytes) * 8.0) / (elapsedMs * 1000.0);
        }
      }
      _lastSampleTime = now;
      _lastBytes = bytes;

      final dcRtt = readRttMs();
      final duration = _connectedAt != null
          ? now.difference(_connectedAt!)
          : Duration.zero;
      if (!_disposed) {
        _controller.add(
          StreamTelemetry(
            latencyMs: dcRtt > 0 ? dcRtt : pairRttMs,
            bitrateMbps: bitrateMbps,
            width: width,
            height: height,
            fps: fps,
            connectedDuration: duration,
          ),
        );
      }
    } catch (_) {
      // PeerConnection may close mid-poll; ignore transient stats errors.
    }
  }

  static int _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => num.tryParse(v)?.round() ?? 0,
    _ => 0,
  };

  static double _asDouble(Object? value) => switch (value) {
    final double v => v,
    final num v => v.toDouble(),
    final String v => double.tryParse(v) ?? 0.0,
    _ => 0.0,
  };

  /// Permanently stops sampling and closes the telemetry stream.
  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _controller.close();
  }
}
