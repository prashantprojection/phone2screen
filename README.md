# Phone2Screen v0.3

**Phone2Screen** turns 1–4 phones into low-latency LAN or USB webcams and screen broadcasters for **Windows PC**, **OBS Studio**, and **any Web Browser** — completely offline, with zero accounts, zero cloud servers, and zero watermarks.

- **Private & Offline**: Video travels peer-to-peer over your Wi-Fi, mobile hotspot, USB tethering, or zero-config ADB USB cable.
- **Studio-Ready**: Edge-to-edge Theater/OBS video stage with floating glass control docks, multi-camera grid (`Solo` / `2-Up` / `4-Up`), multi-window desktop receivers, zero-UI OBS Browser Source (`/obs`), 1-click **OBS WebSocket v5** sync, and non-blocking Studio Inspector drawers.
- **Bidirectional Single App**: One codebase switches in one tap between **Receive** and **Send**.

---

## Quick Start (3 Steps)

> Tap **`?` (`G`)** in the top bar anytime for the in-app visual guide.

### Phone -> PC App (Best Quality & Studio Controls)
1. Open **Phone2Screen** on your PC (starts in **Receive**).
2. Open **Phone2Screen** on your phone, switch to **Send**, and pick **Camera** or **Screen** plus a **Rig Preset** (such as `Facecam 1080p60` or `USB Ultra`).
3. Tap your PC under **Nearby Screens** — or plug in via USB, or tap **Scan QR Code** and point at your PC screen.

### Cast to Web Browser & OBS Studio
1. Open **Phone2Screen** on your phone in **Send** and choose **Camera** or **Screen**.
2. Tap **Cast to Web Browser** to start the phone's embedded web server (`http://<ip>:<port>`).
3. Copy the **`/obs` Clean Feed** link for OBS Studio, or scan the QR / open `http://<ip>:<port>` in any browser to watch live with interactive controls.

### Phone Browser -> PC App (No Phone App Required)
1. Open **Phone2Screen** on your PC in **Receive**.
2. On your phone's Safari or Chrome browser, open the **`https://...`** link under **No Phone App? Use Phone Browser** (tap **Advanced → Proceed** once for the local self-signed certificate).
3. Allow camera/mic permission and tap **Stream Camera** to send straight into the PC receiver.

---

## Virtual Camera & 1-Click OBS Studio Integration

### Option A: 1-Click OBS WebSocket v5 Bridge & Virtual Cam (`ObsVirtualCamSheet`)
1. In OBS Studio 28+, enable **Tools → WebSocket Server Settings** (`127.0.0.1:4455`).
2. On Windows desktop **Receive**, click **Virtual Cam & OBS** in the lobby header (or **Virtual Cam** on the floating dock) to open the **ObsVirtualCamSheet** inspector:
   - **Virtual Webcam & 1-Click OBS Bridge**: Lists detected DirectShow virtual cameras (such as **OBS Virtual Camera**), toggles **Start / Stop Virtual Camera**, and provisions **`Phone2Screen Clean Feed`** (`http://<ip>:<port>/obs`) directly into your active OBS scene with one click.
   - **Always on Top**: Pins the desktop receiver window (`WS_EX_TOPMOST`) above borderless games or studio tools.
   - **Live Tally Sync**: Streams OBS **`PROGRAM`** (`ON AIR`), **`PREVIEW`**, and **`STANDBY`** scene status back to your phone in real time.

### Option B: Zero-UI Browser Source Clean Feed (`GET /obs`)
1. Copy the **OBS Browser Source (Clean Feed)** URL (`http://<ip>:<port>/obs`) from **Cast to Web Browser** (or provision it automatically via OBS WebSocket v5).
2. Optional query parameters on `/obs`:
   - `?pin=<digits>` — included automatically when a 4-digit pairing PIN is enabled
   - `?fit=cover` — crop edge-to-edge (`object-fit: cover`) instead of letterbox fit
   - `?mirror=1` — mirror horizontally (`?mirror=1` or `?mirror=true`)
   - `?bg=black` — solid `#000000` background instead of transparent
   - `?delay=<ms>` — Web Audio lip-sync delay (`0–1000 ms`) via `DelayNode`
