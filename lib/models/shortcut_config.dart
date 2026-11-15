import 'package:flutter/services.dart';

/// User-configurable keyboard actions across receiver and sender controls.
enum ShortcutAction {
  toggleFullscreen,
  toggleFullscreenHud,
  toggleMute,
  rotateVideo,
  toggleMirror,
  toggleFit,
  toggleStats,
  openClipboard,
  openGuide,
  disconnectStream;

  /// Human-readable short title shown in settings and shortcut badges.
  String get label => switch (this) {
    .toggleFullscreen => 'Fullscreen',
    .toggleFullscreenHud => 'Fullscreen Overlay',
    .toggleMute => 'Mute Audio',
    .rotateVideo => 'Rotate 90°',
    .toggleMirror => 'Mirror Video',
    .toggleFit => 'Fit / Fill Screen',
    .toggleStats => 'Live Stats',
    .openClipboard => 'Share Text',
    .openGuide => 'How to Use',
    .disconnectStream => 'Stop / Disconnect',
  };

  /// Concise description of what triggering this shortcut does.
  String get description => switch (this) {
    .toggleFullscreen => 'Enter or exit fullscreen video',
    .toggleFullscreenHud => 'Show or hide controls while in fullscreen',
    .toggleMute => 'Mute or unmute stream audio or microphone',
    .rotateVideo => 'Rotate incoming video clockwise',
    .toggleMirror => 'Flip incoming video horizontally',
    .toggleFit => 'Switch between letterbox fit and edge-to-edge fill',
    .toggleStats => 'Show or hide resolution, FPS, and latency overlay',
    .openClipboard => 'Open live text & clipboard sharing',
    .openGuide => 'Open the quick-start guide',
    .disconnectStream => 'End the active stream session',
  };
}

/// Key combination (logical key + optional modifiers) assigned to an action.
class const ShortcutBinding({
  required final int keyId,
  required final String keyLabel,
  final bool control = false,
  final bool shift = false,
  final bool alt = false,
}) {
  // Reject Escape (reserved for exiting dialogs/fullscreen) and bare modifiers.
  static bool _isIgnoredKey(LogicalKeyboardKey key) => switch (key) {
    .escape ||
    .control ||
    .controlLeft ||
    .controlRight ||
    .shift ||
    .shiftLeft ||
    .shiftRight ||
    .alt ||
    .altLeft ||
    .altRight ||
    .meta ||
    .metaLeft ||
    .metaRight => true,
    _ => false,
  };

  /// Builds a [ShortcutBinding] from a key press, or returns `null` if the
  /// pressed key is Escape or a standalone modifier key.
  static ShortcutBinding? fromKeyEvent(KeyDownEvent event) {
    final key = event.logicalKey;
    if (_isIgnoredKey(key)) return null;

    final rawLabel = key.keyLabel.trim();
    final resolvedLabel = switch (key) {
      .space => 'Space',
      _ when rawLabel.length == 1 => rawLabel.toUpperCase(),
      _ when rawLabel.isNotEmpty => rawLabel,
      _ => key.debugName ?? 'Key',
    };

    final hardware = HardwareKeyboard.instance;
    return ShortcutBinding(
      keyId: key.keyId,
      keyLabel: resolvedLabel,
      control: hardware.isControlPressed,
      shift: hardware.isShiftPressed,
      alt: hardware.isAltPressed,
    );
  }

  /// Formatted key combination string such as `'F'` or `'Ctrl + F'`.
  String get displayLabel {
    final parts = <String>[
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      keyLabel,
    ];
    return parts.join(' + ');
  }

  /// Whether [event] and the active modifier flags match this binding.
  bool matches(
    KeyDownEvent event, {
    required bool ctrl,
    required bool shift,
    required bool alt,
  }) {
    return event.logicalKey.keyId == keyId &&
        control == ctrl &&
        this.shift == shift &&
        this.alt == alt;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShortcutBinding &&
          runtimeType == other.runtimeType &&
          keyId == other.keyId &&
          control == other.control &&
          shift == other.shift &&
          alt == other.alt;

  @override
  int get hashCode => Object.hash(keyId, control, shift, alt);
}

/// Default single-key bindings using Unicode keyIds for `const` compatibility.
const Map<ShortcutAction, ShortcutBinding> defaultShortcutBindings = {
  .toggleFullscreen: ShortcutBinding(keyId: 0x00000066, keyLabel: 'F'),
  .toggleFullscreenHud: ShortcutBinding(keyId: 0x0000006f, keyLabel: 'O'),
  .toggleMute: ShortcutBinding(keyId: 0x0000006d, keyLabel: 'M'),
  .rotateVideo: ShortcutBinding(keyId: 0x00000072, keyLabel: 'R'),
  .toggleMirror: ShortcutBinding(keyId: 0x00000068, keyLabel: 'H'),
  .toggleFit: ShortcutBinding(keyId: 0x0000007a, keyLabel: 'Z'),
  .toggleStats: ShortcutBinding(keyId: 0x00000073, keyLabel: 'S'),
  .openClipboard: ShortcutBinding(keyId: 0x00000063, keyLabel: 'C'),
  .openGuide: ShortcutBinding(keyId: 0x00000067, keyLabel: 'G'),
  .disconnectStream: ShortcutBinding(keyId: 0x00000078, keyLabel: 'X'),
};

/// Global keyboard shortcut preferences and action lookup configuration.
class const ShortcutConfig({
  final bool enabled = true,
  final Map<ShortcutAction, ShortcutBinding> bindings = defaultShortcutBindings,
}) {
  /// Returns the effective [ShortcutBinding] for [action].
  ShortcutBinding bindingFor(ShortcutAction action) =>
      bindings[action] ?? defaultShortcutBindings[action]!;

  /// Returns the formatted shortcut key hint, or empty when disabled.
  String hintFor(ShortcutAction action) =>
      enabled ? bindingFor(action).displayLabel : '';

  /// Appends the formatted shortcut hint to [base] when shortcuts are enabled.
  String tooltipFor(String base, ShortcutAction action) =>
      enabled ? '$base (${bindingFor(action).displayLabel})' : base;

  /// Finds the [ShortcutAction] matching [event] and modifiers, or `null` if
  /// shortcuts are disabled or nothing matches.
  ShortcutAction? matchEvent(
    KeyDownEvent event, {
    required bool ctrl,
    required bool shift,
    required bool alt,
  }) {
    if (!enabled) return null;
    for (final action in ShortcutAction.values) {
      if (bindingFor(
        action,
      ).matches(event, ctrl: ctrl, shift: shift, alt: alt)) {
        return action;
      }
    }
    return null;
  }

  /// Returns an updated copy of [ShortcutConfig].
  ShortcutConfig copyWith({
    bool? enabled,
    Map<ShortcutAction, ShortcutBinding>? bindings,
  }) {
    return ShortcutConfig(
      enabled: enabled ?? this.enabled,
      bindings: bindings ?? this.bindings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ShortcutConfig ||
        runtimeType != other.runtimeType ||
        enabled != other.enabled) {
      return false;
    }
    for (final action in ShortcutAction.values) {
      if (bindingFor(action) != other.bindingFor(action)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    Object.hashAll(ShortcutAction.values.map(bindingFor)),
  );
}
