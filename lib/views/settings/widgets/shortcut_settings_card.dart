import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/shortcut_config.dart';
import '../../../providers/shortcut_provider.dart';

/// Settings card for toggling global shortcuts and remapping action keys.
class const ShortcutSettingsCard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(shortcutProvider);
    final notifier = ref.read(shortcutProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SwitchListTile(
            title: const Text('Enable Keyboard Shortcuts'),
            subtitle: const Text('Press Esc anytime to exit fullscreen'),
            value: shortcuts.enabled,
            onChanged: notifier.setEnabled,
          ),
          const Divider(height: 1),
          Padding(
            padding: const .fromLTRB(16, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Shortcut Keys',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: notifier.resetDefaults,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset Defaults'),
                ),
              ],
            ),
          ),
          for (final action in ShortcutAction.values)
            _ShortcutBindingRow(
              action: action,
              binding: shortcuts.bindingFor(action),
              enabled: shortcuts.enabled,
              onEdit: () => _openRecordDialog(
                context,
                ref,
                action,
                shortcuts.bindingFor(action),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _openRecordDialog(
    BuildContext context,
    WidgetRef ref,
    ShortcutAction action,
    ShortcutBinding currentBinding,
  ) async {
    // Pause global shortcut dispatch around the dialog without mutating state
    // inside widget lifecycle hooks like initState or dispose.
    final recordingNotifier = ref.read(isRecordingShortcutProvider.notifier);
    final shortcutNotifier = ref.read(shortcutProvider.notifier);
    recordingNotifier.setRecording(true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _RecordShortcutDialog(
          action: action,
          currentBinding: currentBinding,
          notifier: shortcutNotifier,
        ),
      );
    } finally {
      if (context.mounted) recordingNotifier.setRecording(false);
    }
  }
}

class const _ShortcutBindingRow({
  required final ShortcutAction action,
  required final ShortcutBinding binding,
  required final bool enabled,
  required final VoidCallback onEdit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final keyColor = enabled
        ? (theme.brightness == .dark ? AppColors.primaryLight : AppColors.primaryDark)
        : colors.onSurfaceVariant;

    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(action.label, style: theme.textTheme.bodyLarge),
                Text(
                  action.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const .symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: .circular(8)),
              backgroundColor: colors.surfaceContainer,
            ),
            onPressed: onEdit,
            child: Text(
              binding.displayLabel,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: .w700, color: keyColor),
            ),
          ),
        ],
      ),
    );
  }
}

class const _RecordShortcutDialog({
  required final ShortcutAction action,
  required final ShortcutBinding currentBinding,
  required final ShortcutNotifier notifier,
}) extends StatefulWidget {
  @override
  State<_RecordShortcutDialog> createState() => _RecordShortcutDialogState();
}

class _RecordShortcutDialogState extends State<_RecordShortcutDialog> {
  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (_closed || event is! KeyDownEvent) return .ignored;
    if (event.logicalKey == .escape) {
      _close();
      return .handled;
    }
    final next = ShortcutBinding.fromKeyEvent(event);
    if (next == null) return .ignored;
    widget.notifier.updateBinding(widget.action, next);
    _close();
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final keyColor = theme.brightness == .dark
        ? AppColors.primaryLight
        : AppColors.primaryDark;

    return AlertDialog(
      title: Row(
        spacing: 8,
        children: [
          const Icon(Icons.keyboard_alt_outlined, color: AppColors.primaryLight, size: 20),
          Expanded(child: Text(widget.action.label)),
        ],
      ),
      content: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Text(
              'Press any key or shortcut combo (Ctrl / Shift / Alt + Key). Press Esc to cancel.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            Container(
              padding: const .all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: .circular(12),
                border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisAlignment: .center,
                spacing: 8,
                children: [
                  Text(
                    'Current:',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  Text(
                    widget.currentBinding.displayLabel,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700, color: keyColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_closed) return;
            widget.notifier.resetAction(widget.action);
            _close();
          },
          child: const Text('Reset'),
        ),
        TextButton(onPressed: _close, child: const Text('Cancel')),
      ],
    );
  }
}
