# AGENTS.md — Phone2Screen v0.5

AI agent context and engineering constraints for **Phone2Screen** (`com.example.phone2screen`), a LAN & USB WebRTC streamer webcam studio (Phone <-> PC Desktop, DirectShow Virtual Webcam, OBS Studio, and Web Browser).

## Workspace Boundary

- Operate **strictly inside** `d:\personal projects\phone2screen`.
- **NEVER** read, scan, or modify files outside `d:\personal projects\phone2screen` (including parent folders, pub cache, or temp directories). Tests writing files MUST use `.dart_tool/test_tmp_*` inside the workspace and clean up in `addTearDown` — NEVER `Directory.systemTemp`.

## Flutter 3.50 & Dart 3.14 Rules

- **UI Imports**: ALWAYS `import 'package:material_ui/material_ui.dart';`. NEVER import `package:flutter/material.dart`, `package:flutter/cupertino.dart`, or private SDK internals like `package:flutter/src/widgets/_window.dart`.
- **Compat Bridge**: Wrap `MaterialApp.builder` with `MaterialUiCompatibilityBridge` (`// ignore: deprecated_member_use`, in `material_ui ^1.11.0`).
- **Dart 3.14 Syntax**: Use primary constructors (`class const Foo({required final int bar})`, `const` AFTER `class`, NEVER `const class`; never put `final` on ordinary method params), dot shorthands (`.center`, `const .all(16)`, `.circular(16)`, switch `.streaming => ...`), and `Row`/`Column(spacing:)`.
- **Zero Code-Gen**: NEVER use `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, `mockito`, `pigeon`, or `*.g.dart`. Write models, JSON serialization, and Riverpod 3 `Notifier` / `NotifierProvider` manually.
- **Native Adaptive Layout**: Use `ResponsiveContext` (`lib/core/utils/responsive.dart`: `compact` / `medium` / `expanded` via `MediaQuery.sizeOf`) and `LayoutBuilder` — NEVER `flutter_screenutil`.
- **File Size Cap (`< 350` LOC)**: Every `.dart`, `.kt`, `.cpp`, and `.h` file MUST stay strictly under 350 lines.
- **Comment Complex Logic**: Keep concise why-comments on H.264 SDP munging, early ICE buffering, Android 14+ `MediaProjection` consent-before-FGS order, UDP `41234` USB/NIC ranking, `QrCipher` crypto, and DataChannel RTT/`clipboard`/`cam_ctrl` sync.

## v0.2 Multi-Cam, Multi-Window & Studio Architecture

- **Desktop Multi-Peer vs Tier-3 Mobile Safety**:
  - Primary Desktop Receiver hosts up to `maxDesktopReceiverPeers = 4` concurrent peers via `peerId`-routed signaling (`PeerSignalingEvent`/`PeerConnectionEvent`, `MultiCamNotifier`, `Solo` / `2-Up` / `4-Up` grid in `MultiCamGridView`).
  - Mobile Sender/Receiver, secondary windows, and Web Broadcast enforce `maxActivePeers = 1`, prioritize hardware **H.264** first in SDP `m=video` (`prioritizeH264InSdp`), support **true-black `#000000` OLED On-Air Tally** (`OledTallyView` unmounting local `RTCVideoView` with 30s burn-in pixel shift), and do zero Dart-side video processing for browser viewers.
- **Desktop Multi-Window (`DesktopWindowService`)**:
  - `flutter config --list` reports `enable-windowing: (Unavailable)` on Flutter `3.50.0` stable, so `DesktopWindowService` spawns isolated OS receiver processes (`--camera-slot`, `--port`, `--window-title`, `--window-offset`, `--clean-feed`) parsed in `windows/runner/main.cpp` and `WindowLaunchArgs.parse`.
- **OBS Clean Feed & Control DataChannel**:
  - `GET /obs` (`obs_clean_feed_page.dart`) serves a zero-UI, `cursor:none`, 1500ms auto-reconnecting WebRTC feed (`?pin=`, `?fit=cover`, `?mirror=1`, `?bg=black`), while `F` (Fullscreen) + `O` / tap (Hide Controls) provides a unified zero-UI clean stage on the desktop receiver.
  - `phone2screen-control` DataChannel carries `ping`/`pong` RTT, `clipboard`, `cam_ctrl`, and `cam_state` frames (`CameraControlService`, `RemoteCameraPanel`).
- **USB NIC Priority, Studio Look & Persistence**:
  - `network_address_io.dart` ranks USB tethering (`+550`, `isUsbTethered`) above Wi-Fi (`+300/+150`) and Ethernet (`+250`), demoting virtual/VPN adapters (`-1000`).
  - `ViewerDisplayConfig` applies GPU aspect crops, `3x3 Grid`, digital zoom/pan, and BT.709 `colorMatrix`.
  - `LocalPreferencesService` (`local_preferences_io.dart`) persists `AppSettings`, `StreamConfig`, `ShortcutConfig`, custom `CameraRigPreset`s, and `lastEndpoint` as manual JSON.
