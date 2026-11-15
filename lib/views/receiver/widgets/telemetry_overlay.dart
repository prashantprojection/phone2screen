import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/stream_telemetry.dart';

/// Compact glassmorphic pill showing live status, resolution, bitrate, RTT, and uptime.
class const TelemetryOverlay({
  super.key,
  required final StreamTelemetry telemetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final duration = _formatDuration(telemetry.connectedDuration);
    final metrics = _buildMetrics(duration);

    return ClipRRect(
      borderRadius: .circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const .symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark.withValues(alpha: 0.72),
            borderRadius: .circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Wrap(
            spacing: 7,
            runSpacing: 2,
            crossAxisAlignment: .center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.accentGreen,
                  shape: .circle,
                ),
              ),
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const Text('•', style: _dotStyle),
                Text(metrics[i], style: _metricStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<String> _buildMetrics(String duration) {
    if (telemetry.width <= 0 && telemetry.bitrateMbps <= 0) {
      return ['Live', duration];
    }
    final res = _formatResolution(telemetry.width, telemetry.height);
    return [
      ?res,
      '${telemetry.bitrateMbps.toStringAsFixed(1)} Mbps',
      '${telemetry.latencyMs} ms',
      duration,
    ];
  }

  String? _formatResolution(int w, int h) {
    if (w <= 0 || h <= 0) return null;
    if (w >= 3840) return '4K';
    if (w == 1920) return '1080p';
    if (h == 720) return '720p';
    return '$w\u00D7$h';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }

  static const TextStyle _metricStyle = TextStyle(
    color: AppColors.textPrimaryDark,
    fontSize: 12,
    fontWeight: .w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle _dotStyle = TextStyle(
    color: AppColors.textSecondaryDark,
    fontSize: 11,
    fontWeight: .w600,
  );
}
