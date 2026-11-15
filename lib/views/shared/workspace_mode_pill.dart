import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/settings_provider.dart';

/// Compact segmented pill toggling between `Simple` webcam and `Studio` mode.
class const WorkspaceModePill({
  super.key,
  final bool compact = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appSettingsProvider.select((s) => s.workspaceMode));
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget segment(WorkspaceMode target, IconData icon) {
      final selected = mode == target;
      final accent = target == .studio ? const Color(0xFF0891B2) : AppColors.primaryBlue;
      final fg = selected ? Colors.white : colors.onSurfaceVariant;
      return Tooltip(
        message: target.description,
        child: Semantics(
          button: true,
          selected: selected,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: .circular(999),
            ),
            child: Material(
              type: .transparency,
              child: InkWell(
                borderRadius: .circular(999),
                onTap: () => ref.read(appSettingsProvider.notifier).setWorkspaceMode(target),
                child: Padding(
                  padding: .symmetric(horizontal: compact ? 10 : 12, vertical: 5),
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 5,
                    children: [
                      Icon(icon, size: 14, color: fg),
                      Text(
                        target.label,
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
        ),
      );
    }

    return Container(
      padding: const .all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: .circular(999),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 2,
        children: [
          segment(.simple, Icons.videocam_rounded),
          segment(.studio, Icons.tune_rounded),
        ],
      ),
    );
  }
}
