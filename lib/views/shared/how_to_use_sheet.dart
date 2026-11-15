import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// Plain-English visual quick-start guide for Phone2Screen casting & OBS studio workflows.
class const HowToUseSheet({super.key}) extends StatelessWidget {
  /// Opens the guide as a bottom sheet on phones or a centered dialog on wide screens.
  static Future<void> show(BuildContext context) {
    if (context.isCompact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const HowToUseSheet(),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: .antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 740),
          child: const HowToUseSheet(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * (context.isCompact ? 0.86 : 0.85);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: .min,
        children: [
          Padding(
            padding: const .fromLTRB(20, 14, 12, 12),
            child: Row(
              spacing: 10,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.14),
                    borderRadius: .circular(10),
                  ),
                  child: const Icon(Icons.help_outline_rounded, color: AppColors.primaryLight, size: 19),
                ),
                Expanded(
                  child: Text('How to Use Phone2Screen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const .fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 12,
                children: [
                  Text(
                    'Pick the setup that fits your rig — everything stays private on your local Wi-Fi or USB link.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const _ScenarioCard(
                    icon: Icons.videocam_outlined,
                    accent: AppColors.primaryLight,
                    title: 'Use Phone as PC Webcam (No OBS)',
                    subtitle: 'Simple Mode — DirectShow webcam for Zoom, Google Meet, Teams & Discord.',
                    steps: [
                      'Stay in Simple mode on PC Receive and click Enable Windows Webcam (no admin required).',
                      'Connect your phone over Wi-Fi or USB, then select "Phone2Screen Camera" inside your call app.',
                      'Press P (or tap Pause) anytime to freeze video with a privacy slate.',
                    ],
                  ),
                  const _ScenarioCard(
                    icon: Icons.devices_rounded,
                    accent: AppColors.primaryBlue,
                    title: 'Phone to PC',
                    subtitle: 'Switch to Studio mode for OBS Window Capture, tally & multi-cam.',
                    steps: [
                      'Open Receive mode on PC (switch to Studio to click + Open Camera Window for extra phones).',
                      'Open Send mode on your phone, pick a Rig Preset, and tap Connect or Scan QR Code.',
                      'Press F for Fullscreen and tap (or press O) to hide controls for clean OBS Window Capture.',
                    ],
                  ),
                  const _ScenarioCard(
                    icon: Icons.open_in_browser_rounded,
                    accent: AppColors.cyanAccent,
                    title: 'Watch in Any Browser',
                    subtitle: 'Feed OBS Studio Browser Source (/obs) or watch in any browser on your LAN.',
                    steps: [
                      'Open Send mode on the device you want to share and tap Cast to Web Browser.',
                      'Copy the /obs link into an OBS Browser Source for a zero-UI auto-reconnecting feed.',
                      'Or open the standard http:// link (or scan the QR) in any browser with remote controls.',
                    ],
                  ),
                  const _ScenarioCard(
                    icon: Icons.videocam_rounded,
                    accent: AppColors.accentGreen,
                    title: 'Phone Browser to PC',
                    subtitle: 'Stream your phone camera straight to your PC without a phone app.',
                    steps: [
                      'Keep your PC in Receive mode and open the https:// link on your phone.',
                      'If the browser warns about a private connection, tap Advanced then Proceed.',
                      'Allow camera access and tap Stream Camera to start casting live.',
                    ],
                  ),
                  const _QuickTipsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _ScenarioCard({
  required final IconData icon,
  required final Color accent,
  required final String title,
  required final String subtitle,
  required final List<String> steps,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const .all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: .circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: .circular(10)),
                child: Icon(icon, color: accent, size: 19),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              for (var i = 0; i < steps.length; i++)
                Row(
                  crossAxisAlignment: .start,
                  spacing: 8,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), shape: .circle),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(color: accent, fontWeight: .w700),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const .only(top: 1),
                        child: Text(steps[i], style: theme.textTheme.bodySmall),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class const _QuickTipsCard() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    const tips = [
      (
        Icons.usb_rounded,
        'USB Zero-Lag: Enable phone USB Tethering (PC prioritizes USB NIC automatically) or run adb reverse tcp:8080 tcp:8080 and tap USB / ADB with the USB Ultra 20 Mbps preset.',
      ),
      (
        Icons.videocam_off_rounded,
        'Privacy Pause (P): Press P or tap Pause anytime on Receiver or Sender to freeze video on a dark privacy slate (including Phone2Screen Camera).',
      ),
      (
        Icons.live_tv_rounded,
        'Simple vs Studio Mode: Use Simple for 1-click Windows Webcam (Zoom/Meet/Teams/Discord), or switch to Studio for /obs, OBS WebSocket tally & up to 4 phones.',
      ),
      (
        Icons.fullscreen_rounded,
        'Studio Controls: Press V for Camera Rig & Color grading, F for Fullscreen, O to hide controls (Esc exits), or customize keys in Settings.',
      ),
    ];

    return Container(
      padding: const .all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.65),
        borderRadius: .circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accentOrange, size: 18),
              Text('Quick Tips', style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
            ],
          ),
          for (final (icon, text) in tips)
            Row(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Padding(
                  padding: const .only(top: 2),
                  child: Icon(icon, size: 15, color: colors.onSurfaceVariant),
                ),
                Expanded(
                  child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
