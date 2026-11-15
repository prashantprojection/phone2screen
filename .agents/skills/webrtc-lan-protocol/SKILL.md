---
name: webrtc-lan-protocol
description: Specification for Phone2Screen v0.2 LAN & USB NIC ranking, UDP 41234 P2S_V1 discovery, multi-peer /ws SignalingMessage JSON handshake, early ICE buffering, phone2screen-control DataChannel (ping/pong, clipboard, cam_ctrl/cam_state), GET / Browser Web Companion, and GET /obs OBS Clean Feed.
---

# WebRTC, USB & LAN Signaling Protocol (v0.2)

Phone2Screen operates completely offline on a local network (USB tethering, ADB reverse loopback, Wi-Fi, Ethernet, or mobile hotspot) without cloud relay servers.

## 1. NIC Ranking & USB Tethering Priority (`NetworkInterfaceInfo`)

- Enumerate local IPv4 addresses via `NetworkInterface.list(type: InternetAddressType.IPv4)`.
- Filter out loopback (`127.0.0.0/8`), link-local (`169.254.0.0/16`), and virtual/tunnel adapters (e.g., `vEthernet`, `WSL`, `Hyper-V`, `Docker`, `VMware`, `VirtualBox`, `vbox`, `tun`, `tap`, `wg`, `utun`, `tailscale`, `wireguard`).
- `isUsbTetherInterface(name, address)` detects non-virtual USB tethering interfaces (`rndis`, `usb`, `ncm`, `cdc`, `apple mobile device`, `iphone`, or `192.168.42.*`) and tags `NetworkInterfaceInfo.isUsbTethered = true`.
- `scoreNetworkInterface` (`lib/services/network/network_address_io.dart`) ranks adapters:
  - USB tethering: **`+550`** (highest priority — dedicated wired link with minimal jitter)
  - Wi-Fi (`wlan`, `wi-fi`, `wifi`, `wireless`, `wlp*`, `en0`): `+300` (`+150` bonus for active OS Wi-Fi IP)
  - Physical Ethernet (`eth*`, `ethernet`, `en*`): `+250`
  - RFC1918 subnet bonus: `192.168.*` `+120`, `10.*` `+100`, `172.16-31.*` `+90`
  - Virtual/tunnel adapters: **`-1000`**
- **ADB USB Loopback**: Senders can also connect directly to `127.0.0.1` via the **USB / ADB** quick action when `adb reverse tcp:8080 tcp:8080` is active.

## 2. UDP LAN Discovery (`41234`, `P2S_V1`)

- Receiver (host) opens a `RawDatagramSocket` (`broadcastEnabled: true` on ephemeral source port) and broadcasts every `2s` (`StreamConstants.discoveryInterval`) on UDP port `41234` (`StreamConstants.udpDiscoveryPort`).
- Packet format: UTF-8 JSON containing `magic: 'P2S_V1'` and `SignalingData` fields (`ip`, `port`, `httpsPort`, `sessionId`, `deviceName`, `requiresPin`).
- Sender listens on `InternetAddress.anyIPv4` port `41234`, validates `P2S_V1`, updates `DiscoveredPeer(endpoint, lastSeen)`, and expires peers unseen for `> 8s` (`StreamConstants.peerStaleTimeout`).

## 3. HTTP + Multi-Peer WebSocket Signaling (`/ws`)

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

## 4. Early ICE Candidate Buffering

- WebRTC `ice` messages can arrive before `setRemoteDescription` completes.
- Always queue incoming ICE candidates until `remoteDescriptionSet == true`, then flush buffered candidates in order immediately after `setRemoteDescription`.
- Clear the buffer on session reset/disconnect so stale candidates never leak into a new session.

## 5. Control DataChannel (`phone2screen-control`)

- Reliable ordered `RTCDataChannel` labeled `phone2screen-control` (`StreamConstants.controlChannelLabel`).
- JSON message kinds (`DataChannelHelper`):
  - `ping`: `{ "kind": "ping", "ts": <epochMs>, "rtt"?: <ms> }` sent at `1 Hz` (`StreamConstants.pingInterval`).
  - `pong`: `{ "kind": "pong", "ts": <echoedTs> }` replied immediately to measure clock-skew-free RTT `latencyMs`.
  - `clipboard`: `{ "kind": "clipboard", "text": "<content>", "ts": <epochMs> }` synced bidirectionally (`ClipboardItem`).
  - `cam_ctrl` (Receiver -> Sender):
    ```json
    {
      "kind": "cam_ctrl",
      "cmd": "flip | torch | micMute | zoom | exposure | focusLock",
      "value": 2.0,
      "enabled": true
    }
    ```
    Parsed safely via `RemoteCameraCommand.tryFromJson`; executed via `CameraControlService.applyCommand`.
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
      "controlsSupported": true
    }
    ```
    Parsed safely with finite/clamped bounds via `RemoteCameraState.tryFromJson`.

## 6. Browser Web Companion (`GET /`) & OBS Clean Feed (`GET /obs`)

- `GET /` (`buildWebCompanionHtml`): Self-contained HTML5/JS companion supporting `sendToReceiver` (Receiver hosts `http://<ip>:8080` + companion TLS `https://<ip>:8443` for browser `getUserMedia`/`getDisplayMedia`) and `viewSenderStream` (Sender hosts plain `http://<ip>:8080` for live `<video autoplay playsinline>`). Includes Fit/Fill, Rotate 90°, Mirror, RTT stats toggle, clipboard drawer, and browser `cam_ctrl`/`cam_state` (`flip` + `micMute`).
- `GET /obs` (`buildObsCleanFeedHtml`, `StreamConstants.obsCleanFeedPath`): Zero-UI full-bleed HTML5/WebRTC page designed for **OBS Studio Browser Source**:
  - `cursor: none`, `<video id="v" autoplay playsinline>`, transparent canvas by default.
  - Supported URL query parameters: `?pin=<digits>`, `?fit=cover`, `?mirror=1` (or `true`), `?bg=black`.
  - Uses H.264 SDP priority (`preferH264`), early ICE buffering, DataChannel `ping -> pong` heartbeat replies, and automatic **1500 ms** reconnect (`scheduleReconnect`) on disconnect/error.
