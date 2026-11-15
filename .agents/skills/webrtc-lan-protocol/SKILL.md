---
name: webrtc-lan-protocol
description: Specification for Phone2Screen v0.5 LAN & USB NIC ranking (including iPhone 172.20.10.* USB Personal Hotspot), encrypted P2S1 QR pairing (QrCipher), ADB reverse + GET /p2s-info discovery, UDP 41234 P2S_V1 discovery, multi-peer /ws SignalingMessage JSON handshake, early ICE buffering, sub-second auto-reconnect, phone2screen-control DataChannel (ping/pong, clipboard, cam_ctrl/cam_state with videoPause, tally), OBS WebSocket v5 sync, GET / Browser Web Companion, and GET /obs?delay=<ms> OBS Clean Feed.
---

# WebRTC, USB & LAN Signaling Protocol (v0.5)

Phone2Screen operates completely offline on a local network (USB tethering, iPhone USB Personal Hotspot, ADB reverse loopback, Wi-Fi, Ethernet, or mobile hotspot) without cloud relay servers.

## 1. NIC Ranking & USB Tethering Priority (`NetworkInterfaceInfo`)

- Enumerate local IPv4 addresses via `NetworkInterface.list(type: InternetAddressType.IPv4)`.
- Filter out loopback (`127.0.0.0/8`), link-local (`169.254.0.0/16`), and virtual/tunnel adapters (e.g., `vEthernet`, `WSL`, `Hyper-V`, `Docker`, `VMware`, `VirtualBox`, `vbox`, `tun`, `tap`, `wg`, `utun`, `tailscale`, `wireguard`).
- `isUsbTetherInterface(name, address)` detects non-virtual USB tethering interfaces (`rndis`, `usb`, `ncm`, `cdc`, `apple mobile device`, `iphone`, Android `192.168.42.*`, and Apple iPhone USB Personal Hotspot `172.20.10.*`) and tags `NetworkInterfaceInfo.isUsbTethered = true`.
- `scoreNetworkInterface` (`lib/services/network/network_address_io.dart`) ranks adapters:
  - USB tethering (Android RNDIS & iPhone USB Personal Hotspot): **`+550`** (highest priority — dedicated wired link with minimal jitter)
  - Wi-Fi (`wlan`, `wi-fi`, `wifi`, `wireless`, `wlp*`, `en0`): `+300` (`+150` bonus for active OS Wi-Fi IP)
  - Physical Ethernet (`eth*`, `ethernet`, `en*`): `+250`
  - RFC1918 subnet bonus: `192.168.*` `+120`, `10.*` `+100`, `172.16-31.*` `+90`
  - Virtual/tunnel adapters: **`-1000`**
- **Zero-Config ADB USB Auto-Bridge (`UsbBridgeService` & `GET /p2s-info`)**:
  - Desktop hosts run `adb reverse tcp:<port> tcp:<port>` across active primary and secondary camera ports (`SessionHostFlow` & `MultiCamNotifier`).
  - `GET /p2s-info` (`StreamConstants.usbInfoPath`) returns JSON `{ "magic": "P2S_V1", "ip": "127.0.0.1", "port": <httpPort>, "httpsPort"?: <httpsPort>, "sessionId", "deviceName", "requiresPin", "mode" }`.
  - Senders probe `http://127.0.0.1:8080..8083/p2s-info` directly (`findProxy = 'DIRECT'`, guarded under `FLUTTER_TEST` unless `allowInTestOverride: true`) and list `isUsbLoopback` peers first in `allDiscoveredPeersProvider`, or connect manually via **USB / ADB**.

## 2. Encrypted App-Only QR Pairing (`QrCipher`, `P2S1.`)

