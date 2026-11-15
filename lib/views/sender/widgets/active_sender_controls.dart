import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/media_source_type.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';
import 'desktop_source_dialog.dart';

/// Live broadcast control dock for camera, audio, source, clipboard, and stop.
class const ActiveSenderControls({super.key}) extends ConsumerWidget {
  Future<void> _switchSource(
    BuildContext context,
    WidgetRef ref,
    MediaSourceType current,
  ) async {
    final next = current == .camera ? MediaSourceType.screen : MediaSourceType.camera;
    String? desktopId;
    if (next == .screen &&
        ref.read(platformServiceProvider).supportsDesktopPicker) {
      final picked = await DesktopSourceDialog.show(context);
      if (picked == null || !context.mounted) return;
      desktopId = picked.id;
    }
    await ref
        .read(sessionProvider.notifier)
        .changeSource(next, desktopSourceId: desktopId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final config = ref.watch(streamConfigProvider);
    final platform = ref.watch(platformServiceProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final isCamera = config.sourceType == .camera;

    return Card(
      child: Padding(
        padding: const .all(14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: .center,
          crossAxisAlignment: .center,
          children: [
            if (isCamera)
              OutlinedButton.icon(
                onPressed: notifier.switchCamera,
                icon: const Icon(Icons.cameraswitch_rounded, size: 18),
                label: const Text('Flip'),
              ),
            OutlinedButton.icon(
              onPressed: () => _switchSource(context, ref, config.sourceType),
              icon: Icon(
                isCamera ? Icons.screen_share_outlined : Icons.videocam_outlined,
                size: 18,
              ),
              label: Text(isCamera ? 'Screen' : 'Camera'),
            ),
            OutlinedButton.icon(
              onPressed: notifier.toggleMicMute,
              icon: Icon(
                session.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 18,
              ),
              label: Text(session.isMicMuted ? 'Unmute' : 'Mute'),
            ),
            if (isCamera && platform.isMobile)
              OutlinedButton.icon(
                onPressed: notifier.toggleTorch,
                icon: Icon(
                  session.isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  size: 18,
                ),
                label: const Text('Torch'),
              ),
            OutlinedButton.icon(
              onPressed: () => ClipboardSyncSheet.show(context),
              icon: const Icon(Icons.content_paste_go_rounded, size: 18),
              label: const Text('Share Text'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                foregroundColor: Colors.white,
              ),
              onPressed: notifier.disconnect,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}
