import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/camera_rig_preset.dart';
import '../../../models/stream_config.dart';
import '../../../providers/preferences_provider.dart';
import '../../../providers/settings_provider.dart';

/// Horizontal scrollable 1-tap streamer rig preset strip backed by
/// [allRigPresetsProvider] (built-in rigs + saved custom presets).
class const RigPresetsStrip({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RigPresetsStrip> createState() => _RigPresetsStripState();
}

class _RigPresetsStripState extends ConsumerState<RigPresetsStrip> {
  String? _selectedPresetId;

  bool _matchesConfig(CameraRigPreset preset, StreamConfig config) =>
      config.resolution == preset.resolution &&
      config.frameRate == preset.frameRate &&
      config.videoBitrate == preset.videoBitrate &&
      (config.sourceType != .camera || config.cameraLens == preset.cameraLens);

  String? _resolveActiveId(List<CameraRigPreset> presets, StreamConfig config) {
    if (_selectedPresetId != null) {
      for (final p in presets) {
        if (p.id == _selectedPresetId && _matchesConfig(p, config)) {
          return p.id;
        }
      }
    }
    for (final p in presets) {
      if (_matchesConfig(p, config)) return p.id;
    }
    return null;
  }

  IconData _iconForPreset(CameraRigPreset preset) {
    if (preset.isCustom) return Icons.tune_rounded;
    return switch (preset.id) {
      'facecam_1080p60' => Icons.face_rounded,
      'overhead_4k30' => Icons.camera_alt_outlined,
      'usb_ultra' => Icons.usb_rounded,
      'vertical_cam' => Icons.stay_current_portrait_rounded,
      'eco_720p30' => Icons.eco_outlined,
      _ => Icons.videocam_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(allRigPresetsProvider);
    final config = ref.watch(streamConfigProvider);
    final activeId = _resolveActiveId(presets, config);

    return SingleChildScrollView(
      scrollDirection: .horizontal,
      child: Row(
        spacing: 8,
        children: [
          for (final preset in presets)
            Tooltip(
              message: preset.subtitle.isEmpty ? preset.name : preset.subtitle,
              child: ChoiceChip(
                showCheckmark: false,
                visualDensity: .compact,
                avatar: Icon(_iconForPreset(preset), size: 16),
                label: Text(preset.name),
                selected: preset.id == activeId,
                onSelected: (_) {
                  setState(() => _selectedPresetId = preset.id);
                  ref.read(streamConfigProvider.notifier).applyPreset(preset);
                },
              ),
            ),
        ],
      ),
    );
  }
}
