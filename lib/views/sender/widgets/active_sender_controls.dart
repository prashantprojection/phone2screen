import 'dart:ui' show ImageFilter;

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
    final isCamera = config.sourceType == .camera;
    final showLabels = !context.isCompact || MediaQuery.sizeOf(context).width >= 480;
    final muteLabel = session.isMicMuted ? 'Unmute' : 'Mute';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: .circular(999),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.34), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: .circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF14161A).withValues(alpha: 0.84),
                  borderRadius: .circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Material(
                  type: .transparency,
                  child: Padding(
                    padding: const .symmetric(horizontal: 10, vertical: 8),
                    child: Wrap(
                      spacing: showLabels ? 6 : 5,
                      runSpacing: 6,
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
                              minimumSize: const Size(0, 40),
                              shape: const StadiumBorder(),
                              padding: const .symmetric(horizontal: 16, vertical: 9),
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
    final accent = activeColor;
    final fg = accent ?? Colors.white;
    final bg = accent != null ? accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.10);
    final border = accent != null ? accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.14);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: .circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
          padding: .symmetric(horizontal: showLabel ? 13 : 10, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: .circular(999), border: Border.all(color: border)),
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
