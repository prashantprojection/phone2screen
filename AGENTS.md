# AGENTS.md — Phone2Screen v0.2

AI agent context and engineering constraints for **Phone2Screen** (`com.example.phone2screen`), a LAN & USB WebRTC streamer webcam studio (Phone <-> PC Desktop, OBS Studio, and Web Browser).

## Workspace Boundary

- Operate **strictly inside** `d:\personal projects\phone2screen`.
- **NEVER** read, scan, or modify files outside `d:\personal projects\phone2screen` (including parent folders, pub cache, or temp directories). Tests writing files MUST use `.dart_tool/test_tmp_*` inside the workspace and clean up in `addTearDown` — NEVER `Directory.systemTemp`.

## Flutter 3.50 & Dart 3.14 Rules

- **UI Imports**: ALWAYS `import 'package:material_ui/material_ui.dart';`. NEVER import `package:flutter/material.dart`, `package:flutter/cupertino.dart`, or private SDK internals like `package:flutter/src/widgets/_window.dart`.
- **Compat Bridge**: Wrap `MaterialApp.builder` with `MaterialUiCompatibilityBridge` (`// ignore: deprecated_member_use`, in `material_ui ^1.11.0`).
- **Dart 3.14 Syntax**: Use primary constructors (`class const Foo({required final int bar})`, `const` AFTER `class`, NEVER `const class`; never put `final` on ordinary method params), dot shorthands (`.center`, `const .all(16)`, `.circular(16)`, switch `.streaming => ...`), and `Row`/`Column(spacing:)`.
- **Zero Code-Gen**: NEVER use `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, `mockito`, `pigeon`, or `*.g.dart`. Write models, JSON serialization, and Riverpod 3 `Notifier` / `NotifierProvider` manually.
- **Native Adaptive Layout**: Use `ResponsiveContext` (`lib/core/utils/responsive.dart`: `compact` / `medium` / `expanded` via `MediaQuery.sizeOf`) and `LayoutBuilder` — NEVER `flutter_screenutil`.
- **File Size Cap (`< 350` LOC)**: Every `.dart` and `.kt` file MUST stay strictly under 350 lines.
- **Comment Complex Logic**: Keep concise why-comments on H.264 SDP munging, early ICE buffering, Android 14+ `MediaProjection` consent-before-FGS order, UDP `41234` USB/NIC ranking, and DataChannel RTT/`clipboard`/`cam_ctrl` sync.

## v0.2 Multi-Cam, Multi-Window & Studio Architecture

- **Desktop Multi-Peer vs Tier-3 Mobile Safety**:
  - Primary Desktop Receiver hosts up to `maxDesktopReceiverPeers = 4` concurrent peers via `peerId`-routed signaling (`PeerSignalingEvent`/`PeerConnectionEvent`, `MultiCamNotifier`, `Solo` / `2-Up` / `4-Up` grid in `MultiCamGridView`).
  - Mobile Sender/Receiver, secondary windows, and Web Broadcast enforce `maxActivePeers = 1`, prioritize hardware **H.264** first in SDP `m=video` (`prioritizeH264InSdp`), support **true-black `#000000` OLED On-Air Tally** (`OledTallyView` unmounting local `RTCVideoView` with 30s burn-in pixel shift), and do zero Dart-side video processing for browser viewers.
- **Desktop Multi-Window (`DesktopWindowService`)**:
  - `flutter config --list` reports `enable-windowing: (Unavailable)` on Flutter `3.50.0` stable, so `DesktopWindowService` spawns isolated OS receiver processes (`--camera-slot`, `--port`, `--window-title`, `--window-offset`, `--clean-feed`) parsed in `windows/runner/main.cpp` and `WindowLaunchArgs.parse`.
- **OBS Clean Feed & Control DataChannel**:
  - `GET /obs` (`obs_clean_feed_page.dart`) serves a zero-UI, `cursor:none`, 1500ms auto-reconnecting WebRTC feed (`?pin=`, `?fit=cover`, `?mirror=1`, `?bg=black`), while `B` / **OBS Clean** toggles edge-to-edge `cleanFeedMode` on the desktop receiver.
  - `phone2screen-control` DataChannel carries `ping`/`pong` RTT, `clipboard`, `cam_ctrl`, and `cam_state` frames (`CameraControlService`, `RemoteCameraPanel`).
- **USB NIC Priority, Studio Look & Persistence**:
  - `network_address_io.dart` ranks USB tethering (`+550`, `isUsbTethered`) above Wi-Fi (`+300/+150`) and Ethernet (`+250`), demoting virtual/VPN adapters (`-1000`).
  - `ViewerDisplayConfig` applies GPU aspect crops, `3x3 Grid`, digital zoom/pan, and BT.709 `colorMatrix`.
  - `LocalPreferencesService` (`local_preferences_io.dart`) persists `AppSettings`, `StreamConfig`, `ShortcutConfig`, custom `CameraRigPreset`s, and `lastEndpoint` as manual JSON.
- **Android Native**: `MainActivity.kt` (`"phone2screen/projection_service"` + `getFilesDir`) and `MediaProjectionService.kt` (`FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` started only after `Helper.requestCapturePermission()`).

## Skills & Verification

Read before coding or verifying:
- [.agents/skills/flutter-350-conventions/SKILL.md](.agents/skills/flutter-350-conventions/SKILL.md)
- [.agents/skills/webrtc-lan-protocol/SKILL.md](.agents/skills/webrtc-lan-protocol/SKILL.md)
- [.agents/skills/verify-phone2screen/SKILL.md](.agents/skills/verify-phone2screen/SKILL.md)

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter analyze --fatal-infos
flutter test
flutter build windows --debug
```
