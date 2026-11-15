import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/video_stage_widget.dart';
import 'telemetry_overlay.dart';

/// Immersive fullscreen receiver video stage with toggleable overlay controls.
class const FullscreenStageView({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<FullscreenStageView> createState() => _FullscreenStageViewState();
}

class _FullscreenStageViewState extends ConsumerState<FullscreenStageView> {
  bool _showEscToast = true;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _showEscToast = true;
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEscToast = false);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingLabel = switch (widget.session.phase) {
      .connecting => 'Connecting live video...',
      .reconnecting => 'Reconnecting to sender...',
      _ => 'Waiting for video stream...',
    };
    final compactTopCollision = context.isCompact && widget.display.showTelemetry && widget.display.fullscreenHudVisible;
    final toastTop = compactTopCollision ? 64.0 : 16.0;

    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: .expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: .opaque,
                onTap: () => ref.read(viewerDisplayProvider.notifier).toggleFullscreenHud(),
                child: VideoStageWidget(
                  stream: widget.session.remoteStream,
                  displayConfig: widget.display,
                  borderRadius: 0,
                  waitingLabel: waitingLabel,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: widget.display.fullscreenHudVisible
                  ? SafeArea(
                      key: const ValueKey('fullscreen-hud-visible'),
                      child: Padding(
                        padding: const .all(16),
                        child: Stack(
                          fit: .expand,
                          children: [
                            if (widget.display.showTelemetry)
                              Align(alignment: Alignment.topLeft, child: TelemetryOverlay(telemetry: widget.session.telemetry)),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: _FullscreenHudPill(display: widget.display, onExitFullscreen: widget.onExitFullscreen),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('fullscreen-hud-hidden')),
            ),
            IgnorePointer(
              child: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _showEscToast
                      ? Align(
                          key: const ValueKey('esc-toast-visible'),
                          alignment: Alignment.topCenter,
                          child: Padding(padding: .fromLTRB(16, toastTop, 16, 0), child: const _EscHintToast()),
                        )
                      : const SizedBox.shrink(key: ValueKey('esc-toast-hidden')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _FullscreenHudPill({
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);

    Widget quickIcon(IconData icon, String tip, bool active, VoidCallback onTap) => IconButton(
      onPressed: onTap,
      tooltip: tip,
      color: active ? AppColors.primaryLight : AppColors.textPrimaryDark,
      icon: Icon(icon),
    );

    return ClipRRect(
      borderRadius: .circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          type: .transparency,
          child: Container(
            padding: const .symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundDark.withValues(alpha: 0.78),
              borderRadius: .circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 6,
              alignment: .center,
              crossAxisAlignment: .center,
              children: [
                quickIcon(display.coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                    shortcuts.tooltipFor(display.coverFit ? 'Fit Screen' : 'Fill Screen', .toggleFit),
                    display.coverFit, notifier.toggleFit),
                quickIcon(Icons.rotate_right_rounded, shortcuts.tooltipFor('Rotate 90°', .rotateVideo),
                    display.quarterTurns % 4 != 0, notifier.rotate90),
                quickIcon(display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    shortcuts.tooltipFor(display.audioMuted ? 'Unmute' : 'Mute', .toggleMute),
                    display.audioMuted, notifier.toggleMute),
                Tooltip(
                  message: shortcuts.tooltipFor('Hide Controls', .toggleFullscreenHud),
                  child: OutlinedButton.icon(
                    onPressed: notifier.toggleFullscreenHud,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimaryDark,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                      padding: const .symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Hide Controls'),
                  ),
                ),
                Tooltip(
                  message: 'Exit Fullscreen (Esc)',
                  child: FilledButton.tonalIcon(
                    onPressed: onExitFullscreen,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      foregroundColor: AppColors.textPrimaryDark,
                      padding: const .symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.fullscreen_exit_rounded, size: 18),
                    label: const Text('Exit Fullscreen'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _EscHintToast() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const .symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.backgroundDark.withValues(alpha: 0.86),
      borderRadius: .circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: const Row(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        Icon(Icons.fullscreen_rounded, size: 20, color: AppColors.primaryLight),
        Flexible(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text('Press Esc to exit fullscreen', style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 13, fontWeight: .w700)),
              Text('Tap anywhere to toggle controls', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 11, fontWeight: .w500)),
            ],
          ),
        ),
      ],
    ),
  );
}
