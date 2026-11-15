import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';

/// Dismissible alert banner for connection, signaling, or media errors.
class const ErrorBanner({
  super.key,
  required final String message,
  final VoidCallback? onRetry,
  final VoidCallback? onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = AppColors.accentRed;

    return Container(
      padding: const .symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: .circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        spacing: 10,
        children: [
          const Icon(Icons.error_outline_rounded, color: accent, size: 20),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Dismiss',
              visualDensity: .compact,
            ),
        ],
      ),
    );
  }
}
