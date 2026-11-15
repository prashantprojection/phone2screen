import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/viewer_display_config.dart';
import '../../../providers/settings_provider.dart';
import 'studio_look_audio_section.dart';

/// Portrait background blur, face fill-light, and overhead desk keystone controls.
class const CreatorStageFxSection({
  super.key,
  required final bool isPrimary,
  required final ViewerDisplayConfig display,
  required final void Function(ViewerDisplayConfig Function(ViewerDisplayConfig))
      onSecondaryDisplayUpdate,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final displayNotifier = ref.read(viewerDisplayProvider.notifier);
    final hasKeystone = display.deskCamMode ||
        display.keystoneVertical != 0.0 ||
        display.keystoneHorizontal != 0.0;

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        StudioSectionBox(
          colors: colors,
          children: [
            const StudioSectionTitle(
              title: 'Portrait Blur & Face Fill-Light',
              subtitle: 'GPU background bokeh & soft face fill illumination',
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final mode in PortraitBokehMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: display.bokehMode == mode,
                    showCheckmark: false,
                    onSelected: (_) => isPrimary
                        ? displayNotifier.setBokehMode(mode)
                        : onSecondaryDisplayUpdate(
                            (c) => c.copyWith(bokehMode: mode),
                          ),
                  ),
              ],
            ),
            StudioSliderRow(
              label: 'Face Fill-Light',
              valueText: '${(display.faceFillLight * 100).round()}%',
              value: display.faceFillLight.clamp(0.0, 1.0).toDouble(),
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => isPrimary
                  ? displayNotifier.setFaceFillLight(v)
                  : onSecondaryDisplayUpdate(
                      (c) => c.copyWith(faceFillLight: v),
                    ),
            ),
          ],
        ),
        StudioSectionBox(
          colors: colors,
          children: [
            StudioSectionTitle(
              title: 'Overhead Desk & Doc Cam',
              subtitle: '180° tabletop flip & 3D perspective keystone',
              trailing: hasKeystone
                  ? TextButton(
                      onPressed: () => isPrimary
                          ? (displayNotifier
                              ..setDeskCamMode(false)
                              ..setKeystoneVertical(0.0)
                              ..setKeystoneHorizontal(0.0))
                          : onSecondaryDisplayUpdate(
                              (c) => c.copyWith(
                                deskCamMode: false,
                                keystoneVertical: 0.0,
                                keystoneHorizontal: 0.0,
                              ),
                            ),
                      style: TextButton.styleFrom(
                        padding: const .symmetric(horizontal: 8, vertical: 4),
                      ),
                      child: const Text('Reset Keystone'),
                    )
                  : null,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.flip_camera_android_rounded, size: 15),
                  label: const Text('Desk Cam 180°'),
                  selected: display.deskCamMode,
                  onSelected: (v) => isPrimary
                      ? displayNotifier.setDeskCamMode(v)
                      : onSecondaryDisplayUpdate(
                          (c) => c.copyWith(deskCamMode: v),
                        ),
                ),
              ],
            ),
            StudioSliderRow(
              label: 'Vertical Keystone',
              valueText: '${(display.keystoneVertical * 100).round()}°',
              value: display.keystoneVertical.clamp(-0.35, 0.35).toDouble(),
              min: -0.35,
              max: 0.35,
              divisions: 14,
              onChanged: (v) => isPrimary
                  ? displayNotifier.setKeystoneVertical(v)
                  : onSecondaryDisplayUpdate(
                      (c) => c.copyWith(keystoneVertical: v),
                    ),
            ),
            StudioSliderRow(
              label: 'Horizontal Keystone',
              valueText: '${(display.keystoneHorizontal * 100).round()}°',
              value: display.keystoneHorizontal.clamp(-0.35, 0.35).toDouble(),
              min: -0.35,
              max: 0.35,
              divisions: 14,
              onChanged: (v) => isPrimary
                  ? displayNotifier.setKeystoneHorizontal(v)
                  : onSecondaryDisplayUpdate(
                      (c) => c.copyWith(keystoneHorizontal: v),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
