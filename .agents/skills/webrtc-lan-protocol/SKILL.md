---
name: webrtc-lan-protocol
description: Specification for Phone2Screen LAN UDP 41234 P2S_V1 discovery, /ws SignalingMessage JSON handshake, early ICE buffering, phone2screen-control DataChannel, NIC ranking, and GET / Browser Web Companion.
---

# WebRTC & LAN Signaling Protocol

Phone2Screen operates completely offline on a local network (Wi-Fi, Ethernet, USB tethering, or mobile hotspot) without cloud relay servers.

## 1. NIC Ranking (`NetworkInterfaceInfo`)

- Enumerate local IPv4 addresses via `NetworkInterface.list(type: InternetAddressType.IPv4)`.
- Filter out loopback (`127.0.0.0/8`), link-local (`169.254.0.0/16`), and virtual/tunnel adapters (e.g., `vEthernet`, `WSL`, `Hyper-V`, `Docker`, `VMware`, `VirtualBox`, `tun`, `tap`, `wg`, `utun`, `tailscale`).
- Rank private RFC1918 LAN interfaces (`192.168.*`, `10.*`, `172.16-31.*`) highest, preferring active Wi-Fi (`wlan`, `wi-fi`, `en0`) and Ethernet (`eth`, `en`) interfaces (`isPreferred = true`).

## 2. UDP LAN Discovery (`41234`, `P2S_V1`)

- Receiver (host) opens a `RawDatagramSocket` (with `reuseAddress: true`, `broadcastEnabled: true`) and broadcasts every `2s` (`StreamConstants.discoveryInterval`) on UDP port `41234` (`StreamConstants.udpDiscoveryPort`).
- Packet format: UTF-8 JSON (or prefixed with magic `'P2S_V1'`) containing `magic: 'P2S_V1'` and `SignalingData` fields (`ip`, `port`, `sessionId`, `deviceName`, `requiresPin`).
- Sender listens on `InternetAddress.anyIPv4` port `41234`, validates `P2S_V1`, ignores self-IPs if needed, updates `DiscoveredPeer(endpoint, lastSeen)`, and expires peers unseen for `> 8s` (`StreamConstants.peerStaleTimeout`).

## 3. HTTP + WebSocket Signaling (`/ws`)

- Receiver binds an `HttpServer` on the first free port in `8080..8095` (`defaultSignalingPort`..`maxSignalingPort`).
- `GET /`: serves the self-contained HTML5/JS Browser Web Companion (zero external assets).
- `GET /ws`: upgrades to WebSocket and exchanges `SignalingMessage` JSON envelopes:
  ```json
  {
    "type": "hello | welcome | offer | answer | ice | bye | error",
    "sessionId": "<uuid-or-short-id>",
    "payload": {}
  }
  ```
- **Handshake sequence**:
  1. Sender connects to `ws://<ip>:<port>/ws` and sends `hello` (`sessionId`, optional `pin`, `deviceName`, `role`).
  2. Receiver verifies `sessionId` (and PIN if `requiresPin == true`); replies `welcome` (or `error` with reason and closes).
  3. Sender creates WebRTC `offer` (with local camera/screen tracks + `phone2screen-control` DataChannel) and sends `offer` (`sdp`, `type`).
  4. Receiver applies remote offer, creates `answer`, and sends `answer` (`sdp`, `type`).
  5. Both sides trickle `ice` candidates (`candidate`, `sdpMid`, `sdpMLineIndex`).
  6. Either side sends `bye` on graceful disconnect.

## 4. Early ICE Candidate Buffering

- WebRTC `ice` messages can arrive before `setRemoteDescription` completes.
- Always queue incoming ICE candidates into a pending list until `_remoteDescriptionSet == true`, then flush all buffered candidates in order via `addCandidate` immediately after `setRemoteDescription`.
- Clear the buffer on session reset/disconnect so stale candidates never leak into a new connection.

## 5. Control DataChannel (`phone2screen-control`)

- Reliable ordered `RTCDataChannel` created by the sender with label `phone2screen-control` (`StreamConstants.controlChannelLabel`).
- JSON message types:
  - `ping`: `{ "kind": "ping", "ts": <epochMs> }` sent every `1s` (`StreamConstants.pingInterval`).
  - `pong`: `{ "kind": "pong", "ts": <echoedTs> }` replied immediately by receiver; sender/receiver compute RTT `latencyMs`.
  - `clipboard`: `{ "kind": "clipboard", "text": "<content>", "ts": <epochMs> }` synced bidirectionally (`ClipboardItem`).

## 6. Browser Web Companion (`GET /`)

- Any desktop or mobile browser on the LAN can open the companion URL to interact with Phone2Screen without installing the native app, operating in two `WebCompanionMode` modes:
  - `sendToReceiver` (Receiver hosts `http://<ip>:8080` + companion TLS `https://<ip>:8443`): Browser captures camera/screen (`getUserMedia`/`getDisplayMedia` require a Secure Context, so plain `http://<lan-ip>` automatically prompts to switch to `https://<lan-ip>:8443` or `http://localhost:8080`), creates the WebRTC `offer`, and streams to Receiver.
  - `viewSenderStream` (Sender hosts **Cast to Web Browser** on plain `http://<ip>:8080`): Browser connects `/ws`, receives the Sender's WebRTC `offer`, replies `answer`, and watches live `<video autoplay playsinline>` over plain HTTP on any LAN browser with zero HTTPS requirement and zero Tier-3 transcoding overhead.
- Both modes use native browser `WebSocket`, `RTCPeerConnection` (preferring H.264), early ICE buffering, and the `phone2screen-control` DataChannel (`ping`/`pong` RTT + bidirectional `clipboard`).
