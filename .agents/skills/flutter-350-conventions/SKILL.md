---
name: flutter-350-conventions
description: Flutter 3.50 and Dart 3.14 coding standards for Phone2Screen v0.5 including package:material_ui, class const primary constructors, dot shorthands, manual Riverpod 3, DesktopWindowService multi-window spawning, WindowsStudioService & p2s_vcam.dll MSVC Win32 C++ constraints, WorkspaceMode Simple/Studio progressive disclosure, Creator Stage FX & Selfie Ring-Light, manual JSON persistence, adaptive layout, and strict <350 LOC rules (.dart/.kt/.cpp/.h).
---

# Flutter 3.50 & Dart 3.14 Conventions (v0.5)

Follow these conventions for all Dart and Flutter code in Phone2Screen (`0.5.0+5`, targeting Windows, Android, iOS, and Web — unused `linux/` and `macos/` runners were removed).

## 1. `package:material_ui` & Compatibility Bridge

- Always import `package:material_ui/material_ui.dart` for Material widgets, themes, colors, and `widgets.dart` exports.
- Never import `package:flutter/material.dart` or `package:flutter/cupertino.dart`.
- In `MaterialApp.builder`, wrap `child` with `MaterialUiCompatibilityBridge`:
  ```dart
  // ignore: deprecated_member_use
  builder: (context, child) => MaterialUiCompatibilityBridge(
    child: child ?? const SizedBox.shrink(),
  ),
  ```
- In `ThemeData`, prefer `AppBarThemeData`, `CardThemeData`, `DialogThemeData`, and `InputDecorationThemeData`.

## 2. Dart 3.14 Primary Constructors (`class const`)

- Place `const` **after** `class` (never write `const class`, and never put `final` on ordinary method parameters):
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

## 3. Dot Shorthands & Layout Spacing

- Use dot shorthands whenever the expected static type makes the target unambiguous:
  - Edges/Radius: `const .all(16)`, `const .symmetric(horizontal: 20, vertical: 14)`, `.circular(16)`
  - Enums & named constants: `brightness: .dark`, `resolution: .p1080`, `connectedDuration: .zero`
  - Switches:
    ```dart
    final text = switch (phase) {
      .streaming => 'Live',
      .reconnecting => 'Reconnecting...',
      _ => 'Ready',
    };
    ```
- Note: `Alignment.topLeft` / `Alignment.center` cannot be shortened to `.topLeft` / `.center` when the parameter type is `AlignmentGeometry` (such as `LinearGradient.begin`, `Align.alignment`, or `Container.alignment`).
- Use `Row(spacing: 12, children: [...])` and `Column(spacing: 12, children: [...])` instead of manual spacer `SizedBox` widgets.

## 4. Manual Riverpod 3 (Zero Code-Gen)

