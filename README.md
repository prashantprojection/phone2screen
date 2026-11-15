# Phone2Screen v0.2

**Phone2Screen** turns 1–4 phones into low-latency LAN or USB webcams and screen broadcasters for **Windows PC**, **OBS Studio**, and **any Web Browser** — completely offline, with zero accounts, zero cloud servers, and zero watermarks.

- **Private & Offline**: Video travels peer-to-peer over your Wi-Fi, mobile hotspot, USB tethering, or ADB USB cable.
- **Studio-Ready**: Edge-to-edge Theater/OBS video stage with floating glass control docks, multi-camera grid (`Solo` / `2-Up` / `4-Up`), multi-window desktop receivers, zero-UI OBS Browser Source (`/obs`), and a non-blocking Studio Inspector drawer.
- **Bidirectional Single App**: One codebase switches in one tap between **Receive** and **Send**.

---

## Quick Start (3 Steps)

> Tap **`?` (`G`)** in the top bar anytime for the in-app visual guide.

### Phone -> PC App (Best Quality & Studio Controls)
1. Open **Phone2Screen** on your PC (starts in **Receive**).
2. Open **Phone2Screen** on your phone, switch to **Send**, and pick **Camera** or **Screen** plus a **Rig Preset** (such as `Facecam 1080p60` or `USB Ultra`).
3. Tap your PC under **Nearby Screens** — or tap **Scan QR Code** and point at your PC screen.

### Cast to Web Browser & OBS Studio
1. Open **Phone2Screen** on your phone in **Send** and choose **Camera** or **Screen**.
2. Tap **Cast to Web Browser** to start the phone's embedded web server (`http://<ip>:<port>`).
3. Copy the **`/obs` Clean Feed** link for OBS Studio, or scan the QR / open `http://<ip>:<port>` in any browser to watch live with interactive controls.

### Phone Browser -> PC App (No Phone App Required)
1. Open **Phone2Screen** on your PC in **Receive**.
2. On your phone's Safari or Chrome browser, open the **`https://...`** link under **No Phone App? Use Phone Browser** (tap **Advanced → Proceed** once for the local self-signed certificate).
3. Allow camera/mic permission and tap **Stream Camera** to send straight into the PC receiver.

---

## OBS Studio Integration

### Option A: Zero-UI Browser Source Clean Feed (`GET /obs`)
1. On your phone, go to **Send → Cast to Web Browser**.
2. Copy the **OBS Browser Source (Clean Feed)** URL (`http://<ip>:<port>/obs`) and paste it into an **OBS Studio Browser Source** (`1920×1080`).
3. Optional query parameters on `/obs`:
   - `?pin=<digits>` — included automatically when a 4-digit pairing PIN is enabled
   - `?fit=cover` — crop edge-to-edge (`object-fit: cover`) instead of letterbox fit
   - `?mirror=1` — mirror horizontally (`?mirror=1` or `?mirror=true`)
   - `?bg=black` — solid `#000000` background instead of transparent
4. Hidden cursor (`cursor: none`), H.264 priority, and automatic **1500 ms reconnect** recover cleanly if your phone stream restarts.

### Option B: PC Receiver Clean Window Mode (`B`)
1. Connect your phone(s) to the PC **Receive** app over Wi-Fi or USB for an edge-to-edge Theater/OBS stage with a floating glass control dock.
2. Press **`B`** (or click **OBS Clean** on the floating receiver dock) to hide the header, dock, and overlays for clean **OBS Window Capture**.
3. Double-click the video or press **`Esc`** (or **`B`**) to bring controls back.

---

## Multi-Phone Grid & Native Multi-Window Studio

- **Single-Window Multi-Cam (`Solo` / `2-Up` / `4-Up`)**: Desktop Receivers accept up to **4 simultaneous phone feeds** (`maxDesktopReceiverPeers = 4`), auto-upgrading the stage to **2-Up** for 2 phones and **4-Up** for 3–4 phones. Click any camera tile to select it for **Camera Rig** control, or double-click to go fullscreen.
- **Independent Multi-Window Mode**: Need separate OBS Window Capture sources per phone? Click **`+ Open Camera Window`** (lobby), **`+ Window`** (control dock), or **`+ Cam Window`** (multi-cam toolbar) on desktop to launch isolated OS receiver windows (**Camera 2..4** on ports `8081..8083`) via `DesktopWindowService`.

---

## Wired USB Tethering & `USB / ADB (127.0.0.1)` Zero-Lag Mode

