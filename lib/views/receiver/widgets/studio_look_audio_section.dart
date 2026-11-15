import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/obs_sync_provider.dart';
import '../../../providers/settings_provider.dart';

/// Studio Look presets, Soft Vignette, Mic DSP, Audio Output routing & Lip-Sync section.
class const StudioLookAudioSection({
  super.key,
  required final bool isPrimary,
  required final ViewerDisplayConfig display,
  required final void Function(ViewerDisplayConfig Function(ViewerDisplayConfig)) onSecondaryDisplayUpdate,
  final ValueChanged<bool>? onSendVoiceMode,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final displayNotifier = ref.read(viewerDisplayProvider.notifier);
    final audioCfg = ref.watch(audioStudioProvider);
    final audioNotifier = ref.read(audioStudioProvider.notifier);
    final outputsAsync = ref.watch(audioOutputsProvider);
    final outputs = outputsAsync.value ?? const <AudioEndpointDevice>[];
    final hasVirtualCable = outputs.any((d) => d.isVirtualCable);

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        StudioSectionBox(
          colors: colors,
          children: [
            const StudioSectionTitle(
              title: '1-Tap Studio Look Presets',
              subtitle: 'Instant GPU color grading & soft vignette',
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in StudioLookPreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: display.lookPreset == preset,
                    showCheckmark: false,
                    onSelected: (_) => isPrimary
                        ? displayNotifier.setLookPreset(preset)
                        : onSecondaryDisplayUpdate((c) => c.copyWith(lookPreset: preset)),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.vignette_rounded, size: 15),
                  label: const Text('Soft Vignette'),
                  selected: display.vignette,
                  onSelected: (v) => isPrimary
                      ? displayNotifier.toggleVignette()
                      : onSecondaryDisplayUpdate((c) => c.copyWith(vignette: v)),
                ),
              ],
            ),
          ],
        ),
        StudioSectionBox(
          colors: colors,
          children: [
            StudioSectionTitle(
              title: 'Studio Audio, Virtual Mic & Lip-Sync',
              subtitle: 'Mic processing, output routing, boost & delay',
              trailing: hasVirtualCable ? const _VirtualMicBadge() : null,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: .center,
              children: [
                Text('Mic Mode', style: theme.textTheme.labelMedium),
                for (final mode in MicProcessingMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: audioCfg.micMode == mode,
                    showCheckmark: false,
                    onSelected: (_) {
                      unawaited(audioNotifier.setMicMode(mode));
                      onSendVoiceMode?.call(mode == .voiceClean);
                    },
                  ),
              ],
            ),
            _buildOutputPicker(theme, colors, ref, outputsAsync, audioCfg, audioNotifier),
            StudioSliderRow(label: 'Audio Boost', valueText: '${(audioCfg.gain * 100).round()}%', value: audioCfg.gain.clamp(0.0, 2.0).toDouble(), min: 0.0, max: 2.0, divisions: 20, onChanged: (v) => unawaited(audioNotifier.setGain(v))),
            StudioSliderRow(label: 'Lip-Sync Offset', valueText: '${audioCfg.lipSyncDelayMs} ms', value: audioCfg.lipSyncDelayMs.clamp(0, 500).toDouble(), min: 0.0, max: 500.0, divisions: 25, onChanged: (v) => unawaited(audioNotifier.setLipSyncDelayMs(v.round()))),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputPicker(
    ThemeData theme,
    ColorScheme colors,
    WidgetRef ref,
    AsyncValue<List<AudioEndpointDevice>> outputsAsync,
    AudioStudioConfig audioCfg,
    AudioStudioNotifier audioNotifier,
  ) {
    final content = outputsAsync.when(
      loading: () => Text('Scanning audio output endpoints...', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      error: (_, _) => Text('Could not enumerate audio outputs.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accentRed)),
      data: (devices) {
        if (devices.isEmpty) {
          return Text('Audio Output: System Default', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant));
        }
        final selectedId = devices.any((d) => d.id == audioCfg.outputDeviceId)
            ? audioCfg.outputDeviceId!
            : (devices.any((d) => d.id == 'default') ? 'default' : devices.first.id);
        return InputDecorator(
          decoration: const InputDecoration(labelText: 'Audio Output', contentPadding: .symmetric(horizontal: 10, vertical: 6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: selectedId,
              items: [
                for (final d in devices)
                  DropdownMenuItem<String>(value: d.id, child: Text(d.isVirtualCable ? '${d.label} • Virtual Mic Ready' : d.label, overflow: .ellipsis)),
              ],
              onChanged: (id) { if (id != null) unawaited(audioNotifier.setOutputDevice(id == 'default' ? null : id)); },
            ),
          ),
        );
      },
    );
    return Row(
      spacing: 6,
      children: [
        Expanded(child: content),
        IconButton(tooltip: 'Refresh audio outputs', onPressed: () => ref.invalidate(audioOutputsProvider), icon: const Icon(Icons.refresh_rounded, size: 18)),
      ],
    );
  }
}

class const _VirtualMicBadge() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const .symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.14), borderRadius: .circular(999), border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.45))),
    child: const Row(
      mainAxisSize: .min,
      spacing: 4,
      children: [
        Icon(Icons.cable_rounded, size: 13, color: AppColors.accentGreen),
        Text('Virtual Mic Ready', style: TextStyle(color: AppColors.accentGreen, fontSize: 11, fontWeight: .w700)),
      ],
    ),
  );
}

/// Shared card container used across studio inspector panels.
class const StudioSectionBox({super.key, required final ColorScheme colors, required final List<Widget> children}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
    color: colors.surfaceContainer.withValues(alpha: 0.55),
    shape: RoundedRectangleBorder(
      borderRadius: .circular(16),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.55)),
    ),
    clipBehavior: .antiAlias,
    child: Padding(
      padding: const .all(12),
      child: Column(crossAxisAlignment: .stretch, spacing: 8, children: children),
    ),
  );
}

/// Shared header block with title, subtitle, and optional trailing action/badge.
class const StudioSectionTitle({super.key, required final String title, required final String subtitle, final Widget? trailing}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      spacing: 2,
      children: [
        if (trailing case final trailingWidget?)
          Row(spacing: 8, children: [Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700))), trailingWidget])
        else
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Shared compact labeled slider row with tabular numeric readout.
class const StudioSliderRow({super.key, required final String label, required final String valueText, required final double value, required final double min, required final double max, final int? divisions, final ValueChanged<double>? onChanged, final ValueChanged<double>? onChangeEnd}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      children: [
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: .w600)),
            Text(valueText, style: theme.textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        SizedBox(height: 28, child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onChangeEnd)),
      ],
    );
  }
}
