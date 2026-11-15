# AGENTS.md — Phone2Screen v0.1

AI agent context and engineering constraints for **Phone2Screen** (`com.example.phone2screen`), a LAN-first WebRTC camera and screen casting app (Phone <-> Windows Desktop or any Web Browser).

## Workspace Boundary

- Operate **strictly inside** `d:\personal projects\phone2screen`.
- **NEVER** read, scan, or modify files outside `d:\personal projects\phone2screen` (including parent folders, pub cache, or temp directories).

## Flutter 3.50 & Dart 3.14 Rules

- **UI Imports**: ALWAYS `import 'package:material_ui/material_ui.dart';`. NEVER import `package:flutter/material.dart` or `package:flutter/cupertino.dart`.
- **Compat Bridge**: Wrap `MaterialApp.builder` with `MaterialUiCompatibilityBridge` (`// ignore: deprecated_member_use`, present in `material_ui ^1.11.0` for plugin compatibility).
- **Dart 3.14 Syntax**: Use primary constructors (`class const Foo({required final int bar})`, `const` AFTER `class`, NEVER `const class`; never put `final` on ordinary method params), private named parameters (`{required this._x}`), dot shorthands (`.center`, `const .all(16)`, `.circular(16)`, switch `.streaming => ...`), and `Row`/`Column(spacing:)`.
- **Zero Code-Gen**: NEVER use `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, `mockito`, `pigeon`, or `*.g.dart`. Write models and Riverpod 3 `Notifier` / `NotifierProvider` manually.
- **Native Adaptive Layout**: Use `ResponsiveContext` (`lib/core/utils/responsive.dart`: `ScreenSize` `compact`/`medium`/`expanded` via `MediaQuery.sizeOf`) and `LayoutBuilder` — NEVER `flutter_screenutil`.
- **File Size Cap (`< 350` LOC)**: Every `.dart` and `.kt` file MUST stay strictly under 350 lines. Split widgets, dialogs, and helpers early.
- **Comment Complex Logic**: Add concise why-comments on H.264 SDP munging, early ICE candidate buffering, Android 14+ `MediaProjection` consent-before-FGS order, UDP `41234` NIC ranking/discovery, and DataChannel RTT/`clipboard` sync.
- **Tier-3 Low-End Phone Rules**: Prioritize hardware **H.264** first in SDP `m=video`, enforce `maxActivePeers = 1`, support **Eco Dim Preview** (unmount local camera `RTCVideoView` while streaming), and perform zero Dart-side video processing for the browser viewer.

## Bidirectional Single-Codebase Architecture

Phone2Screen runs one adaptive codebase toggled via `DeviceRole.receiver` / `DeviceRole.sender` (1-tap role switch):
- **Phone -> Desktop Receiver**: Receiver serves `/ws` (`8080..8095`) and broadcasts UDP `41234` (`P2S_V1`) beacons; Sender connects via LAN discovery, QR (`SignalingData`), or manual entry.
- **Phone -> Browser Web Companion (`GET /`)**: Sender hosts an embedded `HttpServer` serving static HTML/JS WebRTC on `http://<ip>:<port>` and `/ws` signaling.
- **Symmetry**: Phone/Sender is Offerer (captures camera/screen, opens `phone2screen-control` DataChannel for `ping`/`pong` RTT + `clipboard`); Desktop/Browser Viewer is Answerer.
- **Core & Models**: `StreamConstants`, `AppColors`/`AppTheme`, `ResponsiveContext`, `DeviceRole`, `SessionPhase`, `SignalingData`, `SignalingMessage`, `DiscoveredPeer`, `NetworkInterfaceInfo`, `MediaSourceType`/`CameraLens`, `StreamConfig` (`StreamResolution`), `StreamTelemetry`, `ViewerDisplayConfig`, `ClipboardItem`.
- **Android Native**: `MainActivity.kt` (`MethodChannel` `"phone2screen/projection_service"`) and `MediaProjectionService.kt` (`FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`) started only after `Helper.requestCapturePermission()`.

## Skills & Verification

Read these workspace skills before coding or verifying:
- [.agents/skills/flutter-350-conventions/SKILL.md](.agents/skills/flutter-350-conventions/SKILL.md)
- [.agents/skills/webrtc-lan-protocol/SKILL.md](.agents/skills/webrtc-lan-protocol/SKILL.md)
- [.agents/skills/verify-phone2screen/SKILL.md](.agents/skills/verify-phone2screen/SKILL.md)

Verification commands (from workspace root):
```powershell
flutter pub get
flutter analyze --fatal-infos
flutter test
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
```
