import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/obs_sync_provider.dart';
import '../../../providers/virtual_cam_provider.dart';
import 'studio_look_audio_section.dart';

/// Native DirectShow `Phone2Screen Camera` registration card inside [ObsVirtualCamSheet].
class const NativeVirtualCamSection({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<NativeVirtualCamSection> createState() =>
      _NativeVirtualCamSectionState();
}

class _NativeVirtualCamSectionState extends ConsumerState<NativeVirtualCamSection> {
  bool _busy = false;

  Future<void> _toggleRegistration(bool currentlyRegistered) async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(nativeVirtualCamProvider.notifier);
    final ok = currentlyRegistered ? await notifier.disable() : await notifier.enable();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              currentlyRegistered
                  ? 'Could not unregister Phone2Screen Camera.'
                  : 'Could not register p2s_vcam.dll. Ensure it is beside phone2screen.exe.',
            ),
          ),
        );
    }
  }

  Future<void> _refresh() async {
    await ref.read(nativeVirtualCamProvider.notifier).refresh();
    if (mounted) ref.invalidate(videoCaptureDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vcam = ref.watch(nativeVirtualCamProvider);

    return StudioSectionBox(
      colors: colors,
      children: [
        StudioSectionTitle(
          title: 'Phone2Screen Camera • DirectShow',
          subtitle: 'Zero-OBS virtual webcam for Zoom, Meet, Teams & Discord',
          trailing: IconButton(
            tooltip: 'Refresh virtual webcam',
            visualDensity: .compact,
            onPressed: _busy ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ),
        if (!vcam.isSupported)
          _infoBanner(
            colors,
            'Native DirectShow virtual camera requires Windows desktop. Use OBS Studio or /obs Clean Feed below.',
          )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(
                vcam.isRegistered ? Icons.check_circle_rounded : Icons.bolt_rounded,
                vcam.isRegistered
                    ? 'Phone2Screen Camera Ready'
                    : '1-Click Setup — No Admin Needed',
                vcam.isRegistered ? AppColors.accentGreen : AppColors.primaryLight,
              ),
              if (vcam.isRegistered)
                _pill(
                  vcam.isPaused
                      ? Icons.videocam_off_rounded
                      : (vcam.isStreaming ? Icons.sensors_rounded : Icons.pause_circle_outline_rounded),
                  vcam.isPaused
                      ? 'Privacy Slate'
                      : (vcam.isStreaming ? 'Live Feed' : 'Standby Slate'),
                  vcam.isPaused
                      ? AppColors.accentOrange
                      : (vcam.isStreaming ? AppColors.cyanAccent : colors.onSurfaceVariant),
                ),
            ],
          ),
          if (vcam.isRegistered)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_toggleRegistration(true)),
              icon: const Icon(Icons.videocam_off_outlined),
              label: Text(_busy ? 'Disabling...' : 'Disable Webcam'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_toggleRegistration(false)),
              icon: const Icon(Icons.videocam_rounded),
              label: Text(_busy ? 'Enabling...' : 'Enable Windows Webcam'),
            ),
          if (!vcam.dllFound && !vcam.isRegistered)
            Text(
              'Place p2s_vcam.dll next to phone2screen.exe to enable DirectShow output.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ],
    );
  }

  Widget _pill(IconData icon, String label, Color color) => Container(
    padding: const .symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: .circular(999),
      border: Border.all(color: color.withValues(alpha: 0.42)),
    ),
    child: Row(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        Icon(icon, size: 13, color: color),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: .w700),
          ),
        ),
      ],
    ),
  );

  Widget _infoBanner(ColorScheme colors, String text) => Container(
    padding: const .all(10),
    decoration: BoxDecoration(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.65),
      borderRadius: .circular(12),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Padding(
          padding: const .only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurfaceVariant),
        ),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
