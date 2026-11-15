# Phone2Screen v0.1

**Bidirectional LAN-first WebRTC camera and screen casting (`Phone <-> Desktop / Browser / Phone`) without cloud relays or codegen bloat.**

Built with **Flutter 3.50**, **Dart 3.14**, **`package:material_ui`**, **Riverpod 3**, and **`flutter_webrtc`**, Phone2Screen ships a single adaptive codebase toggled in one tap between **Receiver** and **Sender** roles.

---

## Key Capabilities

- **Bidirectional Single-Codebase Roles (`DeviceRole.receiver` / `DeviceRole.sender`)**:
  - **Receiver Mode**: Hosts an embedded HTTP + WebSocket signaling server (`8080..8095`), generates a pairing QR code, displays selectable LAN network interfaces, and broadcasts UDP discovery beacons.
  - **Sender Mode**: Discovers nearby Receivers automatically, scans pairing QR codes, or connects by manual IP/port/PIN to stream camera (`Front` / `Back`) or full screen (`MediaProjection` on Android 14+, screen/window picker on desktop).
- **Zero-Install Browser Web Companion (`GET /`)**:
  - Open `http://<receiver-ip>:<port>` from any desktop or mobile browser on the LAN to cast camera or screen directly to a Receiver over native browser WebRTC and `/ws` signaling.
- **LAN UDP Discovery (`41234`, `P2S_V1`) & Pairing**:
  - Automatic RFC1918 NIC ranking (`NetworkAddressService`), 2s `P2S_V1` UDP beacons with 8s stale pruning, QR pairing (`SignalingData`), optional 4-digit PIN enforcement, and manual IP connect.
- **Live Controls, Telemetry & Clipboard Sync**:
  - `phone2screen-control` WebRTC DataChannel delivers 1Hz `ping`/`pong` RTT latency, bitrate/resolution stats, and bidirectional text clipboard sync (`ClipboardSyncSheet`).
  - Receiver stage controls: Fit/Fill, 90° rotation, mirror, audio mute, telemetry pill, and immersive fullscreen.

---

## Tier-3 Low-End Phone Optimizations

- **H.264 SDP Priority**: Reorders `m=video` payload types so hardware H.264 runs before software codecs.
- **Single-Peer Guard (`maxActivePeers = 1`)**: Prevents concurrent WebRTC encoders from saturating CPU and battery.
- **Eco Dim Preview**: Unmounts the local sender `RTCVideoView` during live streaming to cut GPU compositing and battery drain.
- **Android 14+ Safe Screen Capture**: Requests `Helper.requestCapturePermission()` before starting `MediaProjectionService` (`FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`) via `phone2screen/projection_service`.

---

## Architecture & Tech Stack

- **Flutter / Dart**: `3.50` / `3.14` (`package:material_ui/material_ui.dart`, `class const` primary constructors, dot shorthands, Flex `spacing:`, adaptive `ResponsiveContext` via `MediaQuery.sizeOf`).
- **Zero Code-Gen**: Handwritten models and manual Riverpod 3 `Notifier` / `NotifierProvider` (`flutter_riverpod ^3.0.3`); zero `build_runner`, `freezed`, `json_serializable`, or `flutter_screenutil`.
- **Layout (`< 350` LOC per file)**:
  - `lib/core/` — constants, Studio Dark/Light Material 3 theme, responsive breakpoints
  - `lib/models/` — immutable session, signaling, media config, telemetry, and peer models
  - `lib/services/` — NIC ranking, UDP discovery, HTTP/WS server + Browser Companion, WebRTC & media capture
  - `lib/providers/` — manual Riverpod 3 platform, settings, discovery, and session state
  - `lib/views/` — `shared/` shell/stage/clipboard widgets, `receiver/`, `sender/`, and `settings/`

---

## Quick Start & Verification

```powershell
# Install dependencies
flutter pub get

# Run Windows Desktop Receiver or Android Sender
flutter run -d windows
flutter run -d <android-device-id>

# Verification gates
flutter analyze --fatal-infos
flutter test
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter build windows --debug
```

See [AGENTS.md](AGENTS.md) and [.agents/skills/verify-phone2screen/SKILL.md](.agents/skills/verify-phone2screen/SKILL.md) for engineering constraints and protocol details.
