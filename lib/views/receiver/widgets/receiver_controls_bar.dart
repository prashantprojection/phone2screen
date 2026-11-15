import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';
import 'remote_camera_panel.dart';

/// Floating studio control dock for viewport transforms, camera rig, OBS clean view, and disconnect.
class const ReceiverControlsBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(viewerDisplayProvider);
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);
    final platform = ref.watch(platformServiceProvider);
    final session = ref.watch(sessionProvider);
    final multiCam = ref.watch(multiCamProvider);
    final compact = context.isCompact;
    final isDesktop = !platform.isWeb && platform.isDesktop;

    final fitLabel = display.coverFit ? 'Fill' : 'Fit';
    final audioLabel = display.audioMuted ? 'Muted' : 'Audio';
    final fsLabel = display.isFullscreen ? 'Windowed' : 'Fullscreen';
    final rigActive =
        display.hasColorAdjustments || display.hasFramingAdjustments || display.showGrid;
    final canOpenWindow =
        multiCam.childWindows.length < StreamConstants.maxDesktopReceiverPeers - 1;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: .circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: .circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: .symmetric(horizontal: compact ? 8 : 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161A).withValues(alpha: 0.84),
                  borderRadius: .circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  child: Row(
                    mainAxisSize: .min,
                    spacing: compact ? 6 : 7,
                    children: [
                      _DockButton(
                        icon: display.coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                        tooltip: shortcuts.tooltipFor(fitLabel, .toggleFit),
                        active: display.coverFit,
                        onPressed: notifier.toggleFit,
                      ),
                      _DockButton(
                        icon: Icons.rotate_right_rounded,
                        tooltip: shortcuts.tooltipFor('Rotate 90°', .rotateVideo),
                        active: display.quarterTurns % 4 != 0,
                        onPressed: notifier.rotate90,
                      ),
                      _DockButton(
                        icon: Icons.flip_rounded,
                        tooltip: shortcuts.tooltipFor('Mirror', .toggleMirror),
                        active: display.mirrored,
                        onPressed: notifier.toggleMirror,
                      ),
                      _DockButton(
                        icon: Icons.speed_rounded,
                        tooltip: shortcuts.tooltipFor('Live Stats', .toggleStats),
                        active: display.showTelemetry,
                        onPressed: notifier.toggleTelemetry,
                      ),
                      if (!compact) _divider(),
                      _DockButton(
                        icon: Icons.tune_rounded,
                        label: compact ? null : 'Camera Rig',
                        tooltip: shortcuts.tooltipFor('Camera Rig & Color', .openCameraRig),
                        active: rigActive,
                        accentColor: rigActive ? AppColors.cyanAccent : null,
                        onPressed: () => RemoteCameraPanel.show(context),
                      ),
                      _DockButton(
                        icon: Icons.crop_free_rounded,
                        label: compact ? null : 'OBS Clean',
                        tooltip: shortcuts.tooltipFor('OBS Clean View', .toggleCleanFeed),
                        active: display.cleanFeedMode,
                        accentColor: display.cleanFeedMode ? AppColors.cyanAccent : null,
                        onPressed: notifier.toggleCleanFeed,
                      ),
                      if (isDesktop)
                        _DockButton(
                          icon: Icons.open_in_new_rounded,
                          label: compact ? null : '+ Window',
                          tooltip: canOpenWindow ? 'Open secondary camera window' : 'Max camera windows open',
                          onPressed: () => _openWindow(context, ref),
                        ),
                      if (!compact) _divider(),
                      _DockButton(
                        icon: display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        label: compact ? null : audioLabel,
                        tooltip: shortcuts.tooltipFor(audioLabel, .toggleMute),
                        accentColor: display.audioMuted ? AppColors.accentOrange : null,
                        onPressed: notifier.toggleMute,
                      ),
                      _DockButton(
                        icon: Icons.content_paste_go_rounded,
                        tooltip: shortcuts.tooltipFor('Share Text', .openClipboard),
                        onPressed: () => ClipboardSyncSheet.show(context),
                      ),
                      _DockButton(
                        icon: display.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        label: compact ? null : fsLabel,
                        tooltip: shortcuts.tooltipFor(fsLabel, .toggleFullscreen),
                        active: display.isFullscreen,
                        onPressed: notifier.toggleFullscreen,
                      ),
                      Tooltip(
                        message: shortcuts.tooltipFor('Disconnect', .disconnectStream),
                        child: FilledButton.icon(
                          onPressed: () async {
                            final hasPrimary = session.phase == .streaming ||
                                session.phase == .connecting ||
                                session.phase == .reconnecting;
                            if (hasPrimary) {
                              await ref.read(sessionProvider.notifier).disconnect();
                            } else {
                              await ref.read(multiCamProvider.notifier).disconnectAll();
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentRed,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 40),
                            padding: .symmetric(horizontal: compact ? 12 : 16),
                            shape: const StadiumBorder(),
                          ),
                          icon: Icon(Icons.call_end_rounded, size: compact ? 17 : 18),
                          label: Text(compact ? 'End' : 'Disconnect'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 22,
    margin: const .symmetric(horizontal: 2),
    color: Colors.white.withValues(alpha: 0.14),
  );

  Future<void> _openWindow(BuildContext context, WidgetRef ref) async {
    final entry = await ref.read(multiCamProvider.notifier).openCameraWindow();
    if (entry == null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Maximum camera windows already open.')));
    }
  }
}

class const _DockButton({
  required final IconData icon,
  final String? label,
  required final String tooltip,
  final bool active = false,
  final Color? accentColor,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tone = accentColor ?? (active ? AppColors.primaryLight : null);
    final fg = tone ?? Colors.white.withValues(alpha: 0.92);
    final bg = tone != null
        ? tone.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.08);
    final border = tone != null
        ? tone.withValues(alpha: 0.50)
        : Colors.white.withValues(alpha: 0.12);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(999),
          side: BorderSide(color: border),
        ),
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 40,
            width: label == null ? 40 : null,
            child: Padding(
              padding: .symmetric(horizontal: label == null ? 0 : 12),
              child: Row(
                mainAxisSize: .min,
                mainAxisAlignment: .center,
                spacing: 6,
                children: [
                  Icon(icon, size: label == null ? 19 : 17, color: fg),
                  if (label case final text?)
                    Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: .w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
