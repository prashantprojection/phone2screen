import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shortcut_config.dart';

/// Global keyboard shortcut configuration provider.
final shortcutProvider = NotifierProvider<ShortcutNotifier, ShortcutConfig>(
  ShortcutNotifier.new,
);

/// Notifier managing shortcut toggle state and conflict-free key bindings.
class ShortcutNotifier extends Notifier<ShortcutConfig> {
  @override
  ShortcutConfig build() => const ShortcutConfig();

  /// Enables or disables global keyboard shortcuts.
  void setEnabled(bool enabled) => state = state.copyWith(enabled: enabled);

  /// Assigns [binding] to [action], swapping any conflicting action to
  /// [action]'s previous binding so zero duplicate bindings exist.
  void updateBinding(ShortcutAction action, ShortcutBinding binding) {
    final previous = state.bindingFor(action);
    final updated = <ShortcutAction, ShortcutBinding>{
      for (final item in ShortcutAction.values) item: state.bindingFor(item),
    };
    for (final other in ShortcutAction.values) {
      if (other != action && updated[other] == binding) {
        updated[other] = previous;
      }
    }
    updated[action] = binding;
    state = state.copyWith(bindings: Map.unmodifiable(updated));
  }

  /// Restores [action] to its default binding, swapping any conflict.
  void resetAction(ShortcutAction action) =>
      updateBinding(action, defaultShortcutBindings[action]!);

  /// Restores all shortcut bindings and enabled state to defaults.
  void resetDefaults() => state = const ShortcutConfig();

  /// Replaces the full [ShortcutConfig] (used when loading preferences).
  void replaceConfig(ShortcutConfig config) => state = config;
}

/// Whether the settings UI is currently recording a replacement key press.
final isRecordingShortcutProvider =
    NotifierProvider<ShortcutRecordingNotifier, bool>(
      ShortcutRecordingNotifier.new,
    );

/// Notifier pausing global shortcut dispatch while recording a new binding.
class ShortcutRecordingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Updates active shortcut recording state.
  void setRecording(bool value) => state = value;
}