3. Hidden cursor (`cursor: none`), H.264 priority, and automatic **1500 ms reconnect** recover cleanly if your phone stream restarts.

### Option C: PC Receiver Clean Window Mode (`B`)
1. Connect your phone(s) to the PC **Receive** app over Wi-Fi or USB for an edge-to-edge Theater/OBS stage with a floating glass control dock.
2. Press **`B`** (or click **OBS Clean** on the floating receiver dock) to hide the header, dock, and overlays for clean **OBS Window Capture**.
3. Double-click the video or press **`Esc`** (or **`B`**) to bring controls back.

---

## Multi-Phone Grid & Native Multi-Window Studio

- **Single-Window Multi-Cam (`Solo` / `2-Up` / `4-Up`)**: Desktop Receivers accept up to **4 simultaneous phone feeds** (`maxDesktopReceiverPeers = 4`), auto-upgrading the stage to **2-Up** for 2 phones and **4-Up** for 3–4 phones. Click any camera tile to select it for **Camera Rig** control, or double-click to go fullscreen.
- **Independent Multi-Window Mode**: Need separate OBS Window Capture sources per phone? Click **`+ Open Camera Window`** (lobby), **`+ Window`** (control dock), or **`+ Cam Window`** (multi-cam toolbar) on desktop to launch isolated OS receiver windows (**Camera 2..4** on ports `8081..8083`) via `DesktopWindowService`.

---

## Zero-Config USB Plug-and-Play & Wired Tethering

1. **Zero-Config USB Auto-Bridge (`adb reverse` + `GET /p2s-info`)**: When an Android phone with USB debugging is plugged into a Windows desktop Receiver, Phone2Screen automatically runs `adb reverse tcp:<port> tcp:<port>` (including secondary camera window ports) and displays a **USB Auto-Bridge Active** banner. On the phone's **Send** screen, `UsbBridgeService` probes `http://127.0.0.1:8080..8083/p2s-info` and pins the PC at the top of **Nearby Screens** as **`USB Wired • Zero-Latency`** — or tap **USB / ADB** anytime.
2. **USB Tethering (20+ Mbps)**: Enable **USB Tethering** to rank RNDIS/CDC/NCM/Apple USB adapters above Wi-Fi (`+550` priority, `isUsbTethered`) with a **USB Wired • Ultra-Low Latency** badge. Pair with **`USB Ultra`** (`1080p`, `60 FPS`, `20 Mbps`; slider up to `25 Mbps`).

---

## Studio Audio Routing, Looks, Tally & Persistence

