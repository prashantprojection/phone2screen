import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../models/device_role.dart';
import '../../models/session_phase.dart';
import '../../providers/platform_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shortcut_provider.dart';
import 'how_to_use_sheet.dart';

/// Top bar with brand mark, live status pill, role switcher, guide, and settings.
class const AppShellHeader({super.key, required final VoidCallback onOpenSettings})
    extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final session = ref.watch(sessionProvider);
    final shortcuts = ref.watch(shortcutProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canFullscreen =
        activeRole == .receiver &&
        (session.phase == .streaming ||
            session.phase == .connecting ||
            session.phase == .reconnecting);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final centered = constraints.maxWidth >= 720;
            final wide = constraints.maxWidth >= 680;
            final compact = constraints.maxWidth < 460;
            final showTitle = constraints.maxWidth >= 500;
            final iconStyle = compact
                ? IconButton.styleFrom(
                    padding: const .all(6),
                    minimumSize: const Size(34, 34),
                    tapTargetSize: .shrinkWrap,
                  )
                : null;

            final brand = Row(
              mainAxisSize: .min,
              spacing: wide ? 10 : (compact ? 6 : 8),
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: .circular(9),
                  ),
                  child: const Icon(Icons.cast_connected_rounded, color: Colors.white, size: 17),
                ),
                if (showTitle)
                  Text(
                    'Phone2Screen',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: .w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                _PhasePill(phase: session.phase, showLabel: wide),
              ],
            );

            final switcher = _RolePillSwitcher(
              activeRole: activeRole,
              showIcons: wide,
              onSelected: (next) => _onRoleSelected(context, ref, activeRole, next, session.phase),
            );

            final actions = Row(
              mainAxisSize: .min,
              spacing: compact ? 2 : 4,
              children: [
                if (canFullscreen)
                  IconButton(
                    onPressed: () => ref.read(viewerDisplayProvider.notifier).toggleFullscreen(),
                    icon: const Icon(Icons.fullscreen_rounded),
                    tooltip: shortcuts.tooltipFor('Fullscreen', .toggleFullscreen),
                    style: iconStyle,
                    visualDensity: .compact,
                  ),
                IconButton(
                  onPressed: () => HowToUseSheet.show(context),
                  icon: const Icon(Icons.help_outline_rounded),
                  tooltip: shortcuts.tooltipFor('How to Use', .openGuide),
                  style: iconStyle,
                  visualDensity: .compact,
                ),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  style: iconStyle,
                  visualDensity: .compact,
                ),
              ],
            );

            return Container(
              height: 56,
              padding: .symmetric(horizontal: wide ? 16 : 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
                ),
              ),
              child: centered
                  ? Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: .scaleDown,
                              alignment: Alignment.centerLeft,
                              child: brand,
                            ),
                          ),
                        ),
                        switcher,
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      spacing: compact ? 4 : 6,
                      children: [
                        brand,
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: .scaleDown,
                              alignment: Alignment.centerRight,
                              child: switcher,
                            ),
                          ),
                        ),
                        actions,
                      ],
                    ),
            );
          },
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

class const _RolePillSwitcher({
  required final DeviceRole activeRole,
  required final bool showIcons,
  required final ValueChanged<DeviceRole> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget segment(DeviceRole role, String label, IconData icon) {
      final selected = activeRole == role;
      final fg = selected ? Colors.white : colors.onSurfaceVariant;
      return Semantics(
        button: true,
        selected: selected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: .circular(999),
          ),
          child: Material(
            type: .transparency,
            child: InkWell(
              borderRadius: .circular(999),
              onTap: () => onSelected(role),
              child: Padding(
                padding: .symmetric(horizontal: showIcons ? 14 : 12, vertical: 6),
                child: Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    if (showIcons) Icon(icon, size: 15, color: fg),
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: selected ? .w700 : .w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const .all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: .circular(999),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 2,
        children: [
          segment(.receiver, 'Receive', Icons.tv_rounded),
          segment(.sender, 'Send', Icons.videocam_rounded),
        ],
      ),
    );
  }
}

class const _PhasePill({
  required final SessionPhase phase,
  required final bool showLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (label, color) = switch (phase) {
      .streaming => ('Live', AppColors.accentGreen),
      .hosting || .discovering => ('Ready', AppColors.primaryBlue),
      .connecting => ('Connecting', AppColors.accentOrange),
      .reconnecting => ('Reconnecting', AppColors.accentOrange),
      .failed => ('Issue', AppColors.accentRed),
      .idle => ('Ready', muted),
    };
    return Tooltip(
      message: label,
      child: Container(
        padding: .symmetric(horizontal: showLabel ? 10 : 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: .circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: .circle)),
            if (showLabel)
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: .w600)),
          ],
        ),
      ),
    );
  }
}
