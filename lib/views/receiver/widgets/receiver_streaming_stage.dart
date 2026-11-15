import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/session_provider.dart';
import '../../shared/error_banner.dart';
import '../../shared/video_stage_widget.dart';
import 'receiver_controls_bar.dart';
import 'telemetry_overlay.dart';

/// Active receiver video stage supporting windowed controls and immersive fullscreen.
class const ReceiverStreamingStage({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
  required final VoidCallback onDismissError,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final waitingLabel = switch (session.phase) {
      .connecting => 'Negotiating WebRTC stream...',
      .reconnecting => 'Reconnecting to sender...',
      _ => 'Waiting for video stream...',
    };

    if (display.isFullscreen) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: VideoStageWidget(
                stream: session.remoteStream,
                displayConfig: display,
                borderRadius: 0,
                waitingLabel: waitingLabel,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const .all(16),
                child: Stack(
                  children: [
                    if (display.showTelemetry)
                      Align(
                        alignment: Alignment.topLeft,
                        child: TelemetryOverlay(telemetry: session.telemetry),
                      ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FilledButton.tonalIcon(
                        onPressed: onExitFullscreen,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.backgroundDark.withValues(alpha: 0.78),
                          foregroundColor: AppColors.textPrimaryDark,
                        ),
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                        label: const Text('Exit Fullscreen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: VideoStageWidget(
                    stream: session.remoteStream,
                    displayConfig: display,
                    waitingLabel: waitingLabel,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Wrap(
                    alignment: .spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (display.showTelemetry) TelemetryOverlay(telemetry: session.telemetry),
                      if (session.connectedPeerName != null)
                        _PeerBadge(name: session.connectedPeerName!),
                    ],
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
      padding: const .symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.72),
        borderRadius: .circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.primaryLight),
          Text(
            name,
            style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 12, fontWeight: .w600),
          ),
        ],
      ),
    );
  }
}