- **Studio Audio, Virtual Mic & Lip-Sync**: Under **Camera Rig & Studio Look** (`V`), switch **Mic Mode** live between **`Voice Clean`** (echo cancellation + noise suppression + AGC) and **`Studio Raw`** (unprocessed music/ASMR capture), route playback to Windows **Virtual Audio Cables** (VB-Audio, VoiceMeeter, Wave Link, Sonar) tagged **`Virtual Mic Ready`**, adjust **Audio Boost (`0–200%`)**, and align **Lip-Sync Offset (`0–500 ms`)** synced to OBS Browser Source (`SetInputAudioSyncOffset`) and `/obs?delay=<ms>`.
- **1-Tap GPU Studio Look Presets & Soft Vignette**: Apply lightweight 4x5 GPU color grades — **`Natural`**, **`Stream Punch`**, **`Warm Keylight`**, **`Cool Cyber`**, and **`Noir B&W`** — plus **`Soft Vignette`**, alongside **Free / 16:9 / 9:16 / 4:3** crop, **3x3 Grid**, **Digital Zoom (`1.0x–3.0x`)**, **Pan X / Y**, and **Brightness / Contrast / Saturation**.
- **Remote Phone Camera Rig (`V`)**: Opens as a non-blocking right-side Studio Inspector drawer on desktop or a bottom sheet on phones to control **Flip Lens**, **Torch**, **Mic Mute**, **AF Lock**, **1x / 2x / 3x Zoom**, and **Exposure (`-2.0..+2.0 EV`)** *(hardware lens controls require a native mobile camera stream)*.
- **Live OBS `ON AIR` / `PREVIEW` / `STANDBY` OLED Tally (`OledTallyView`)**: Toggle **Battery Saver Preview** (in **Settings → Video & Audio** or the live **Battery Saver** pill) for a pure `#000000` OLED-safe tally screen with 30-second anti-burn-in pixel shift, elapsed timer, active OBS scene label (`OBS • <scene>`), live status color (**`ON AIR`** red, **`PREVIEW`** green, **`STANDBY`** cyan), and **Wake Preview** / double-tap wake.
- **Platform Scope**: Core LAN/WebRTC streaming, GPU Studio Looks, `/obs?delay=<ms>`, and live OLED Tally run across **Windows**, **Android**, and **Web**; DirectShow virtual camera scan, Win32 WaveOut routing, `Always on Top`, and host `adb reverse` auto-bridging are native **Windows desktop** studio capabilities (Web remains Sender-only).
- **Persistent Settings**: Theme, video/audio settings, OBS WebSocket config, audio routing config, custom presets, keyboard shortcuts, and your last connected receiver (**Reconnect to ...**) are saved locally as JSON with zero cloud sign-in.

---

## Customizable Keyboard Shortcuts

Customize every keybinding (or disable shortcuts) in **Settings → Keyboard Shortcuts**:

| Default Key | Action | What It Does |
| --- | --- | --- |
| `V` | Camera Rig & Color | Open remote phone camera controls, Studio Looks, audio routing & lip-sync |
| `B` | OBS Clean View | Hide all window UI for clean OBS Window Capture |
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
| `Esc` | Always Active | Exits OBS Clean View or Fullscreen even when shortcuts are disabled |

---

## Troubleshooting FAQ

- **Devices don't appear under Nearby Screens?** Ensure both devices are on the same Wi-Fi (avoid Guest Wi-Fi client isolation and pause VPNs), allow **Phone2Screen** through Windows Defender Firewall, plug in over USB with USB debugging enabled, or use **Enter IP Manually** / **USB / ADB**.
- **OBS Virtual Camera or WebSocket won't connect?** Open **OBS Studio 28+** on PC and enable **Tools → WebSocket Server Settings** on port `4455` (matching any password in **Virtual Cam & OBS**).
- **Why does `https://` show a browser warning in Phone Browser -> PC?** Browsers require HTTPS for `getUserMedia` camera access. Because Phone2Screen runs 100% offline, it generates an ephemeral local TLS certificate; tap **Advanced → Proceed** once.
- **Need access control on shared Wi-Fi?** Set a **4-Digit Pairing PIN** under **Settings → Advanced & Security**.

---

## For Developers (`v0.3.0`)

Phone2Screen `0.3.0` is built with **Flutter 3.50**, **Dart 3.14**, **`package:material_ui`**, manual **Riverpod 3** (zero codegen), **`flutter_webrtc`**, and a native Win32 C++ **`StudioBridge`**.

- **Key Docs**: [AGENTS.md](AGENTS.md) • [flutter-350-conventions](.agents/skills/flutter-350-conventions/SKILL.md) • [webrtc-lan-protocol](.agents/skills/webrtc-lan-protocol/SKILL.md) • [verify-phone2screen](.agents/skills/verify-phone2screen/SKILL.md)

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter analyze --fatal-infos
flutter test
flutter build windows --debug
```
