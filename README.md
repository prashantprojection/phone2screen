# Phone2Screen v0.4

**Phone2Screen** turns 1–4 phones into low-latency LAN or USB webcams and screen broadcasters for **Windows PC**, **Zoom / Google Meet / Teams / Discord**, **OBS Studio**, and **any Web Browser** — completely offline, with zero accounts, zero cloud servers, and zero watermarks.

- **Zero-OBS Windows Webcam (`Phone2Screen Camera`)**: Built-in native DirectShow virtual webcam (`p2s_vcam.dll`) works out of the box in Zoom, Google Meet, Microsoft Teams, Discord, and OBS with 1-click per-user setup (no administrator privileges required).
- **Simple & Studio Modes**: Start in **Simple** mode for plug-and-play webcam calls, or switch to **Studio** mode for multi-camera grids (`Solo` / `2-Up` / `4-Up`), multi-window desktop receivers, zero-UI OBS Browser Source (`/obs`), 1-click **OBS WebSocket v5** tally sync, and Studio Look color grading.
- **Privacy Freeze-Frame (`P`) & Auto-Reconnect**: Press **`P`** (or **Pause**) on either PC or phone to replace the live feed with a frosted privacy slate and send a native virtual-cam privacy slate, plus sub-second (`650ms`) auto-reconnect on transient Wi-Fi or USB drops.
- **Private & Offline**: Video travels peer-to-peer over Wi-Fi, mobile hotspot, USB tethering, or zero-config ADB USB cable.

---

## Quick Start (3 Steps)

> Tap **`?` (`G`)** in the top bar anytime for the in-app visual guide.

### Option 1: Use Phone as PC Webcam — No OBS Required (`Simple` Mode)
1. Open **Phone2Screen** on your Windows PC (starts in **Receive • Simple**).
2. Click **Enable Windows Webcam** on the **Use as PC Webcam — No OBS Required** card (registers `Phone2Screen Camera` per-user with no admin prompt).
3. Open **Phone2Screen** on your phone (**Send**), tap your PC (or connect via USB), and choose **Phone2Screen Camera** in **Zoom**, **Google Meet**, **Teams**, or **Discord**.

### Option 2: Phone -> PC Studio & Multi-Cam (`Studio` Mode)
1. Toggle **`Studio`** in the top bar or Receiver lobby header.
2. Open **Phone2Screen** on your phone (**Send**), pick **Camera** or **Screen** + a **Rig Preset** (`Facecam 1080p60`, `USB Ultra`, etc.), and tap your PC (or **Scan QR Code**).
3. Press **`F`** (Fullscreen) + **`O`** (Hide Controls) for clean capture, **`P`** to pause with the privacy slate, or click **`+ Open Camera Window`** for up to 4 phones.

### Option 3: Cast to Web Browser & OBS Studio (`/obs`)
1. Open **Phone2Screen** on your phone (**Send**) -> choose **Camera** or **Screen** -> tap **Cast to Web Browser**.
2. Copy the **`/obs` Clean Feed** link into an OBS Browser Source for a zero-UI auto-reconnecting feed (`?pin=`, `?fit=cover`, `?mirror=1`, `?bg=black`, `?delay=<ms>`), or open `http://<ip>:<port>` in any browser.

### Option 4: Phone Browser -> PC App (No Phone App Required)
1. Open **Phone2Screen** on your PC in **Receive**.
2. On your phone's Safari or Chrome browser, open the **`https://...`** link under **No Phone App? Use Phone Browser** (tap **Advanced → Proceed** once for the local TLS certificate) and tap **Stream Camera**.

---

## Zero-OBS Native Windows Virtual Camera & OBS Studio Sync

### Native DirectShow Virtual Webcam (`p2s_vcam.dll`)
- **1-Click Per-User Registration**: Click **Enable Windows Webcam** in the Receiver lobby (`SimpleWebcamCard`) or at the top of **Virtual Cam & OBS** (`NativeVirtualCamSection`) to register `Phone2Screen Camera` under `HKCU` without UAC/admin elevation.
- **Standby, Live & Privacy Slates**: `NativeVirtualCamNotifier` pumps 20 fps frames from the active receiver stage via shared memory (`Local\Phone2ScreenVCamSharedV1`) while live, and displays branded standby (`0`) or privacy-paused (`2`) slates otherwise.
- **CLI Helper**: Run `scripts/setup_windows_webcam.ps1 -Action Register|Unregister|Status` (add `-AddFirewallRules` in an elevated shell if needed).

### 1-Click OBS WebSocket v5 Bridge (`ObsVirtualCamSheet`)
1. In OBS Studio 28+, enable **Tools → WebSocket Server Settings** (`127.0.0.1:4455`).
2. Switch to **Studio** mode and open **Virtual Cam & OBS** (or **Virtual Cam** on the live dock) to toggle OBS Virtual Camera, provision **`Phone2Screen Clean Feed`** (`http://<ip>:<port>/obs`), toggle **Always on Top** (`WS_EX_TOPMOST`), and stream live **`PROGRAM`** / **`PREVIEW`** / **`STANDBY`** tally status back to your phone.

