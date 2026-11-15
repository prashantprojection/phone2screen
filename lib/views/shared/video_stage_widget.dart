import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../models/viewer_display_config.dart';

/// WebRTC [MediaStream] video stage with immediate srcObject binding, GPU
/// framing transforms, BT.709 color grading, and optional Rule-of-Thirds grid.
class const VideoStageWidget({
  super.key,
  required final MediaStream? stream,
  final ViewerDisplayConfig displayConfig = const ViewerDisplayConfig(),
  final bool isPaused = false,
  final String waitingLabel = 'Waiting for video stream...',
  final double borderRadius = 16.0,
}) extends StatefulWidget {
  @override
  State<VideoStageWidget> createState() => _VideoStageWidgetState();
}

class _VideoStageWidgetState extends State<VideoStageWidget> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _initialized = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initRenderer());
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    if (!mounted || _disposed) {
      await _renderer.dispose();
      return;
    }
    // Bind initial stream right after initialization so already-ready streams render immediately.
    _renderer.srcObject = widget.stream;
    _initialized = true;
    _syncAudioMute(forceApply: false);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant VideoStageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final streamChanged =
        oldWidget.stream?.id != widget.stream?.id || oldWidget.stream != widget.stream;
    final muteChanged =
        oldWidget.displayConfig.audioMuted != widget.displayConfig.audioMuted;
    final gainChanged =
        oldWidget.displayConfig.audioGain != widget.displayConfig.audioGain;
    if (streamChanged && _initialized) _renderer.srcObject = widget.stream;
    if (streamChanged || muteChanged || gainChanged) {
      _syncAudioMute(forceApply: muteChanged || gainChanged);
    }
  }

  void _syncAudioMute({required bool forceApply}) {
    final stream = widget.stream;
    if (stream == null) return;
    final muted = widget.displayConfig.audioMuted;
    final gain = widget.displayConfig.audioGain.clamp(0.0, 2.0).toDouble();
    // Avoid overriding local sender mic state unless muted, gain-adjusted, or changed.
    if (!forceApply && !muted && gain == 1.0) return;
    final targetVolume = muted ? 0.0 : gain;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
      if (!kIsWeb) unawaited(_applyTrackVolume(track, targetVolume));
    }
  }

  Future<void> _applyTrackVolume(MediaStreamTrack track, double volume) async {
    try {
      await Helper.setVolume(volume, track);
    } catch (_) {
      // Ignore platforms or track implementations without volume control.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_initialized) {
      _renderer.srcObject = null;
      unawaited(_renderer.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final config = widget.displayConfig;
    final paused = widget.isPaused || config.isVideoPaused;
    return ClipRRect(
      borderRadius: .circular(widget.borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: config.isFullscreen ? Colors.black : const Color(0xFF07080A),
        ),
        child: Stack(
          fit: .expand,
          children: [
            stream == null || !_initialized
                ? _StageSlate(
                    icon: Icons.cast_connected_rounded,
                    iconColor: AppColors.primaryLight,
                    badgeFill: AppColors.primaryBlue.withValues(alpha: 0.12),
                    badgeBorder: AppColors.primaryLight.withValues(alpha: 0.28),
                    title: widget.waitingLabel,
                  )
                : _buildGradedStage(config),
            if (paused && stream != null)
              _StageSlate(
                icon: Icons.videocam_off_rounded,
                iconColor: AppColors.accentOrange,
                badgeFill: AppColors.accentOrange.withValues(alpha: 0.16),
                badgeBorder: AppColors.accentOrange.withValues(alpha: 0.48),
                title: 'Camera Paused',
                subtitle: 'Privacy Mode • Press P or Resume to go live',
                frosted: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradedStage(ViewerDisplayConfig config) {
    Widget video = RotatedBox(
      quarterTurns: config.quarterTurns % 4,
      child: RTCVideoView(
        _renderer,
        mirror: config.mirrored,
        objectFit: config.coverFit
            ? .RTCVideoViewObjectFitCover
            : .RTCVideoViewObjectFitContain,
      ),
    );

    if (config.hasColorAdjustments) {
      video = ColorFiltered(
        colorFilter: ColorFilter.matrix(config.colorMatrix),
        child: video,
      );
    }

    final zoom = config.digitalZoom.clamp(1.0, 3.0);
    final hasTransform = zoom != 1.0 || config.panX != 0.0 || config.panY != 0.0;
    Widget framed = hasTransform
        ? LayoutBuilder(
            builder: (context, constraints) {
              // Allow subtle panning even at 1.0x crop while scaling range with zoom.
              final maxShiftX = math.max(
                constraints.maxWidth * 0.2,
                constraints.maxWidth * (zoom - 1.0) / 2,
              );
              final maxShiftY = math.max(
                constraints.maxHeight * 0.2,
                constraints.maxHeight * (zoom - 1.0) / 2,
              );
              final dx = config.panX.clamp(-1.0, 1.0) * maxShiftX;
              final dy = config.panY.clamp(-1.0, 1.0) * maxShiftY;
              return ClipRect(
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(scale: zoom, child: video),
                ),
              );
            },
          )
        : ClipRect(child: video);

    // Hide the framing grid whenever fullscreen HUD controls are hidden for clean capture.
    final showGrid = config.showGrid && !(config.isFullscreen && !config.fullscreenHudVisible);
    if (config.vignette || showGrid) {
      framed = Stack(
        fit: .expand,
        children: [
          framed,
          if (config.vignette)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.88,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.52),
                    ],
                    stops: const [0.58, 1.0],
                  ),
                ),
              ),
            ),
          if (showGrid)
            const IgnorePointer(child: CustomPaint(painter: _ThirdsGridPainter())),
        ],
      );
    }

    final ratio = config.aspectPreset.aspectRatio;
    if (ratio != null) {
      framed = Center(
        child: AspectRatio(aspectRatio: ratio, child: ClipRect(child: framed)),
      );
    }
    return framed;
  }
}

class const _StageSlate({
  required final IconData icon,
  required final Color iconColor,
  required final Color badgeFill,
  required final Color badgeBorder,
  required final String title,
  final String? subtitle,
  final bool frosted = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 165 || constraints.maxWidth < 180;
        final boxSize = tight ? 48.0 : 70.0;
        return Center(
          child: SingleChildScrollView(
            padding: .all(tight ? 12 : 24),
            child: Column(
              mainAxisSize: .min,
              spacing: tight ? 8 : 12,
              children: [
                Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: BoxDecoration(
                    shape: .circle,
                    color: badgeFill,
                    border: Border.all(color: badgeBorder, width: 1.5),
                  ),
                  child: Icon(icon, size: tight ? 22 : 30, color: iconColor),
                ),
                Text(
                  title,
                  textAlign: .center,
                  style: (frosted ? textTheme.titleMedium : textTheme.bodyMedium)
                      ?.copyWith(
                        color: frosted
                            ? AppColors.textPrimaryDark
                            : AppColors.textSecondaryDark,
                        fontWeight: frosted ? .w700 : .w500,
                      ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    textAlign: .center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondaryDark,
                      fontSize: tight ? 11 : null,
                      fontWeight: .w500,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!frosted) return body;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: ColoredBox(color: const Color(0xEB0B0E14), child: body),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  const _ThirdsGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0
      ..style = .stroke;

    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ThirdsGridPainter oldDelegate) => false;
}

// Shared _StageSlate handles both waiting and privacy-paused slates below.
