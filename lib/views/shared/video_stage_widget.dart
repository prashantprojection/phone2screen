import 'dart:async';
import 'dart:math' as math;

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
    if (streamChanged && _initialized) _renderer.srcObject = widget.stream;
    if (streamChanged || muteChanged) _syncAudioMute(forceApply: muteChanged);
  }

  void _syncAudioMute({required bool forceApply}) {
    final stream = widget.stream;
    if (stream == null) return;
    final muted = widget.displayConfig.audioMuted;
    // Avoid overriding local sender mic state unless audioMuted is active or changed.
    if (!forceApply && !muted) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
      if (!kIsWeb) unawaited(_applyTrackVolume(track, muted ? 0.0 : 1.0));
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
    return ClipRRect(
      borderRadius: .circular(widget.borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: config.cleanFeedMode ? Colors.black : AppColors.backgroundDark,
        ),
        child: stream == null || !_initialized
            ? _WaitingPlaceholder(label: widget.waitingLabel)
            : _buildGradedStage(config),
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

    if (config.showGrid && !config.cleanFeedMode) {
      framed = Stack(
        fit: .expand,
        children: [
          framed,
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

class const _WaitingPlaceholder({required final String label})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            const Icon(
              Icons.cast_connected_rounded,
              size: 40,
              color: AppColors.primaryLight,
            ),
            Text(
              label,
              textAlign: .center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
            ),
          ],
        ),
      ),
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
