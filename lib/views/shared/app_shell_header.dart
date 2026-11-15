import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../models/device_role.dart';
import '../../models/session_phase.dart';
import '../../providers/platform_provider.dart';
import '../../providers/session_provider.dart';

/// Top bar with brand mark, live status pill, RTT chip, role switcher, and settings.
class const AppShellHeader({super.key, required final VoidCallback onOpenSettings})
    extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final session = ref.watch(sessionProvider);
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 64,
          padding: const .symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              final showTitle = constraints.maxWidth >= 500;
              final isStreaming = session.phase == .streaming;
              return Row(
                spacing: 8,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: .circular(10)),
                    child: const Icon(Icons.cast_connected_rounded, color: Colors.white, size: 18),
                  ),
                  if (showTitle)
                    Text('Phone2Screen', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                  _PhasePill(phase: session.phase, showLabel: wide, latencyMs: isStreaming ? session.telemetry.latencyMs : null),
                  if (wide && isStreaming)
                    Container(
                      padding: const .symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: .circular(999)),
                      child: Text('${session.telemetry.latencyMs} ms', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: .w600)),
                    ),
                  const Spacer(),
                  SegmentedButton<DeviceRole>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: .compact,
                      tapTargetSize: .shrinkWrap,
                      padding: WidgetStatePropertyAll(.symmetric(horizontal: 10)),
                    ),
                    segments: const [
                      ButtonSegment(value: .receiver, label: Text('Receive')),
                      ButtonSegment(value: .sender, label: Text('Send')),
                    ],
                    selected: {activeRole},
                    onSelectionChanged: (s) => _onRoleSelected(context, ref, activeRole, s.first, session.phase),
                  ),
                  IconButton(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined), tooltip: 'Settings'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onRoleSelected(
    BuildContext context,
    WidgetRef ref,
    DeviceRole currentRole,
    DeviceRole nextRole,
    SessionPhase phase,
  ) async {
    if (nextRole == currentRole) return;
    if (phase == .streaming) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Switch device role?'),
          content: const Text('Switching roles will disconnect the active stream session.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Switch')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await ref.read(sessionProvider.notifier).disconnect();
    } else if (phase == .connecting || phase == .reconnecting) {
      await ref.read(sessionProvider.notifier).disconnect();
    }
    if (!context.mounted) return;
    ref.read(activeRoleProvider.notifier).setRole(nextRole);
  }
}

class const _PhasePill({
  required final SessionPhase phase,
  required final bool showLabel,
  final int? latencyMs,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      .streaming => AppColors.accentGreen,
      .hosting || .discovering => AppColors.primaryBlue,
      .connecting || .reconnecting => AppColors.accentOrange,
      .failed => AppColors.accentRed,
      .idle => AppColors.textSecondaryDark,
    };
    return Container(
      padding: .symmetric(horizontal: showLabel ? 10 : 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: .circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: .circle)),
          if (showLabel)
            Text(phase.label, style: TextStyle(color: color, fontSize: 12, fontWeight: .w600))
          else if (latencyMs != null)
            Text('${latencyMs}ms', style: TextStyle(color: color, fontSize: 11, fontWeight: .w600)),
        ],
      ),
    );
  }
}
