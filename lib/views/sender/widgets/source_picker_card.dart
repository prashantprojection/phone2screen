import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../models/media_source_type.dart';
import '../../../models/stream_config.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/settings_provider.dart';
import 'desktop_source_dialog.dart';

typedef _QualityPreset = ({String label, StreamResolution res, int fps, int bps});

const List<_QualityPreset> _presets = [
  (label: '720p Saver', res: .p720, fps: 30, bps: StreamConstants.videoBitrate720p),
  (label: '1080p HD', res: .p1080, fps: 30, bps: StreamConstants.videoBitrate1080p),
  (label: '1080p Smooth', res: .p1080, fps: 60, bps: StreamConstants.videoBitrate1080p),
  (label: '4K Crisp', res: .p4k, fps: 60, bps: StreamConstants.videoBitrate4K),
];

/// Step 1 card for selecting camera/screen source, mic, and stream quality.
class const SourcePickerCard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SourcePickerCard> createState() => _SourcePickerCardState();
}

class _SourcePickerCardState extends ConsumerState<SourcePickerCard> {
  String? _selectedSourceName;

  Future<void> _pickDesktopSource() async {
    final picked = await DesktopSourceDialog.show(context);
    if (picked == null || !mounted) return;
    ref.read(streamConfigProvider.notifier)
      ..setSourceType(.screen)
      ..setDesktopSourceId(picked.id);
    setState(() => _selectedSourceName = picked.name);
  }

  Future<void> _onSourceChanged(MediaSourceType next) async {
    ref.read(streamConfigProvider.notifier).setSourceType(next);
    if (next == .screen && ref.read(platformServiceProvider).supportsDesktopPicker && ref.read(streamConfigProvider).desktopSourceId == null) {
      await _pickDesktopSource();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(streamConfigProvider);
    final notifier = ref.read(streamConfigProvider.notifier);
    final supportsDesktopPicker = ref.watch(platformServiceProvider).supportsDesktopPicker;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isCam = config.sourceType == .camera;

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
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.16), shape: .circle, border: Border.all(color: colors.primary.withValues(alpha: 0.45))),
                  child: Text('1', style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: .w800)),
                ),
                Text('What to Share', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                Expanded(child: _SourceOptionCard(icon: Icons.videocam_outlined, title: 'Camera', subtitle: 'Front or back', selected: isCam, onTap: () => _onSourceChanged(.camera))),
                Expanded(child: _SourceOptionCard(icon: Icons.screen_share_outlined, title: 'Screen', subtitle: 'Live display', selected: !isCam, onTap: () => _onSourceChanged(.screen))),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isCam) ...[
                  ChoiceChip(showCheckmark: false, avatar: const Icon(Icons.camera_rear_outlined, size: 17), label: const Text('Back'), selected: config.cameraLens == .back, onSelected: (_) => notifier.setCameraLens(.back)),
                  ChoiceChip(showCheckmark: false, avatar: const Icon(Icons.camera_front_outlined, size: 17), label: const Text('Front'), selected: config.cameraLens == .front, onSelected: (_) => notifier.setCameraLens(.front)),
                ],
                FilterChip(
                  showCheckmark: false,
                  avatar: Icon(config.enableAudio ? Icons.mic_rounded : Icons.mic_off_rounded, size: 17),
                  label: Text(config.enableAudio ? 'Mic On' : 'Mic Off'),
                  selected: config.enableAudio,
                  onSelected: notifier.setEnableAudio,
                ),
              ],
            ),
            if (!isCam && supportsDesktopPicker)
              Container(
                padding: const .symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: .circular(10), border: Border.all(color: colors.outlineVariant)),
                child: Row(
                  spacing: 10,
                  children: [
                    Icon(Icons.desktop_windows_rounded, size: 18, color: colors.primary),
                    Expanded(child: Text(_selectedSourceName ?? (config.desktopSourceId != null ? 'Source selected' : 'Default display'), maxLines: 1, overflow: .ellipsis)),
                    OutlinedButton(style: OutlinedButton.styleFrom(padding: const .symmetric(horizontal: 14, vertical: 8)), onPressed: _pickDesktopSource, child: const Text('Pick')),
                  ],
                ),
              ),
            Column(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Text('Quality', style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant, fontWeight: .w600)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _presets)
                      ChoiceChip(
                        showCheckmark: false,
                        visualDensity: .compact,
                        label: Text(p.label),
                        selected: config.resolution == p.res && config.frameRate == p.fps,
                        onSelected: (_) => notifier
                          ..setResolution(p.res)
                          ..setFrameRate(p.fps)
                          ..setBitrate(p.bps),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _SourceOptionCard({
  required final IconData icon,
  required final String title,
  required final String subtitle,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;

    return Material(
      color: selected ? accent.withValues(alpha: 0.13) : colors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: .circular(14), side: BorderSide(color: selected ? accent : colors.outlineVariant, width: selected ? 1.5 : 1)),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Container(
                    padding: const .all(8),
                    decoration: BoxDecoration(color: selected ? accent.withValues(alpha: 0.18) : colors.surface, borderRadius: .circular(10)),
                    child: Icon(icon, size: 20, color: selected ? accent : colors.onSurfaceVariant),
                  ),
                  Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: selected ? accent : colors.outline),
                ],
              ),
              Text(title, maxLines: 1, overflow: .ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700, color: selected ? accent : colors.onSurface)),
              Text(subtitle, maxLines: 1, overflow: .ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