- **Android Native**: `MainActivity.kt` (`"phone2screen/projection_service"` + `getFilesDir`) and `MediaProjectionService.kt` (`FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` started only after `Helper.requestCapturePermission()`).

## v0.3 Streamer Pro Architecture

- **Windows Native `StudioBridge` (`windows/runner/studio_bridge.cpp`/`.h`)**:
  - Registers `MethodChannel('phone2screen/windows_studio')` wrapped by `WindowsStudioService` (`listVideoCaptureDevices` via DirectShow COM `CLSID_VideoInputDeviceCategory`, `listAudioOutputDevices` via WinMM `waveOutGetDevCapsW`, `setAlwaysOnTop`/`getAlwaysOnTop` via `WS_EX_TOPMOST`).
  - Compiled under MSVC `/W4 /WX` and `_HAS_EXCEPTIONS=0` (no `try`/`catch`/`throw` or `<comdef.h>`; wrap `<dshow.h>`/`<mmsystem.h>` in `#pragma warning(push, 3)`).
- **OBS WebSocket v5 & Live Tally Sync (`ObsWebSocketService`, `ObsSyncNotifier`)**:
  - Pure-Dart FIPS 180-4 SHA-256 (`lib/core/utils/sha256.dart`: `sha256Bytes`, `sha256Hex`, `hmacSha256`, `computeObsWebSocketAuth`) drives OBS WebSocket v5 (`rpcVersion: 1`, `Hello -> Identify -> Identified`, virtual cam toggle, `CreateInput`/`SetInputSettings` for `"Phone2Screen Clean Feed"`, `SetInputAudioSyncOffset` in nanoseconds, and scene/item events).
  - `ObsSyncNotifier` and `MultiCamNotifier` broadcast `LiveTallyMessage` (`{"kind": "tally", "state": "program|preview|standby|off", "scene": "..."}`) over `phone2screen-control` (`DataChannelHelper`) to `SenderScreen` pills and `OledTallyView`.
- **Studio Audio Routing & Mic DSP (`AudioRoutingService`, `AudioStudioNotifier`)**:
  - Enumerates WebRTC `audiooutput` endpoints with Win32 WaveOut fallback, tagging Virtual Audio Cables (`Virtual Mic Ready`), applying `0.0..2.0` stream boost (`Helper.setVolume`), `0..500 ms` lip-sync delay (synced to OBS + `/obs?delay=<ms>` Web Audio `DelayNode`), and live `Voice Clean` vs `Studio Raw` (`cam_ctrl.cmd == "voiceMode"`, `cam_state.voiceClean`).
- **Zero-Config USB Plug-and-Play (`UsbBridgeService`)**:
  - Desktop hosts run `adb reverse tcp:<port> tcp:<port>` across primary & secondary camera window ports; Senders probe `http://127.0.0.1:8080..8083/p2s-info` (`GET /p2s-info`) and surface `isUsbLoopback` peers first in `allDiscoveredPeersProvider` (`USB Wired • Zero-Latency`).
  - Guarded under `FLUTTER_TEST` so real `adb` processes and loopback socket scans never run unless `processRunner` or `allowInTestOverride` is injected.
- **GPU Studio Look Presets & Vignette (`StudioLookPreset`, `VideoStageWidget`)**:
  - `ViewerDisplayConfig` composes 4x5 `StudioLookPreset` matrices (`natural`, `streamPunch`, `warmKeylight`, `coolCyber`, `noirBw`) with user brightness/contrast/saturation; `VideoStageWidget` layers an `IgnorePointer` `RadialGradient` overlay when `vignette: true`.

## v0.4 Native Virtual Camera, Modes & Release Packaging

- **Zero-OBS DirectShow Virtual Camera (`p2s_vcam.dll`, `NativeVirtualCamNotifier`)**:
  - Native DirectShow source filter (`windows/runner/vcam_*`, `p2s_vcam.dll` alongside `phone2screen.exe`) streams 1280x720 RGB24 frames via shared memory (`Local\Phone2ScreenVCamSharedV1`) with `0` Standby, `1` Live, and `2` Privacy Paused slates.
  - Registered per-user in `HKCU` (no admin required) via `StudioBridge` (`WindowsStudioService`) or `scripts/setup_windows_webcam.ps1`, managed by `nativeVirtualCamProvider` (`lib/providers/virtual_cam_provider.dart`) with 20 fps `stageBoundaryKey` `RepaintBoundary` capture on `ReceiverStreamingStage` / `FullscreenStageView`.
