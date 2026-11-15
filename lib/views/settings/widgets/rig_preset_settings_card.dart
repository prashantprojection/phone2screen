import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/camera_rig_preset.dart';
import '../../../models/stream_config.dart';
import '../../../providers/preferences_provider.dart';
import '../../../providers/settings_provider.dart';

/// Settings card for saving current video/lens config as custom rig presets
/// and applying or deleting saved presets.
class const RigPresetSettingsCard({super.key}) extends ConsumerWidget {
  bool _matchesConfig(CameraRigPreset preset, StreamConfig config) =>
      config.resolution == preset.resolution &&
      config.frameRate == preset.frameRate &&
      config.videoBitrate == preset.videoBitrate &&
      config.cameraLens == preset.cameraLens;

  Future<void> _promptSavePreset(
    BuildContext context,
    WidgetRef ref,
    StreamConfig config,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SaveRigPresetDialog(),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final mbps = (config.videoBitrate / 1_000_000).toStringAsFixed(1);
    final preset = CameraRigPreset(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      subtitle: '${config.resolution.label} • ${config.frameRate} FPS • $mbps Mbps',
      resolution: config.resolution,
      frameRate: config.frameRate,
      videoBitrate: config.videoBitrate,
      cameraLens: config.cameraLens,
      isCustom: true,
    );
    await ref.read(customRigPresetsProvider.notifier).savePreset(preset);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Saved preset "$name"')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(streamConfigProvider);
    final customPresets = ref.watch(customRigPresetsProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mbps = (config.videoBitrate / 1_000_000).toStringAsFixed(1);
    final summary =
        '${config.resolution.label} • ${config.frameRate} FPS • $mbps Mbps • ${config.cameraLens.label}';

    return Card(
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 12),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.11),
                    borderRadius: .circular(10),
                  ),
                  child: Icon(Icons.bookmark_add_outlined, size: 18, color: colors.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text('Custom Rig Presets', style: theme.textTheme.bodyLarge),
                      Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    visualDensity: .compact,
                    padding: const .symmetric(horizontal: 14, vertical: 9),
                  ),
                  onPressed: () => _promptSavePreset(context, ref, config),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          if (customPresets.isEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const .symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'No custom presets yet. Adjust Video & Audio above or below and tap Save to reuse on Send.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ] else
            for (final preset in customPresets) ...[
              const Divider(height: 1, indent: 62),
              ListTile(
                leading: Icon(
                  _matchesConfig(preset, config) ? Icons.check_circle_rounded : Icons.tune_rounded,
                  size: 20,
                  color: _matchesConfig(preset, config) ? colors.primary : colors.onSurfaceVariant,
                ),
                title: Text(preset.name, maxLines: 1, overflow: .ellipsis),
                subtitle: Text(
                  '${preset.subtitle} • ${preset.cameraLens.label}',
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Delete preset',
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  onPressed: () => ref.read(customRigPresetsProvider.notifier).removePreset(preset.id),
                ),
                onTap: () {
                  ref.read(streamConfigProvider.notifier).applyPreset(preset);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text('Applied "${preset.name}"')));
                },
              ),
            ],
        ],
      ),
    );
  }
}

class const _SaveRigPresetDialog() extends StatefulWidget {
  @override
  State<_SaveRigPresetDialog> createState() => _SaveRigPresetDialogState();
}

class _SaveRigPresetDialogState extends State<_SaveRigPresetDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a preset name');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save Custom Rig Preset'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 28,
      textCapitalization: .words,
      decoration: InputDecoration(
        labelText: 'Preset Name',
        hintText: 'e.g. Desk Overhead 4K',
        errorText: _error,
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
        onPressed: _save,
        child: const Text('Save'),
      ),
    ],
  );
}
