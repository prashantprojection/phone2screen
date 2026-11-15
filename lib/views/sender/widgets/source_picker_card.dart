import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/media_source_type.dart';
import '../../../models/stream_config.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/settings_provider.dart';
import 'desktop_source_dialog.dart';

typedef _QualityPreset = ({String label, StreamResolution res, int fps, int bps});

const List<_QualityPreset> _presets = [
  (label: '720p30', res: .p720, fps: 30, bps: StreamConstants.videoBitrate720p),
  (label: '1080p30', res: .p1080, fps: 30, bps: StreamConstants.videoBitrate1080p),
  (label: '1080p60', res: .p1080, fps: 60, bps: StreamConstants.videoBitrate1080p),
  (label: '4K60', res: .p4k, fps: 60, bps: StreamConstants.videoBitrate4K),
];

/// Sender media source, camera lens, audio, and quick resolution/FPS selector.
class const SourcePickerCard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SourcePickerCard> createState() => _SourcePickerCardState();
}

class _SourcePickerCardState extends ConsumerState<SourcePickerCard> {
  String? _selectedSourceName;

  Future<void> _pickDesktopSource() async {
    final picked = await DesktopSourceDialog.show(context);
    if (picked == null || !mounted) return;
    final notifier = ref.read(streamConfigProvider.notifier);
    notifier.setSourceType(.screen);
    notifier.setDesktopSourceId(picked.id);
    setState(() => _selectedSourceName = picked.name);
  }

  Future<void> _onSourceChanged(MediaSourceType next) async {
    final notifier = ref.read(streamConfigProvider.notifier);
    notifier.setSourceType(next);
    if (next == .screen &&
        ref.read(platformServiceProvider).supportsDesktopPicker &&
        ref.read(streamConfigProvider).desktopSourceId == null) {
      await _pickDesktopSource();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(streamConfigProvider);
    final notifier = ref.read(streamConfigProvider.notifier);
    final supportsDesktopPicker = ref.watch(platformServiceProvider).supportsDesktopPicker;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const .all(18),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Row(
              spacing: 10,
              children: [
                const Icon(Icons.tune_rounded, color: AppColors.primaryLight),
                Text('Broadcast Source', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
              ],
            ),
            SegmentedButton<MediaSourceType>(
              segments: const [
                ButtonSegment(value: .camera, icon: Icon(Icons.videocam_outlined), label: Text('Camera')),
                ButtonSegment(value: .screen, icon: Icon(Icons.screen_share_outlined), label: Text('Screen')),
              ],
              selected: {config.sourceType},
              onSelectionChanged: (s) => _onSourceChanged(s.first),
            ),
            if (config.sourceType == .camera)
              SegmentedButton<CameraLens>(
                segments: const [
                  ButtonSegment(value: .back, icon: Icon(Icons.camera_rear_outlined), label: Text('Back Lens')),
                  ButtonSegment(value: .front, icon: Icon(Icons.camera_front_outlined), label: Text('Front Lens')),
                ],
                selected: {config.cameraLens},
                onSelectionChanged: (s) => notifier.setCameraLens(s.first),
              )
            else if (supportsDesktopPicker)
              Container(
                padding: const .symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: .circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    const Icon(Icons.desktop_windows_rounded, size: 18),
                    Expanded(
                      child: Text(
                        _selectedSourceName ?? (config.desktopSourceId != null ? 'Source selected' : 'Default display'),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                    OutlinedButton(onPressed: _pickDesktopSource, child: const Text('Pick')),
                  ],
                ),
              ),
            SwitchListTile(
              contentPadding: .zero,
              title: const Text('Include Audio'),
              subtitle: const Text('Capture microphone audio with stream'),
              value: config.enableAudio,
              onChanged: notifier.setEnableAudio,
            ),
            Text('Quality Preset', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: config.resolution == p.res && config.frameRate == p.fps,
                    onSelected: (_) {
                      notifier.setResolution(p.res);
                      notifier.setFrameRate(p.fps);
                      notifier.setBitrate(p.bps);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
