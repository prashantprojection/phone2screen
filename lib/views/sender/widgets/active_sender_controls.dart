import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/media_source_type.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';
import 'desktop_source_dialog.dart';

/// Centered call-style floating control dock for active Sender broadcasts.
class const ActiveSenderControls({super.key}) extends ConsumerWidget {
  Future<void> _switchSource(BuildContext context, WidgetRef ref, MediaSourceType current) async {
    final next = current == .camera ? MediaSourceType.screen : MediaSourceType.camera;
    String? desktopId;
    if (next == .screen && ref.read(platformServiceProvider).supportsDesktopPicker) {
      final picked = await DesktopSourceDialog.show(context);
      if (picked == null || !context.mounted) return;
      desktopId = picked.id;
    }
    await ref.read(sessionProvider.notifier).changeSource(next, desktopSourceId: desktopId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final config = ref.watch(streamConfigProvider);
    final platform = ref.watch(platformServiceProvider);
    final shortcuts = ref.watch(shortcutProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final isCamera = config.sourceType == .camera;
    final showLabels = !context.isCompact || MediaQuery.sizeOf(context).width >= 480;
    final muteLabel = session.isMicMuted ? 'Unmute' : 'Mute';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: .circular(20),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Material(
            type: .transparency,
            child: Padding(
              padding: const .symmetric(horizontal: 12, vertical: 10),
              child: Wrap(
                spacing: showLabels ? 8 : 6,
                runSpacing: 8,
                alignment: .center,
                crossAxisAlignment: .center,
                children: [
                  if (isCamera)
                    _DockActionButton(icon: Icons.cameraswitch_rounded, label: 'Flip', tooltip: 'Flip camera', showLabel: showLabels, onPressed: notifier.switchCamera),
                  _DockActionButton(
                    icon: isCamera ? Icons.screen_share_outlined : Icons.videocam_outlined,
                    label: isCamera ? 'Screen' : 'Camera',
                    tooltip: isCamera ? 'Switch to Screen' : 'Switch to Camera',
                    showLabel: showLabels,
                    onPressed: () => _switchSource(context, ref, config.sourceType),
                  ),
                  _DockActionButton(
                    icon: session.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: muteLabel,
                    tooltip: shortcuts.tooltipFor(muteLabel, .toggleMute),
                    showLabel: showLabels,
                    activeColor: session.isMicMuted ? AppColors.accentRed : null,
                    onPressed: notifier.toggleMicMute,
                  ),
                  if (isCamera && platform.isMobile)
                    _DockActionButton(
                      icon: session.isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      label: 'Torch',
                      tooltip: session.isTorchOn ? 'Turn Torch Off' : 'Turn Torch On',
                      showLabel: showLabels,
                      activeColor: session.isTorchOn ? AppColors.accentOrange : null,
                      onPressed: notifier.toggleTorch,
                    ),
                  _DockActionButton(
                    icon: Icons.content_paste_go_rounded,
                    label: 'Share Text',
                    tooltip: shortcuts.tooltipFor('Share Text', .openClipboard),
                    showLabel: showLabels,
                    onPressed: () => ClipboardSyncSheet.show(context),
                  ),
                  Tooltip(
                    message: shortcuts.tooltipFor('Stop', .disconnectStream),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentRed,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        shape: const StadiumBorder(),
                        padding: const .symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: notifier.disconnect,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Stop', style: TextStyle(fontWeight: .w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _DockActionButton({
  required final IconData icon,
  required final String label,
  required final String tooltip,
  required final bool showLabel,
  final Color? activeColor,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = activeColor;
    final fg = accent ?? colors.onSurface;
    final bg = accent != null ? accent.withValues(alpha: 0.16) : colors.surfaceContainer;
    final border = accent != null ? accent.withValues(alpha: 0.48) : colors.outlineVariant;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: .circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42, minWidth: 42),
          padding: .symmetric(horizontal: showLabel ? 12 : 10, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: .circular(13), border: Border.all(color: border)),
          child: Row(
            mainAxisSize: .min,
            spacing: showLabel ? 6 : 0,
            children: [
              Icon(icon, size: 18, color: fg),
              if (showLabel) Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: .w600)),
            ],
          ),
        ),
      ),
    );
  }
}
