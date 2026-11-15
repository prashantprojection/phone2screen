---
name: flutter-350-conventions
description: Flutter 3.50 and Dart 3.14 coding standards for Phone2Screen including package:material_ui, class const primary constructors, dot shorthands, manual Riverpod 3, adaptive layout, and strict <350 LOC rules.
---

# Flutter 3.50 & Dart 3.14 Conventions

Follow these conventions for all Dart and Flutter code in Phone2Screen.

## 1. `package:material_ui` & Compatibility Bridge

- Always import `package:material_ui/material_ui.dart` for Material widgets, themes, colors, and `widgets.dart` exports.
- Never import `package:flutter/material.dart`.
- In `MaterialApp.builder`, wrap `child` with `MaterialUiCompatibilityBridge`:
  ```dart
  // ignore: deprecated_member_use
  builder: (context, child) => MaterialUiCompatibilityBridge(
    child: child ?? const SizedBox.shrink(),
  ),
  ```
- In `ThemeData`, prefer `AppBarThemeData`, `CardThemeData`, `DialogThemeData`, and `InputDecorationThemeData`.

## 2. Dart 3.14 Primary Constructors (`class const`)

- Place `const` **after** `class` (never write `const class`):
  ```dart
  // Bodyless model
  class const ClipboardItem({
    required final String text,
    required final DateTime timestamp,
    required final bool fromRemote,
  });

  // Model with methods
  class const StreamTelemetry({
    final int latencyMs = 0,
    final double bitrateMbps = 0.0,
    final Duration connectedDuration = .zero,
  }) {
    StreamTelemetry copyWith({int? latencyMs}) => StreamTelemetry(
      latencyMs: latencyMs ?? this.latencyMs,
      bitrateMbps: bitrateMbps,
      connectedDuration: connectedDuration,
    );
  }

  // StatelessWidget / ConsumerWidget
  class const StatusBadge({super.key, required final SessionPhase phase})
      extends StatelessWidget {
    @override
    Widget build(BuildContext context) => Text(phase.label);
  }
  ```
- Notice `final` in parameter lists declares instance fields directly on the class.

## 3. Dot Shorthands & Layout Spacing

- Use dot shorthands whenever the expected static type makes the target unambiguous:
  - Alignment/Edges/Radius: `const .all(16)`, `const .symmetric(horizontal: 20, vertical: 14)`, `.circular(16)`
  - Enums & named constants: `brightness: .dark`, `resolution: .p1080`, `connectedDuration: .zero`
  - Switches:
    ```dart
    final text = switch (phase) {
      .streaming => 'Live',
      .reconnecting => 'Reconnecting...',
      _ => 'Ready',
    };
    ```
- Note: `Alignment.topLeft` cannot be shortened to `.topLeft` when the parameter type is `AlignmentGeometry` (such as `LinearGradient.begin` or `Align.alignment`); use `Alignment.topLeft` there.
- Use `Row(spacing: 12, children: [...])` and `Column(spacing: 12, children: [...])` instead of manual spacer `SizedBox` widgets.

## 4. Manual Riverpod 3 (Zero Code-Gen)

- Never use `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, or `*.g.dart`.
- Define providers manually:
  ```dart
  final roleProvider = NotifierProvider<RoleNotifier, DeviceRole>(
    RoleNotifier.new,
  );

  class RoleNotifier extends Notifier<DeviceRole> {
    @override
    DeviceRole build() => .receiver;
    void setRole(DeviceRole role) => state = role;
  }
  ```

## 5. Responsive Design & File Size Limit

- Use `lib/core/utils/responsive.dart`: `context.screenSize` (`compact` `< 640`, `medium` `640..1024`, `expanded` `> 1024`), `context.isCompact`, `context.isExpanded`, and `context.contentMaxWidth`.
- Never import or use `flutter_screenutil`.
- Keep every `.dart` file strictly `< 350` lines. Split large screens into cohesive feature widgets.
