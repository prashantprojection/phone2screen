import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/stream_telemetry.dart';

/// Translucent glassmorphic pill showing live RTT, resolution, bitrate, and uptime.
class const TelemetryOverlay({
  super.key,
  required final StreamTelemetry telemetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final res = telemetry.width > 0 && telemetry.height > 0
        ? '${telemetry.width}x${telemetry.height}'
        : '--';
    final bitrate = '${telemetry.bitrateMbps.toStringAsFixed(1)} Mbps';
    final duration = _formatDuration(telemetry.connectedDuration);

    return ClipRRect(
      borderRadius: .circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const .symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark.withValues(alpha: 0.72),
            borderRadius: .circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: .center,
            children: [
              Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accentGreen,
                      shape: .circle,
                    ),
                  ),
                  Text('${telemetry.latencyMs}ms', style: _metricStyle),
                ],
              ),
              Text(res, style: _metricStyle),
              Text(bitrate, style: _metricStyle),
              Text(duration, style: _metricStyle),
            ],
          ),
        ),
      ),
    );
  }

  static const TextStyle _metricStyle = TextStyle(
    color: AppColors.textPrimaryDark,
    fontSize: 12,
    fontWeight: .w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }
}