---

## Multi-Phone Grid, USB Plug-and-Play & Studio Tools

- **Single-Window Multi-Cam (`Solo` / `2-Up` / `4-Up`) & Multi-Window**: Primary Desktop Receivers accept up to **4 concurrent phone feeds** (`maxDesktopReceiverPeers = 4`), or launch isolated OS camera windows (`Camera 2..4` on ports `8081..8083`) via `DesktopWindowService`.
- **Zero-Config USB Auto-Bridge (`adb reverse` + `/p2s-info`) & USB Tethering**: Desktop hosts auto-forward active ports over `adb reverse`; Senders probe `http://127.0.0.1:8080..8083/p2s-info` and surface `USB Wired • Zero-Latency` peers first. USB Tethering interfaces receive `+550` NIC priority.
- **Studio Audio Routing, GPU Looks & OLED Tally**: Switch **Mic Mode** (`Voice Clean` vs `Studio Raw`), route to Windows **Virtual Audio Cables** (`Virtual Mic Ready`), boost audio (`0–200%`), align **Lip-Sync Offset (`0–500 ms`)**, apply 4x5 GPU **Studio Look Presets** + **Soft Vignette**, or enable true-black `#000000` **Battery Saver Preview** (`OledTallyView`).

---

## Customizable Keyboard Shortcuts

Customize every keybinding (or disable shortcuts) in **Settings → Keyboard Shortcuts**:

| Default Key | Action | What It Does |
| --- | --- | --- |
| `P` | Pause Camera | Freeze or resume camera feed with privacy slate (`videoPause`) |
| `V` | Camera Rig & Color | Open remote phone camera controls, Studio Looks, audio routing & lip-sync |
| `F` | Fullscreen | Enter or exit fullscreen receiver stage |
| `O` | Fullscreen Overlay | Show or hide fullscreen HUD controls |
| `M` | Mute Audio | Mute or unmute receiver audio / sender mic |
| `R` | Rotate 90° | Rotate incoming video clockwise in 90° steps |
| `H` | Mirror Video | Flip incoming video horizontally |
| `Z` | Fit / Fill Screen | Toggle letterbox fit vs edge-to-edge cover fill |
| `S` | Live Stats | Show or hide resolution, FPS, bitrate, RTT & timer pill |
| `C` | Share Text | Open live bidirectional clipboard sync sheet |
| `G` | How to Use | Open the quick-start guide |
| `X` | Stop / Disconnect | End the active stream or multi-cam session |
| `Esc` | Always Active | Exits Fullscreen even when shortcuts are disabled |

---

## Windows Release Packaging (`v0.4.0`)

Build the portable x64 `.zip` bundle (with SHA-256 checksum) and non-admin Inno Setup 6 installer (`windows/packaging/phone2screen.iss`, if `ISCC.exe` is installed):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package_windows.ps1
```

Outputs are staged in `dist/` (`Phone2Screen-v0.4.0-Windows-x64.zip`, `.sha256`, and `Phone2Screen-Setup-v0.4.0.exe` when Inno Setup 6 is available). Pass `-SkipBuild` to package an existing Release build.

---

## Troubleshooting FAQ

- **`Phone2Screen Camera` doesn't appear in Zoom/Meet/Discord?** Click **Enable Windows Webcam** in Phone2Screen (or run `scripts/setup_windows_webcam.ps1 -Action Register`), then restart your browser or call app so it rescans DirectShow devices.
- **Devices don't appear under Nearby Screens?** Ensure both devices are on the same Wi-Fi (pause VPNs), allow Phone2Screen in Windows Firewall (UDP `41234`, TCP `8080–8083`, `8443`), plug in via USB debugging, or use **Enter IP Manually** / **USB / ADB**.
- **OBS WebSocket won't connect?** Enable **Tools → WebSocket Server Settings** on port `4455` in OBS Studio 28+.

---

## For Developers (`v0.4.0`)

Phone2Screen `0.4.0` is built with **Flutter 3.50**, **Dart 3.14**, **`package:material_ui`**, manual **Riverpod 3** (zero codegen), **`flutter_webrtc`**, a native Win32 C++ **`StudioBridge`**, and DirectShow **`p2s_vcam.dll`**.

- **Key Docs**: [AGENTS.md](AGENTS.md) • [flutter-350-conventions](.agents/skills/flutter-350-conventions/SKILL.md) • [webrtc-lan-protocol](.agents/skills/webrtc-lan-protocol/SKILL.md) • [verify-phone2screen](.agents/skills/verify-phone2screen/SKILL.md)

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter analyze --fatal-infos
flutter test
flutter build windows --debug
```
