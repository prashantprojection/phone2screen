import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';

/// Receiver viewport controls for fit, rotation, mirror, audio, clipboard, and disconnect.
class const ReceiverControlsBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(viewerDisplayProvider);
    final notifier = ref.read(viewerDisplayProvider.notifier);

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
              label: display.coverFit ? 'Fill' : 'Fit',
              active: display.coverFit,
              onPressed: notifier.toggleFit,
            ),
            _StageActionButton(
              icon: Icons.rotate_right_rounded,
              label: 'Rotate',
              active: display.quarterTurns % 4 != 0,
              onPressed: notifier.rotate90,
            ),
            _StageActionButton(
              icon: Icons.flip_rounded,
              label: 'Mirror',
              active: display.mirrored,
              onPressed: notifier.toggleMirror,
            ),
            _StageActionButton(
              icon: display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: display.audioMuted ? 'Muted' : 'Audio',
              active: display.audioMuted,
              onPressed: notifier.toggleMute,
            ),
            _StageActionButton(
              icon: Icons.content_paste_go_rounded,
              label: 'Clipboard',
              onPressed: () => ClipboardSyncSheet.show(context),
            ),
            _StageActionButton(
              icon: Icons.speed_rounded,
              label: 'Stats',
              active: display.showTelemetry,
              onPressed: notifier.toggleTelemetry,
            ),
            _StageActionButton(
              icon: display.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              label: display.isFullscreen ? 'Windowed' : 'Fullscreen',
              active: display.isFullscreen,
              onPressed: notifier.toggleFullscreen,
            ),
            FilledButton.icon(
              onPressed: () => ref.read(sessionProvider.notifier).disconnect(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                foregroundColor: Colors.white,
                padding: const .symmetric(horizontal: 16, vertical: 11),
              ),
              icon: const Icon(Icons.call_end_rounded, size: 18),
              label: const Text('Disconnect'),
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
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: .circular(12),
        child: Container(
          padding: const .symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: .circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Icon(icon, size: 18, color: fg),
              Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: .w600)),
            ],
          ),
        ),
      ),
    );
  }
}