- Never use `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, `mockito`, `pigeon`, or `*.g.dart`.
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

## 5. Desktop Multi-Window Spawning (`DesktopWindowService`)

- `flutter config --list` reports `enable-windowing: (Unavailable)` on Flutter `3.50.0` stable.
- **NEVER** import private SDK internals such as `package:flutter/src/widgets/_window.dart`.
- Instead, use `DesktopWindowService` (`lib/services/windowing/desktop_window_service.dart` / `desktop_window_io.dart`), which spawns isolated OS processes (`Process.start(Platform.resolvedExecutable, args)`) with `WindowLaunchArgs` flags:
  - `--camera-slot=<2..4>`, `--port=<p>`, `--window-title=Phone2Screen — Camera <n>`, `--window-offset=<px>`, and optional `--clean-feed`.
- `windows/runner/main.cpp` applies `--window-title=` and `--window-offset=` to the native Win32 window (default title `Phone2Screen`) and forwards args to Dart `main(List<String> args)` -> `WindowLaunchArgs.parse(args)`.
- Secondary windows enforce `maxActivePeers = 1` and guard against spawning child processes under `FLUTTER_TEST` (accepting injected `DesktopWindowLauncher` callbacks in unit tests).

## 6. Manual JSON Persistence (`LocalPreferencesService`)

- Persist preferences manually via `LocalPreferencesService` (`lib/services/storage/local_preferences_service.dart` + `local_preferences_io.dart` / `local_preferences_stub.dart`) — zero codegen.
- `PreferencesSnapshot` manually encodes/decodes `AppSettings`, `StreamConfig`, `ShortcutConfig`, custom `CameraRigPreset` lists, and `lastEndpoint` (`SignalingData`) with defensive `tryFromJson`/`fromJson` fallbacks.
- Storage paths: Windows `%APPDATA%\Phone2Screen\preferences.json`, Android `MethodChannel('phone2screen/projection_service')` `getFilesDir` -> `phone2screen_prefs.json`, iOS/fallback `$HOME/.phone2screen_prefs.json`, and in-memory isolation when `Platform.environment.containsKey('FLUTTER_TEST')` (unless `LocalPreferencesService.fromFilePath(...)` is passed explicitly under `.dart_tool/test_tmp_*`).

## 7. Windows Native Bridge & Virtual Camera (`StudioBridge` & `p2s_vcam.dll`)

- `WindowsStudioService` (`lib/services/windowing/windows_studio_service.dart`) wraps `MethodChannel('phone2screen/windows_studio')` backed by `StudioBridge` (`windows/runner/studio_bridge.cpp`/`.h`), while `NativeVirtualCamNotifier` (`lib/providers/virtual_cam_provider.dart`) drives `p2s_vcam.dll` (`windows/runner/vcam_*`, shared memory `Local\Phone2ScreenVCamSharedV1`, HKCU per-user registration, 20 fps `stageBoundaryKey` `RepaintBoundary` capture).
- `windows/CMakeLists.txt` compiles C++ targets (`phone2screen` & `p2s_vcam`) with MSVC `/W4 /WX` (warnings as errors) and `_HAS_EXCEPTIONS=0`:
  - **NEVER** use `try`, `catch`, `throw`, or `<comdef.h>` in `windows/runner/*.cpp`.
  - Wrap Win32 multimedia/DirectShow headers (`<dshow.h>`, `<mmsystem.h>`, `<objbase.h>`, `<oleauto.h>`) in `#pragma warning(push, 3)` ... `#pragma warning(pop)`, and avoid unused variables/parameters.
  - Link `ole32.lib`, `oleaut32.lib`, `strmiids.lib`, and `winmm.lib` in `windows/runner/CMakeLists.txt`.

## 8. Workspace Modes, Creator FX & Packaging

- `AppSettings.workspaceMode` (`WorkspaceMode.simple` default / `WorkspaceMode.studio`) controls progressive disclosure via `WorkspaceModePill`, `SimpleWebcamCard` (Zero-OBS Windows Webcam + 1-tap `Blur` chip), `NativeVirtualCamSection`, and `ReceiverControlsBar` (`Blur` `B` + `Camera Rig` visible in both modes).
- `ViewerDisplayNotifier` (`lib/providers/viewer_display_provider.dart`) & `video_stage_fx.dart` handle GPU `PortraitBokehMode` (`off`, `soft`, `strong`), `FaceFillLightOverlay`, and `applyDeskKeystoneTransform`, wired into `CreatorStageFxSection` (`RemoteCameraPanel`); `SelfieRingLightOverlay` (`lib/views/sender/widgets/selfie_ring_light_overlay.dart`) provides `off`/`warm`/`daylight` bezel lighting on `SenderScreen` camera feeds.
- Windows release artifacts (`0.5.0`) are staged via `scripts/package_windows.ps1` and `windows/packaging/phone2screen.iss` (non-admin x64 Inno Setup 6 installer + `scripts/setup_windows_webcam.ps1`).

## 9. Responsive Design & File Size Limit

- Use `lib/core/utils/responsive.dart`: `context.screenSize` (`compact` `< 640`, `medium` `640..1024`, `expanded` `> 1024`), `context.isCompact`, `context.isExpanded`, and `context.contentMaxWidth`.
- Never import or use `flutter_screenutil`.
- Keep every `.dart`, `.kt`, `.cpp`, and `.h` file strictly `< 350` lines. Split large screens or native bridges into cohesive files early.