- `lib/core/utils/sha256.dart` adds pure-Dart RFC 2104 `hmacSha256(key, message)`.
- `lib/core/utils/qr_cipher.dart` implements `QrCipher` (`tokenPrefix = 'P2S1.'`):
  - Generates a 12-byte random nonce (or deterministic `nonceOverride` in tests), derives `P2S1-ENC` and `P2S1-MAC` keys via `hmacSha256`, encrypts UTF-8 JSON with a counter-mode HMAC-SHA256 keystream XOR, appends a 16-byte MAC tag verified in constant time, and encodes `nonce || ciphertext || tag` as unpadded `base64Url`.
  - `SignalingData.toQrString` / `SignalingData.fromQrString` (`lib/models/signaling_data.dart`) strictly enforce `P2S1.` tokens (rejecting cleartext JSON/URLs or tampered bytes with `FormatException`), preventing external camera/QR apps from reading receiver IPs, ports, session IDs, or PIN flags.
  - `QrPairingCard` caches `_qrData` per endpoint (`didUpdateWidget` compares `SignalingData`) to prevent QR flicker across unrelated rebuilds.

## 3. UDP LAN Discovery (`41234`, `P2S_V1`)

- Receiver (host) opens a `RawDatagramSocket` (`broadcastEnabled: true` on ephemeral source port) and broadcasts every `2s` (`StreamConstants.discoveryInterval`) on UDP port `41234` (`StreamConstants.udpDiscoveryPort`).
- Packet format: UTF-8 JSON containing `magic: 'P2S_V1'` and `SignalingData` fields (`ip`, `port`, `httpsPort`, `sessionId`, `deviceName`, `requiresPin`).
- Sender listens on `InternetAddress.anyIPv4` port `41234`, validates `P2S_V1`, updates `DiscoveredPeer(endpoint, lastSeen)`, and expires peers unseen for `> 8s` (`StreamConstants.peerStaleTimeout`).

## 4. HTTP + Multi-Peer WebSocket Signaling (`/ws`)

- Host binds an `HttpServer` on the first free port in `preferredPort..8095` (`defaultSignalingPort`..`maxSignalingPort`, or `0` for ephemeral in tests).
- **Slot limits (`maxPeers`)**:
  - Primary Desktop Receiver: `maxPeers = StreamConstants.maxDesktopReceiverPeers` (`4`), enabling up to 4 phones in one window.
  - Mobile Receiver, Secondary Desktop Camera Windows (`--camera-slot > 1`), and Web Broadcast (`viewSenderStream`): `maxPeers = StreamConstants.maxActivePeers` (`1`) to protect Tier-3 mobile encoders/decoders.
  - Excess WebSocket upgrade attempts receive `{ "type": "error", ... }` and a policy-violation close.
- **Peer Routing (`SignalingEventHub`)**:
  - Each authenticated WebSocket client gets a unique `peerId` (`peer-1`, `peer-2`, ...) and `isPrimary` flag.
  - `welcome` payload includes `deviceName` and `peerId`.
  - `SignalingServerService.peerMessages` (`PeerSignalingEvent`) and `peerConnectionEvents` (`PeerConnectionEvent`) tag every event with `peerId` and `isPrimary` (while `messages`/`clientConnectionEvents` continue mirroring `isPrimary` events).
  - `send(message, peerId: peerId)` and `disconnectClient(reason, peerId)` target a specific peer without leaking frames to other connected cameras.
- **Envelope & Handshake**:
  ```json
  {
    "type": "hello | welcome | offer | answer | ice | bye | error",
    "sessionId": "<uuid-or-short-id>",
    "payload": {}
  }
  ```
  1. Client connects to `/ws` and sends `hello` (`sessionId`, optional `pin`, `deviceName`, `role`).
  2. Server verifies PIN (`validateHelloHandshake`); replies `welcome` (with `peerId`) or `error` and closes.
  3. Offerer sends `offer` (H.264 prioritized first on `m=video`); Answerer replies `answer`.
  4. Both sides trickle `ice` candidates and send `bye` on graceful disconnect.

## 5. Early ICE Candidate Buffering

- WebRTC `ice` messages can arrive before `setRemoteDescription` completes.
- Always queue incoming ICE candidates until `remoteDescriptionSet == true`, then flush buffered candidates in order immediately after `setRemoteDescription`.
- Clear the buffer on session reset/disconnect so stale candidates never leak into a new session.

## 6. Control DataChannel (`phone2screen-control`)

