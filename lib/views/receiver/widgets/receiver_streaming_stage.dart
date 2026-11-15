import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../shared/error_banner.dart';
import '../../shared/video_stage_widget.dart';
import 'fullscreen_stage_view.dart';
import 'multi_cam_grid_view.dart';
import 'receiver_controls_bar.dart';
import 'telemetry_overlay.dart';

/// Active receiver video stage supporting windowed multi-cam, OBS Clean View, and fullscreen.
class const ReceiverStreamingStage({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
  required final VoidCallback onDismissError,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (display.isFullscreen) {
      return FullscreenStageView(
        session: session,
        display: display,
        onExitFullscreen: onExitFullscreen,
      );
    }

    final waitingLabel = switch (session.phase) {
      .connecting => 'Connecting live video...',
      .reconnecting => 'Reconnecting to sender...',
      _ => 'Waiting for video stream...',
    };
    final multiCam = ref.watch(multiCamProvider);
    final selectedSlot = multiCam.selectedPeerId != null
        ? multiCam.secondarySlots[multiCam.selectedPeerId]
        : null;
    final activeStream = selectedSlot?.stream ?? session.remoteStream;
    final activeDisplay = (selectedSlot?.displayConfig ?? display).copyWith(
      cleanFeedMode: display.cleanFeedMode,
      audioMuted: display.audioMuted || (selectedSlot?.displayConfig.audioMuted ?? false),
    );

    if (display.cleanFeedMode) {
      return SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: GestureDetector(
            behavior: .opaque,
            onDoubleTap: () => ref.read(viewerDisplayProvider.notifier).setCleanFeed(false),
            child: VideoStageWidget(
              stream: activeStream,
              displayConfig: activeDisplay,
              borderRadius: 0,
              waitingLabel: waitingLabel,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (session.errorMessage != null)
          Padding(
            padding: const .fromLTRB(16, 12, 16, 0),
            child: ErrorBanner(message: session.errorMessage!, onDismiss: onDismissError),
          ),
        Expanded(
          child: Padding(
            padding: const .fromLTRB(16, 12, 16, 8),
            child: multiCam.secondarySlots.isNotEmpty
                ? MultiCamGridView(session: session, display: display)
                : Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: .opaque,
                          onDoubleTap: () =>
                              ref.read(viewerDisplayProvider.notifier).toggleFullscreen(),
                          child: VideoStageWidget(
                            stream: session.remoteStream,
                            displayConfig: display,
                            waitingLabel: waitingLabel,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: IgnorePointer(
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
                      ),
                    ],
                  ),
          ),
        ),
        const Padding(
          padding: .fromLTRB(16, 4, 16, 16),
          child: ReceiverControlsBar(),
        ),
      ],
    );
  }
}

class const _PeerBadge({required final String name}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.72),
        borderRadius: .circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 7,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppColors.accentGreen, shape: .circle),
          ),
          const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.primaryLight),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              name,
              overflow: .ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimaryDark,
                fontSize: 12,
                fontWeight: .w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
