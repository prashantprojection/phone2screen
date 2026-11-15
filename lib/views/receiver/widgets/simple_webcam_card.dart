import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/virtual_cam_provider.dart';

/// Zero-OBS Windows DirectShow virtual webcam card surfaced in the Receiver lobby.
class const SimpleWebcamCard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SimpleWebcamCard> createState() => _SimpleWebcamCardState();
}

class _SimpleWebcamCardState extends ConsumerState<SimpleWebcamCard> {
  static const List<String> _compatibleApps = [
    'Zoom',
    'Google Meet',
    'Teams',
    'Discord',
  ];

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

  @override
  Widget build(BuildContext context) {
    final vcam = ref.watch(nativeVirtualCamProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final registered = vcam.isSupported && vcam.isRegistered;
    final statusColor = !vcam.isSupported
        ? AppColors.primaryLight
        : (registered ? AppColors.accentGreen : AppColors.primaryLight);
    final statusIcon = !vcam.isSupported
        ? Icons.info_outline_rounded
        : (registered ? Icons.check_circle_rounded : Icons.bolt_rounded);
    final statusText = !vcam.isSupported
        ? 'Windows Desktop Feature'
        : (registered ? 'Phone2Screen Camera Ready' : '1-Click Setup — No Admin Needed');
    final subtitle = !vcam.isSupported
        ? 'DirectShow virtual webcam runs on Windows desktop. Use OBS (/obs) or Browser Companion on this device.'
        : (registered
              ? 'Select "${vcam.deviceName}" inside any desktop call or streaming app.'
              : 'Register "${vcam.deviceName}" once with zero OBS required.');

    final infoSection = Column(
      crossAxisAlignment: .start,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: .circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Icon(Icons.videocam_rounded, color: statusColor, size: 21),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 3,
                children: [
                  Text(
                    'Use as PC Webcam — No OBS Required',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: .center,
          children: [
            _pillChip(
              label: statusText,
              bg: statusColor.withValues(alpha: 0.14),
              border: statusColor.withValues(alpha: 0.42),
              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: .w700),
              icon: statusIcon,
              iconColor: statusColor,
            ),
            for (final app in _compatibleApps)
              _pillChip(
                label: app,
                bg: colors.surfaceContainerHighest.withValues(alpha: 0.65),
                border: colors.outlineVariant.withValues(alpha: 0.5),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: .w600,
                ),
                hPad: 9,
                vPad: 4,
              ),
          ],
        ),
      ],
    );

    final actionButton = vcam.isSupported
        ? Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: .center,
            children: [
              if (registered)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => unawaited(_toggleRegistration(true)),
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const .symmetric(horizontal: 14, vertical: 11),
                  ),
                  icon: const Icon(Icons.videocam_off_outlined, size: 18),
                  label: Text(_busy ? 'Disabling...' : 'Disable Webcam'),
                )
              else
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_toggleRegistration(false)),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const .symmetric(horizontal: 14, vertical: 11),
                  ),
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: Text(_busy ? 'Enabling...' : 'Enable Windows Webcam'),
                ),
              IconButton(
                tooltip: 'Refresh webcam status',
                onPressed: _busy ? null : () => unawaited(ref.read(nativeVirtualCamProvider.notifier).refresh()),
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          )
        : null;

    return Card(
      child: Padding(
        padding: const .all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (actionButton == null) return infoSection;
            if (constraints.maxWidth >= 700) {
              return Row(
                crossAxisAlignment: .center,
                spacing: 16,
                children: [Expanded(child: infoSection), actionButton],
              );
            }
            return Column(
              crossAxisAlignment: .start,
              spacing: 14,
              children: [infoSection, actionButton],
            );
          },
        ),
      ),
    );
  }
}

Widget _pillChip({
  required String label,
  required Color bg,
  required Color border,
  required TextStyle? style,
  IconData? icon,
  Color? iconColor,
  double hPad = 10,
  double vPad = 5,
}) => Container(
  padding: .symmetric(horizontal: hPad, vertical: vPad),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: .circular(999),
    border: Border.all(color: border),
  ),
  child: Row(
    mainAxisSize: .min,
    spacing: 5,
    children: [
      if (icon != null) Icon(icon, size: 14, color: iconColor),
      Flexible(child: Text(label, style: style)),
    ],
  ),
);