- **`Simple` vs `Studio` Progressive Disclosure (`WorkspaceMode`)**:
  - `AppSettings.workspaceMode` defaults to `.simple`, surfacing `WorkspaceModePill` (`AppShellHeader` >= 880px Receiver, `ReceiverScreen` lobby, `SettingsScreen` Appearance) and `SimpleWebcamCard` (`Use as PC Webcam — No OBS Required`), while `.studio` reveals full multi-window (`+ Open Camera Window` / `+ Window`), `Virtual Cam & OBS` lobby launcher, `Live Stats`, and `Share Text` controls. `Camera Rig` stays accessible in both modes.
- **Privacy Freeze-Frame (`P`) & Auto-Reconnect**:
  - `ShortcutAction.toggleVideoPause` (`P`) and `Pause` / `Resume` controls toggle `ViewerDisplayConfig.isVideoPaused` / `SessionState.isVideoPaused` and sync `RemoteCameraCommandType.videoPause` (`cam_ctrl` / `cam_state.videoPaused`) bidirectionally, overlaying a frosted `#EB0B0E14` `Camera Paused` privacy slate on `VideoStageWidget` and switching `p2s_vcam.dll` to state `2`.
  - `SessionSenderFlow` performs a 1-shot `650ms` auto-reconnect (`SessionPhase.reconnecting`, probing USB loopback first) on transient active-stream socket drops.
- **Windows Release Packaging**: `scripts/package_windows.ps1` + `windows/packaging/phone2screen.iss` produce `dist/Phone2Screen-v0.5.0-Windows-x64.zip` (+ `.sha256`) and Inno Setup 6 non-admin `Phone2Screen-Setup-v0.5.0.exe`.

## v0.5 Encrypted QR, Creator Stage FX, iOS USB & Cleanup

- **Encrypted App-Only QR Pairing (`QrCipher`, `P2S1.`)**:
  - `lib/core/utils/sha256.dart` provides RFC 2104 `hmacSha256`; `lib/core/utils/qr_cipher.dart` implements `QrCipher` (`P2S1.<base64url>` with 12-byte nonce, `P2S1-ENC`/`P2S1-MAC` key derivation, HMAC-SHA256 counter-mode XOR keystream, and constant-time 16-byte MAC verification).
  - `SignalingData.toQrString`/`fromQrString` requires `P2S1.` and rejects cleartext JSON/URLs; `QrPairingCard` caches `_qrData` per endpoint and displays `Encrypted • App-Only QR`, while `QrScannerPage` rejects non-`P2S1` codes.
- **GPU Portrait Bokeh, Face Fill-Light, Desk Keystone & `B` Shortcut**:
  - `ViewerDisplayConfig` (`lib/providers/viewer_display_provider.dart`) adds `PortraitBokehMode` (`off`, `soft` sigma `7.0`, `strong` sigma `15.0`), `faceFillLight` (`0.0..1.0`), `deskCamMode` (180° flip), `keystoneVertical` / `keystoneHorizontal` (`-0.35..0.35`), and `resetLookAndFraming()`.
  - `lib/views/shared/video_stage_fx.dart` renders `buildPortraitBokehLayer` (`ShaderMask` `dstIn` + `ImageFiltered`), `FaceFillLightOverlay`, and `applyDeskKeystoneTransform`.
  - `ShortcutAction.cycleBackgroundBlur` (`B`) and UI controls in `SimpleWebcamCard`, `ReceiverControlsBar`, and `CreatorStageFxSection` (`RemoteCameraPanel`) control all FX live.
- **Sender Selfie Ring-Light (`SelfieRingLightOverlay`)**:
  - `lib/views/sender/widgets/selfie_ring_light_overlay.dart` exports `SelfieRingLightMode` (`off`, `warm` `#FFFFE4B5`, `daylight` `#FFF4F8FF`), `SelfieRingLightOverlay`, `LiveStatusPill`, `BatterySaverPill`, and `RingLightPill` in `SenderScreen` (camera mode only, hidden during `OledTallyView`).
- **iOS USB Personal Hotspot, App Store `Info.plist` & Workspace Pruning**:
  - `isUsbTetherInterface` (`network_address_io.dart`) ranks Apple iPhone USB Personal Hotspot (`172.20.10.*`, `'apple mobile device'`, `'iphone'`) at `+550` alongside Android RNDIS (`192.168.42.*`).
  - `ios/Runner/Info.plist` sets `CFBundleDisplayName` to `Phone2Screen`, clarifies local-only privacy descriptions, and removes unused `voip` from `UIBackgroundModes` (keeping `audio`).
  - Deleted unused `linux/` and `macos/` directories (active targets: Windows, Android, iOS, Web; `0.5.0+5`).

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
