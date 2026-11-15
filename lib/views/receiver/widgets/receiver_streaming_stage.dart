import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/virtual_cam_provider.dart';
import '../../shared/error_banner.dart';
import '../../shared/video_stage_widget.dart';
import 'fullscreen_stage_view.dart';
import 'multi_cam_grid_view.dart';
import 'receiver_controls_bar.dart';
import 'telemetry_overlay.dart';

/// Active receiver video stage supporting windowed multi-cam and unified clean fullscreen.
class const ReceiverStreamingStage({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
  required final VoidCallback onDismissError,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ReceiverStreamingStage> createState() =>
      _ReceiverStreamingStageState();
}

class _ReceiverStreamingStageState extends ConsumerState<ReceiverStreamingStage> {
  ({bool isStreaming, bool isPaused})? _lastVcamSync;
  bool _syncScheduled = false;

  bool get _effectivePaused =>
      widget.display.isVideoPaused || widget.session.remoteCameraState.videoPaused;

  @override
  void initState() {
    super.initState();
    _scheduleVcamSync();
  }

  @override
  void didUpdateWidget(covariant ReceiverStreamingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleVcamSync();
  }

  void _scheduleVcamSync() {
    if (!mounted) return;
    final vcam = ref.read(nativeVirtualCamProvider);
    if (!vcam.isSupported || !vcam.isRegistered) {
      _lastVcamSync = null;
      return;
    }
    final next = (isStreaming: widget.session.phase == .streaming, isPaused: _effectivePaused);
    if (_lastVcamSync == next || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final current = ref.read(nativeVirtualCamProvider);
      if (!current.isSupported || !current.isRegistered) {
        _lastVcamSync = null;
        return;
      }
      final target = (isStreaming: widget.session.phase == .streaming, isPaused: _effectivePaused);
      if (_lastVcamSync == target) return;
      _lastVcamSync = target;
      unawaited(
        ref.read(nativeVirtualCamProvider.notifier).syncStreamState(
          isStreaming: target.isStreaming,
          isPaused: target.isPaused,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final display = widget.display;
    final effectivePaused = _effectivePaused;

    ref.listen<bool>(
      nativeVirtualCamProvider.select((s) => s.isRegistered),
      (_, _) => _scheduleVcamSync(),
    );
    final vcamNotifier = ref.watch(nativeVirtualCamProvider.notifier);

    if (display.isFullscreen) {
      return FullscreenStageView(
        session: session,
        display: display,
        onExitFullscreen: widget.onExitFullscreen,
      );
    }

    final waitingLabel = switch (session.phase) {
      .connecting => 'Connecting live video...',
      .reconnecting => 'Reconnecting to sender...',
      _ => 'Waiting for video stream...',
    };
    final multiCam = ref.watch(multiCamProvider);
    final isMultiCam = multiCam.secondarySlots.isNotEmpty;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: .expand,
        children: [
          Positioned.fill(
            child: isMultiCam
                ? MultiCamGridView(session: session, display: display)
                : GestureDetector(
                    behavior: .opaque,
                    onDoubleTap: () => ref.read(viewerDisplayProvider.notifier).toggleFullscreen(),
                    child: RepaintBoundary(
                      key: vcamNotifier.stageBoundaryKey,
                      child: VideoStageWidget(
                        stream: session.remoteStream,
                        displayConfig: display,
                        isPaused: effectivePaused,
                        borderRadius: 0,
                        waitingLabel: waitingLabel,
                      ),
                    ),
                  ),
          ),
          if (!isMultiCam) _scrim(top: true),
          if (!isMultiCam || session.errorMessage != null)
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: 10,
                children: [
                  if (session.errorMessage != null)
                    Material(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
                      borderRadius: .circular(12),
                      child: ErrorBanner(message: session.errorMessage!, onDismiss: widget.onDismissError),
                    ),
                  if (!isMultiCam)
                    IgnorePointer(
                      child: Wrap(
                        alignment: .spaceBetween,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          display.showTelemetry
                              ? TelemetryOverlay(telemetry: session.telemetry)
                              : const SizedBox.shrink(),
                          if (session.connectedPeerName != null)
                            _PeerBadge(name: session.connectedPeerName!),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          _scrim(top: false),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: SafeArea(top: false, child: ReceiverControlsBar()),
          ),
        ],
      ),
    );
  }

  Widget _scrim({required bool top}) => Positioned(
    top: top ? 0 : null,
    bottom: top ? null : 0,
    left: 0,
    right: 0,
    height: top ? 84 : 96,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: top
                ? [Colors.black.withValues(alpha: 0.55), Colors.transparent]
                : [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
          ),
        ),
      ),
    ),
  );
}

class const _PeerBadge({required final String name}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: .circular(999),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: const .symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF121418).withValues(alpha: 0.78),
          borderRadius: .circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 7,
          children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: .circle)),
            const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.primaryLight),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                name,
                overflow: .ellipsis,
                style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 12, fontWeight: .w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
