import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';

/// Receiver viewport controls for fit, rotation, mirror, audio, text sharing, and disconnect.
class const ReceiverControlsBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(viewerDisplayProvider);
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);
    final showHints = shortcuts.enabled && !context.isCompact;
    final fitLabel = display.coverFit ? 'Fill' : 'Fit';
    final audioLabel = display.audioMuted ? 'Muted' : 'Audio';
    final fsLabel = display.isFullscreen ? 'Windowed' : 'Fullscreen';

    return Card(
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: .center,
          crossAxisAlignment: .center,
          children: [
            _StageActionButton(
              icon: display.coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
              label: fitLabel,
              tooltip: shortcuts.tooltipFor(fitLabel, .toggleFit),
              shortcutHint: showHints ? shortcuts.hintFor(.toggleFit) : null,
              active: display.coverFit,
              onPressed: notifier.toggleFit,
            ),
            _StageActionButton(
              icon: Icons.rotate_right_rounded,
              label: 'Rotate',
              tooltip: shortcuts.tooltipFor('Rotate', .rotateVideo),
              shortcutHint: showHints ? shortcuts.hintFor(.rotateVideo) : null,
              active: display.quarterTurns % 4 != 0,
              onPressed: notifier.rotate90,
            ),
            _StageActionButton(
              icon: Icons.flip_rounded,
              label: 'Mirror',
              tooltip: shortcuts.tooltipFor('Mirror', .toggleMirror),
              shortcutHint: showHints ? shortcuts.hintFor(.toggleMirror) : null,
              active: display.mirrored,
              onPressed: notifier.toggleMirror,
            ),
            _StageActionButton(
              icon: display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: audioLabel,
              tooltip: shortcuts.tooltipFor(audioLabel, .toggleMute),
              shortcutHint: showHints ? shortcuts.hintFor(.toggleMute) : null,
              active: display.audioMuted,
              onPressed: notifier.toggleMute,
            ),
            _StageActionButton(
              icon: Icons.content_paste_go_rounded,
              label: 'Share Text',
              tooltip: shortcuts.tooltipFor('Share Text', .openClipboard),
              shortcutHint: showHints ? shortcuts.hintFor(.openClipboard) : null,
              onPressed: () => ClipboardSyncSheet.show(context),
            ),
            _StageActionButton(
              icon: Icons.speed_rounded,
              label: 'Stats',
              tooltip: shortcuts.tooltipFor('Stats', .toggleStats),
              shortcutHint: showHints ? shortcuts.hintFor(.toggleStats) : null,
              active: display.showTelemetry,
              onPressed: notifier.toggleTelemetry,
            ),
            _StageActionButton(
              icon: display.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              label: fsLabel,
              tooltip: shortcuts.tooltipFor(fsLabel, .toggleFullscreen),
              shortcutHint: showHints ? shortcuts.hintFor(.toggleFullscreen) : null,
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
                  padding: const .symmetric(horizontal: 16, vertical: 11),
                ),
                icon: const Icon(Icons.call_end_rounded, size: 18),
                label: Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    const Text('Disconnect'),
                    if (showHints)
                      _ShortcutKeycap(label: shortcuts.hintFor(.disconnectStream), inverted: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _StageActionButton({
  required final IconData icon,
  required final String label,
  required final String tooltip,
  final String? shortcutHint,
  final bool active = false,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = active ? colors.primary : colors.onSurface;
    final bg = active ? colors.primary.withValues(alpha: 0.14) : colors.surfaceContainer;
    final border = active ? colors.primary.withValues(alpha: 0.5) : colors.outlineVariant;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: .circular(12),
        child: Container(
          padding: const .symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: .circular(12), border: Border.all(color: border)),
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Icon(icon, size: 18, color: fg),
              Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: .w600)),
              if (shortcutHint case final hint? when hint.isNotEmpty) _ShortcutKeycap(label: hint, active: active),
            ],
          ),
        ),
      ),
    );
  }
}

class const _ShortcutKeycap({
  required final String label,
  final bool active = false,
  final bool inverted = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = inverted
        ? Colors.white.withValues(alpha: 0.18)
        : (active ? colors.primary.withValues(alpha: 0.16) : colors.onSurface.withValues(alpha: 0.08));
    final border = inverted
        ? Colors.white.withValues(alpha: 0.32)
        : (active ? colors.primary.withValues(alpha: 0.38) : colors.outlineVariant);
    final fg = inverted ? Colors.white : (active ? colors.primary : colors.onSurfaceVariant);

    return Container(
      padding: const .symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: .circular(5), border: Border.all(color: border)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: .w700, height: 1.2)),
    );
  }
}
