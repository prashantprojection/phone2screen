# Phone2Screen

## What is Phone2Screen?

**Phone2Screen** lets you wirelessly turn your phone into a live camera, share your phone or PC screen, or watch your camera/screen in any web browser on the same Wi-Fi.

- **Free & Private**: Video travels directly between your devices on your own Wi-Fi — never uploaded to the internet.
- **100% Offline**: Works with no internet connection and **zero accounts or cloud logins**.
- **Two-Way**: One app works as both a **Receive** screen and a **Send** camera/screen broadcaster.

---

## How to Use (3 Simple Ways)

> Need a quick reminder inside the app? Tap the **`?` (How to Use)** button in the top bar at any time.

### Way 1: Phone to PC App (Best Quality)
Use this when Phone2Screen is installed on both your phone and your PC (or two phones/PCs):
1. Open **Phone2Screen** on your PC (it starts in the **Receive** tab).
2. Open **Phone2Screen** on your phone, switch to the **Send** tab, and choose **Camera** or **Screen** under **What to Share**.
3. Tap your PC under **Nearby Screens** — or tap **Scan QR Code** and point at your PC screen. Your video appears right away!

### Way 2: Watch in Any Web Browser (Zero App Install on Viewer)
Share your phone or PC camera/screen with any laptop, smart TV, or tablet browser:
1. Open **Phone2Screen** on the device you want to share from, switch to **Send**, and choose **Camera** or **Screen**.
2. Tap **Cast to Web Browser**. Phone2Screen displays a plain `http://...` link and QR code.
3. Scan the QR code or type that `http://` address into any browser on the same Wi-Fi to watch live — no app install required on the viewer.

### Way 3: Phone Browser to PC App (No Android App Needed)
Send your phone's camera straight into the Phone2Screen PC app using just Safari or Chrome:
1. Open **Phone2Screen** on your PC in the **Receive** tab.
2. On your phone's browser, open the **`https://...`** link shown under **No Phone App? Use Phone Browser** (or scan the QR code).
3. Your browser will show a one-time local security notice — tap **Advanced → Proceed** (or *Show Details → Visit this website*), allow camera/mic permission, and tap **Stream Camera**.

---

## Handy Controls & Tips

- **Switch Camera or Screen Live**: While streaming, tap **Flip** (front/back camera), **Screen / Camera** to switch live without hanging up, **Mute / Unmute**, or **Torch** (phone flashlight). On the receiving screen, use **Fit / Fill**, **Rotate**, **Mirror**, or **Fullscreen**.
- **Immersive Fullscreen & Keyboard Shortcuts**: In **Fullscreen**, press `Esc` to exit or tap the video (or click **Hide Controls**) to clear overlays. Customize **Keyboard Shortcuts** in **Settings → Keyboard Shortcuts** (defaults: `F` Fullscreen, `O` Toggle Overlay, `M` Mute, `R` Rotate, `H` Mirror, `Z` Fit/Fill, `S` Stats, `C` Share Text, `G` Guide, `X` Disconnect).
- **Share Text (Clipboard Sync)**: Tap **Share Text** during any session to send website links, notes, or passwords back and forth between devices in one tap. Turn on **Auto-Copy Shared Text** in **Settings → Advanced & Security** to copy incoming text straight to your clipboard.
- **Battery Saver Preview**: Turn on **Battery Saver Preview** in **Settings → Video & Audio** to pause the preview video on your sending device while streaming — keeping your phone cool and saving battery while your stream stays live.
- **No Wi-Fi? Use Your Phone Hotspot**: Turn on your phone's Personal Hotspot and connect your PC or TV to it. Phone2Screen streams directly across that local connection — **it works offline and uses zero mobile data!**

### Troubleshooting FAQ

- **Devices don't see each other under Nearby Screens?**
  - Make sure both devices are on the **exact same Wi-Fi** (avoid Guest Wi-Fi networks, which isolate devices from each other, and temporarily pause any VPN).
  - If automatic discovery is blocked by your router, tap **Enter IP Manually** on the **Send** tab and type the IP shown on the **Receive** screen.
- **Windows asks about Firewall access?**
  - Click **Allow access** when Windows Defender Firewall prompts for **Phone2Screen** so nearby devices and browsers can connect over Wi-Fi.
- **Why does the browser show a security warning on `https://` in Way 3?**
  - Mobile browsers require `https://` before allowing camera access. Because Phone2Screen runs completely offline without cloud certificates, it creates a private local certificate on your PC. Tapping **Advanced → Proceed** once simply tells your browser to trust your own PC on your home Wi-Fi.
- **Need to protect your receiver from others on shared Wi-Fi?**
  - Open **Settings → Advanced & Security** and set a **4-digit PIN**.

---

## For Developers

Phone2Screen v0.1 is a single adaptive codebase built with **Flutter 3.50**, **Dart 3.14**, **`package:material_ui`**, manual **Riverpod 3** (zero codegen), and **`flutter_webrtc`**.

- **Architecture Constraints**: `package:material_ui/material_ui.dart` only (with `MaterialUiCompatibilityBridge`), Dart 3.14 `class const` primary constructors and dot shorthands, native `ResponsiveContext` layout (no `flutter_screenutil`), zero `build_runner`/`freezed`/`json_serializable`, and a strict **`< 350` LOC** cap on every `.dart` and `.kt` file.
- **Key Docs & Skills**:
  - [AGENTS.md](AGENTS.md) — Workspace rules, conventions, and architecture overview
  - [flutter-350-conventions](.agents/skills/flutter-350-conventions/SKILL.md) — Flutter 3.50 / Dart 3.14 coding standards
  - [webrtc-lan-protocol](.agents/skills/webrtc-lan-protocol/SKILL.md) — UDP `41234` (`P2S_V1`), `/ws` signaling, early ICE buffering, `phone2screen-control` DataChannel, and Browser Web Companion
  - [verify-phone2screen](.agents/skills/verify-phone2screen/SKILL.md) — Verification runbook

### Build & Verification Commands

```powershell
# Install dependencies
flutter pub get

# Run locally (Windows Desktop or Android)
flutter run -d windows
flutter run -d <android-device-id>

# Verification gates
flutter analyze --fatal-infos
flutter test
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
flutter build windows --debug
```
