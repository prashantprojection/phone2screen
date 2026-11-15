import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// Plain-English visual quick-start guide for Phone2Screen's three casting modes.
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
                  width: 34,
                  height: 34,
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
                    'Pick the setup that fits your devices — everything stays private on your local Wi-Fi.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const _ScenarioCard(
                    icon: Icons.devices_rounded,
                    accent: AppColors.primaryBlue,
                    title: 'Phone to PC',
                    subtitle: 'Stream between two Phone2Screen apps over the same Wi-Fi.',
                    steps: [
                      'Open Phone2Screen in Receive mode on your PC or TV.',
                      'Open Send mode on your phone and pick Camera or Screen.',
                      'Tap Connect next to your PC, or tap Scan QR Code.',
                    ],
                  ),
                  const _ScenarioCard(
                    icon: Icons.open_in_browser_rounded,
                    accent: AppColors.cyanAccent,
                    title: 'Watch in Any Browser',
                    subtitle: 'Watch on any PC, TV, or tablet browser — no viewer app needed.',
                    steps: [
                      'Open Send mode on the device you want to share.',
                      'Tap Cast to Web Browser to create a temporary local link.',
                      'Open the http:// link (or scan the QR code) in any browser on the same Wi-Fi.',
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
      padding: const .all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: .circular(14),
        border: Border.all(color: colors.outlineVariant),
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
      (Icons.wifi_rounded, 'Same Wi-Fi: Connect both devices to the same Wi-Fi (avoid Guest Wi-Fi).'),
      (
        Icons.wifi_tethering_rounded,
        'No Wi-Fi? Turn on your phone hotspot and connect your PC — it works offline with zero mobile data.',
      ),
      (Icons.content_paste_go_rounded, 'Share Text: Send links, notes, or passwords live between connected screens.'),
    ];

    return Container(
      padding: const .all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: .circular(14),
        border: Border.all(color: colors.outlineVariant),
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