- Reliable ordered `RTCDataChannel` labeled `phone2screen-control` (`StreamConstants.controlChannelLabel`).
- JSON message kinds (`DataChannelHelper`):
  - `ping`: `{ "kind": "ping", "ts": <epochMs>, "rtt"?: <ms> }` sent at `1 Hz` (`StreamConstants.pingInterval`).
  - `pong`: `{ "kind": "pong", "ts": <echoedTs> }` replied immediately to measure clock-skew-free RTT `latencyMs`.
  - `clipboard`: `{ "kind": "clipboard", "text": "<content>", "ts": <epochMs> }` synced bidirectionally (`ClipboardItem`).
  - `cam_ctrl` (Receiver -> Sender):
    ```json
    {
      "kind": "cam_ctrl",
      "cmd": "flip | torch | micMute | zoom | exposure | focusLock | voiceMode | videoPause",
      "value": 2.0,
      "enabled": true
    }
    ```
    Parsed safely via `RemoteCameraCommand.tryFromJson`; executed via `CameraControlService.applyCommand`. `voiceMode` toggles live mic DSP (`echoCancellation`, `noiseSuppression`, `autoGainControl`); `videoPause` freezes outgoing video tracks on the privacy slate.
  - `cam_state` (Sender -> Receiver, emitted on open and after changes):
    ```json
    {
      "kind": "cam_state",
      "lens": "front | back",
      "torchOn": false,
      "micMuted": false,
      "zoom": 1.0,
      "minZoom": 1.0,
      "maxZoom": 5.0,
      "exposureOffset": 0.0,
      "focusLocked": false,
      "controlsSupported": true,
      "voiceClean": true,
      "videoPaused": false
    }
    ```
    Parsed safely with finite/clamped bounds via `RemoteCameraState.tryFromJson`.
  - **Sub-Second Auto-Reconnect (`SessionSenderFlow`)**: On unexpected WebSocket/peer drop during an active stream, transitions to `SessionPhase.reconnecting`, waits `650 ms`, probes USB loopback (`UsbBridgeService`) first, and retries once before falling back to `.failed`.
  - `tally` (Receiver -> Sender, emitted on control channel open, OBS scene/item updates, or multi-cam focus changes):
    ```json
    {
      "kind": "tally",
      "state": "program | preview | standby | off",
      "scene": "Scene 1"
    }
    ```
    Parsed via `LiveTallyMessage.tryFromJson`; driven by `ObsSyncNotifier` (`ObsWebSocketService`, OBS WebSocket v5 `rpcVersion: 1` with pure-Dart SHA-256 `computeObsWebSocketAuth`) or local `MultiCamNotifier` slot focus when OBS is disconnected.

## 7. Browser Web Companion (`GET /`) & OBS Clean Feed (`GET /obs`)

- `GET /` (`buildWebCompanionHtml`): Self-contained HTML5/JS companion supporting `sendToReceiver` (Receiver hosts `http://<ip>:8080` + companion TLS `https://<ip>:8443` for browser `getUserMedia`/`getDisplayMedia`) and `viewSenderStream` (Sender hosts plain `http://<ip>:8080` for live `<video autoplay playsinline>`). Includes Fit/Fill, Rotate 90°, Mirror, RTT stats toggle, clipboard drawer, and browser `cam_ctrl`/`cam_state` (`flip` + `micMute`).
- `GET /obs` (`buildObsCleanFeedHtml`, `StreamConstants.obsCleanFeedPath`): Zero-UI full-bleed HTML5/WebRTC page designed for **OBS Studio Browser Source**:
  - `cursor: none`, `<video id="v" autoplay playsinline>`, transparent canvas by default.
  - Supported URL query parameters: `?pin=<digits>`, `?fit=cover`, `?mirror=1` (or `true`), `?bg=black`, `?delay=<ms>` (clamped `0..1000`, attaches Web Audio `AudioContext` + `DelayNode` with `v.muted = true` to avoid dry bleed).
  - Uses H.264 SDP priority (`preferH264`), early ICE buffering, DataChannel `ping -> pong` heartbeat replies, and automatic **1500 ms** reconnect (`scheduleReconnect`) on disconnect/error.