1. **USB Tethering (Recommended for 20+ Mbps)**: Connect your phone via USB and enable **USB Tethering**. Phone2Screen automatically ranks USB RNDIS/CDC/NCM/Apple USB adapters above Wi-Fi (`+550` priority, `isUsbTethered`) and displays a **USB Wired • Ultra-Low Latency** badge. Pair with the **`USB Ultra`** preset (`1080p`, `60 FPS`, `20 Mbps`; bitrate slider supports up to `25 Mbps`).
2. **USB / ADB Loopback (`127.0.0.1`)**: With Android USB debugging enabled, run:
   ```powershell
   adb reverse tcp:8080 tcp:8080
   ```
   Then tap **USB / ADB** under **Nearby Screens** on the **Send** screen to stream directly over `127.0.0.1:8080`.

---

## Streamer Rig Controls, Framing, Tally & Persistence

- **Non-Blocking Studio Inspector & Remote Tripod Camera Rig (`V` / Camera Rig)**: Opens as a right-side Studio Inspector drawer on desktop (keeping the live video visible as you adjust controls) or a bottom sheet on phones. Control your mounted phone live over the `phone2screen-control` DataChannel (`cam_ctrl`/`cam_state`) without touching the phone: **Flip Lens**, **Torch**, **Mic Mute**, **AF Lock**, **1x / 2x / 3x Zoom** + slider, and **Exposure (`-2.0..+2.0 EV`)** *(hardware lens controls require a native mobile camera stream)*.
- **Studio Framing & GPU Color Look**: Adjust per-camera **Free / 16:9 / 9:16 / 4:3** aspect crop, **3x3 Grid** (Rule of Thirds), **Digital Zoom (`1.0x–3.0x`)**, **Pan X / Y**, **Brightness**, **Contrast**, and **Saturation**, or tap **Reset Studio Look**.
- **True-Black OLED On-Air Tally (`OledTallyView`)**: Toggle **Battery Saver Preview** (in **Settings → Video & Audio** or the live **Battery Saver** pill) to switch the phone into a pure `#000000` OLED-safe **ON AIR** tally screen—automatically hiding the top shell header with floating glass live controls, 30-second anti-burn-in pixel shift, elapsed timer, stream summary, and **Wake Preview** / double-tap wake.
- **Streamer Camera Presets**: 1-tap presets on **Send** — `Facecam 1080p60`, `Overhead 4K`, `USB Ultra`, `Vertical Cam`, and `Eco 720p` — plus custom saved presets in **Settings → Streamer Presets**.
- **Persistent Settings**: Theme, video/audio settings, custom presets, keyboard shortcuts, and your last connected receiver (**Reconnect to ...** quick tile on **Send**) are automatically saved locally as JSON with zero cloud sign-in.

---

## Customizable Keyboard Shortcuts

Customize every keybinding (or disable shortcuts) in **Settings → Keyboard Shortcuts**:

| Default Key | Action | What It Does |
| --- | --- | --- |
| `V` | Camera Rig & Color | Open remote phone camera controls, aspect crop & GPU color grading |
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

- **Devices don't appear under Nearby Screens?** Ensure both devices are on the same Wi-Fi (avoid Guest Wi-Fi client isolation and pause VPNs), allow **Phone2Screen** through Windows Defender Firewall, or use **Enter IP Manually** / **USB / ADB**.
- **Why does `https://` show a browser warning in Phone Browser -> PC?** Browsers require HTTPS for `getUserMedia` camera access. Because Phone2Screen runs 100% offline, it generates an ephemeral local TLS certificate; tap **Advanced → Proceed** once.
- **Need access control on shared Wi-Fi?** Set a **4-Digit Pairing PIN** under **Settings → Advanced & Security**.

---

## For Developers (`v0.2.0`)

Phone2Screen `0.2.0` is built with **Flutter 3.50**, **Dart 3.14**, **`package:material_ui`**, manual **Riverpod 3** (zero codegen), and **`flutter_webrtc`**.

- **Key Docs**: [AGENTS.md](AGENTS.md) • [flutter-350-conventions](.agents/skills/flutter-350-conventions/SKILL.md) • [webrtc-lan-protocol](.agents/skills/webrtc-lan-protocol/SKILL.md) • [verify-phone2screen](.agents/skills/verify-phone2screen/SKILL.md)

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter analyze --fatal-infos
flutter test
flutter build windows --debug
```
