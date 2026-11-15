import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../models/viewer_display_config.dart';

/// WebRTC [MediaStream] video stage with immediate srcObject binding and transforms.
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
        decoration: const BoxDecoration(color: AppColors.backgroundDark),
        child: stream == null || !_initialized
            ? Center(
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
                        widget.waitingLabel,
                        textAlign: .center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : RotatedBox(
                quarterTurns: config.quarterTurns % 4,
                child: RTCVideoView(
                  _renderer,
                  mirror: config.mirrored,
                  objectFit: config.coverFit
                      ? .RTCVideoViewObjectFitCover
                      : .RTCVideoViewObjectFitContain,
                ),
              ),
      ),
    );
  }
}
