import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';

/// Floating studio control dock for viewport transforms, audio, sharing, and disconnect.
class const ReceiverControlsBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(viewerDisplayProvider);
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);
    final colors = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    final fitLabel = display.coverFit ? 'Fill' : 'Fit';
    final audioLabel = display.audioMuted ? 'Muted' : 'Audio';
    final fsLabel = display.isFullscreen ? 'Windowed' : 'Fullscreen';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: .symmetric(horizontal: compact ? 8 : 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: .circular(20),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: .horizontal,
            child: Row(
              mainAxisSize: .min,
              spacing: compact ? 6 : 8,
              children: [
                _DockButton(
                  icon: display.coverFit
                      ? Icons.fit_screen_rounded
                      : Icons.aspect_ratio_rounded,
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
                if (!compact)
                  Container(
                    width: 1,
                    height: 24,
                    margin: const .symmetric(horizontal: 2),
                    color: colors.outlineVariant,
                  ),
                _DockButton(
                  icon: display.audioMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: compact ? null : audioLabel,
                  tooltip: shortcuts.tooltipFor(audioLabel, .toggleMute),
                  accentColor: display.audioMuted ? AppColors.accentOrange : null,
                  onPressed: notifier.toggleMute,
                ),
                _DockButton(
                  icon: Icons.content_paste_go_rounded,
                  label: compact ? null : 'Share Text',
                  tooltip: shortcuts.tooltipFor('Share Text', .openClipboard),
                  onPressed: () => ClipboardSyncSheet.show(context),
                ),
                _DockButton(
                  icon: display.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: compact ? null : fsLabel,
                  tooltip: shortcuts.tooltipFor(fsLabel, .toggleFullscreen),
                  active: display.isFullscreen,
                  onPressed: notifier.toggleFullscreen,
                ),
                Tooltip(
                  message: shortcuts.tooltipFor('Disconnect', .disconnectStream),
                  child: FilledButton.icon(
                    onPressed: () => ref.read(sessionProvider.notifier).disconnect(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentRed,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 42),
                      padding: .symmetric(horizontal: compact ? 12 : 14),
                      shape: RoundedRectangleBorder(borderRadius: .circular(12)),
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
    );
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
    final colors = Theme.of(context).colorScheme;
    final tone = accentColor ?? (active ? colors.primary : null);
    final fg = tone ?? colors.onSurface;
    final bg = tone != null ? tone.withValues(alpha: 0.16) : colors.surfaceContainer;
    final border = tone != null
        ? tone.withValues(alpha: 0.48)
        : colors.outlineVariant.withValues(alpha: 0.7);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(12),
          side: BorderSide(color: border),
        ),
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 42,
            width: label == null ? 42 : null,
            child: Padding(
              padding: .symmetric(horizontal: label == null ? 0 : 12),
              child: Row(
                mainAxisSize: .min,
                mainAxisAlignment: .center,
                spacing: 6,
                children: [
                  Icon(icon, size: label == null ? 20 : 18, color: fg),
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
