import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/session_phase.dart';
import '../../../models/stream_config.dart';
import '../../../models/stream_telemetry.dart';

/// True-black `#000000` OLED burn-in-safe ON AIR tally screen shown while
/// Eco Dim Preview is active during streaming.
class const OledTallyView({
  super.key,
  required final String targetName,
  required final SessionPhase phase,
  required final StreamTelemetry telemetry,
  required final StreamConfig streamConfig,
  required final VoidCallback onShowPreview,
}) extends StatefulWidget {
  @override
  State<OledTallyView> createState() => _OledTallyViewState();
}

class _OledTallyViewState extends State<OledTallyView> {
  // Cycle softly across 5 offsets every 30s to prevent static-pixel OLED burn-in.
  static const List<Alignment> _shiftOffsets = [
    Alignment.center,
    Alignment(0.0, -0.14),
    Alignment(0.10, 0.08),
    Alignment(-0.10, 0.12),
    Alignment(0.06, -0.06),
  ];

  Timer? _shiftTimer;
  int _offsetIndex = 0;

  @override
  void initState() {
    super.initState();
    _shiftTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _offsetIndex = (_offsetIndex + 1) % _shiftOffsets.length);
    });
  }

  @override
  void dispose() {
    _shiftTimer?.cancel();
    _shiftTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = widget.phase == .streaming;
    final tallyColor = isLive ? AppColors.accentRed : AppColors.accentOrange;
    final durationText = _formatDuration(widget.telemetry.connectedDuration);
    final summary = _formatStreamSummary(widget.streamConfig);

    return Material(
      color: Colors.black,
      borderRadius: .circular(16),
      clipBehavior: .antiAlias,
      child: GestureDetector(
        behavior: .opaque,
        onDoubleTap: widget.onShowPreview,
        child: Padding(
          padding: const .fromLTRB(20, 54, 20, 20),
          child: AnimatedAlign(
            alignment: _shiftOffsets[_offsetIndex],
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: .min,
                spacing: 12,
                children: [
                  Container(
                    padding: const .symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: tallyColor.withValues(alpha: 0.14),
                      borderRadius: .circular(999),
                      border: Border.all(color: tallyColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: .min,
                      spacing: 8,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tallyColor.withValues(alpha: 0.85),
                            shape: .circle,
                          ),
                        ),
                        Text(
                          isLive ? 'ON AIR' : 'CONNECTING',
                          style: TextStyle(
                            color: tallyColor.withValues(alpha: 0.88),
                            fontSize: 12,
                            fontWeight: .w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.targetName,
                    maxLines: 1,
                    overflow: .ellipsis,
                    textAlign: .center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: .w600,
                    ),
                  ),
                  Text(
                    durationText,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: .w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    summary,
                    textAlign: .center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontWeight: .w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  OutlinedButton.icon(
                    onPressed: widget.onShowPreview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.72),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                      padding: const .symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Wake Preview'),
                  ),
                  Text(
                    'Double-tap anywhere to wake preview',
                    textAlign: .center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }

  String _formatStreamSummary(StreamConfig cfg) {
    final res = switch (cfg.resolution) {
      .p720 => '720p',
      .p1080 => '1080p',
      .p4k => '4K',
    };
    final source = cfg.sourceType == .screen
        ? 'Screen Share'
        : (cfg.cameraLens == .front ? 'Front Cam' : 'Back Cam');
    final mbps = widget.telemetry.bitrateMbps > 0
        ? widget.telemetry.bitrateMbps.toStringAsFixed(1)
        : (cfg.videoBitrate / 1_000_000).toStringAsFixed(1);
    return '$res • ${cfg.frameRate} FPS • $source • $mbps Mbps';
  }
}
