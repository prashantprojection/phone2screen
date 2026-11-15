import 'dart:convert';

import 'web_companion_mode.dart';

/// Builds the zero-UI full-bleed HTML5/CSS/JS clean video page for OBS Studio
/// Browser Source (`GET /obs`), with optional `?bg=black`, `?fit=cover`,
/// `?mirror=1`, and `?pin=<digits>` parameters plus 1500ms auto-reconnect.
String buildObsCleanFeedHtml({
  required String sessionId,
  required String deviceName,
  required bool requiresPin,
  WebCompanionMode mode = .viewSenderStream,
}) {
  final escapedName = const HtmlEscape().convert(deviceName);
  // Escape '</' so a deviceName containing '</script>' cannot close the tag.
  final cfgJson = jsonEncode({
    'sessionId': sessionId,
    'deviceName': deviceName,
    'requiresPin': requiresPin,
    'mode': mode == .viewSenderStream ? 'viewer' : 'sender',
  }).replaceAll('</', r'<\/');

  return _obsCleanFeedTemplate
      .replaceAll('__ESCAPED_NAME__', escapedName)
      .replaceAll('__CFG_JSON__', cfgJson);
}

const String _obsCleanFeedTemplate = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<title>Phone2Screen OBS • __ESCAPED_NAME__</title>
<style>
html,body{margin:0;padding:0;width:100vw;height:100vh;overflow:hidden;background:transparent;cursor:none}
html.bg-black,body.bg-black{background:#000}
#v{width:100vw;height:100vh;display:block;object-fit:contain;background:transparent}
#v.fit-cover{object-fit:cover}
#v.mirrored{transform:scaleX(-1)}
#dot{position:fixed;top:10px;left:10px;width:8px;height:8px;border-radius:50%;background:rgba(56,189,248,.85);pointer-events:none;z-index:2}
#dot[hidden]{display:none}
</style>
</head>
<body>
<div id="dot" aria-hidden="true"></div>
<video id="v" autoplay playsinline></video>
<script>
(function(){
  const CFG = __CFG_JSON__;
  const q = new URLSearchParams(location.search);
  const pin = (q.get('pin') || '').trim();
  const v = document.getElementById('v'), dot = document.getElementById('dot');
  if (q.get('bg') === 'black'){ document.documentElement.classList.add('bg-black'); document.body.classList.add('bg-black'); }
  if (q.get('fit') === 'cover') v.classList.add('fit-cover');
  if (q.get('mirror') === '1' || q.get('mirror') === 'true') v.classList.add('mirrored');

  let ws = null, pc = null, dc = null, remoteDescSet = false, earlyIce = [];
  let reconTimer = null, dead = false, playAttempted = false;
  const iceCfg = {iceServers: [{urls: 'stun:stun.l.google.com:19302'}]};
  const sendSig = (type, payload) => {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify({type, sessionId: CFG.sessionId, payload: payload || {}}));
  };

  // Prioritize hardware H.264 payload types on m=video for low-end mobile decoders.
  function preferH264(sdp){
    if (!sdp) return sdp;
    const nl = sdp.indexOf('\r\n') >= 0 ? '\r\n' : '\n', lines = sdp.split(nl);
    let mIdx = -1, endIdx = lines.length;
    for (let i = 0; i < lines.length; i++){
      if (lines[i].startsWith('m=video ')) mIdx = i;
      else if (mIdx !== -1 && lines[i].startsWith('m=')){ endIdx = i; break; }
    }
    if (mIdx === -1) return sdp;
    const h264 = new Set();
    for (let i = mIdx + 1; i < endIdx; i++){ const m = lines[i].match(/^a=rtpmap:(\d+)\s+H264\//i); if (m) h264.add(m[1]); }
    const p = lines[mIdx].split(' ');
    if (!h264.size || p.length <= 3) return sdp;
    const pref = [], rest = [];
    for (const pt of p.slice(3)) (h264.has(pt) ? pref : rest).push(pt);
    if (!pref.length) return sdp;
    lines[mIdx] = [...p.slice(0, 3), ...pref, ...rest].join(' ');
    return lines.join(nl);
  }

  async function flushEarlyIce(){
    // Drain candidates that arrived before setRemoteDescription completed.
    while (earlyIce.length > 0 && pc){
      const c = earlyIce.shift();
      if (c && c.candidate) await pc.addIceCandidate(new RTCIceCandidate(c)).catch(() => {});
    }
  }

  function tryPlay(){
    if (!v.srcObject) return;
    if (!playAttempted){ playAttempted = true; v.muted = false; }
    if (!v.paused) return;
    const p = v.play();
    if (p && p.then){
      p.then(() => { if (!v.paused) dot.hidden = true; }).catch(() => {
        v.muted = true;
        v.play().then(() => { if (!v.paused) dot.hidden = true; }).catch(() => {});
      });
    }
  }

  v.addEventListener('playing', () => { dot.hidden = true; });

  function scheduleReconnect(){
    if (dead || reconTimer) return;
    reconTimer = setTimeout(() => { reconTimer = null; connect(); }, 1500);
  }

  function cleanup(retry){
    if (dc){ try{ dc.close(); }catch(_){} dc = null; }
    if (pc){ pc.onconnectionstatechange = null; pc.onicecandidate = null; try{ pc.close(); }catch(_){} pc = null; }
    if (ws){ ws.onopen = null; ws.onmessage = null; ws.onerror = null; ws.onclose = null; try{ ws.close(); }catch(_){} ws = null; }
    v.srcObject = null; remoteDescSet = false; earlyIce = []; playAttempted = false;
    dot.hidden = false;
    if (retry) scheduleReconnect();
  }

  function setupDc(ch){
    dc = ch;
    dc.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.kind === 'ping' && dc && dc.readyState === 'open') dc.send(JSON.stringify({kind: 'pong', ts: msg.ts}));
      } catch (_) {}
    };
  }

  function createPc(){
    const conn = new RTCPeerConnection(iceCfg);
    remoteDescSet = false; earlyIce = [];
    conn.onicecandidate = (e) => { if (e.candidate && e.candidate.candidate) sendSig('ice', {candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex}); };
    conn.ondatachannel = (e) => setupDc(e.channel);
    conn.ontrack = (e) => {
      const inc = (e.streams && e.streams[0]) || null;
      if (inc){ if (v.srcObject !== inc) v.srcObject = inc; }
      else {
        const cur = v.srcObject instanceof MediaStream ? v.srcObject : new MediaStream();
        cur.addTrack(e.track); if (v.srcObject !== cur) v.srcObject = cur;
      }
      tryPlay();
    };
    conn.onconnectionstatechange = () => {
      if (pc !== conn) return;
      if (conn.connectionState === 'failed' || conn.connectionState === 'closed') cleanup(true);
    };
    return conn;
  }

  function connect(){
    if (dead) return;
    cleanup(false);
    try {
      ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws');
      ws.onopen = () => sendSig('hello', {deviceName: 'OBS Clean Feed', role: 'viewer', pin});
      ws.onerror = () => cleanup(true);
      ws.onclose = () => cleanup(true);
      ws.onmessage = async (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === 'ice'){
            if (!remoteDescSet) earlyIce.push(msg.payload);
            else if (msg.payload && msg.payload.candidate && pc) await pc.addIceCandidate(new RTCIceCandidate(msg.payload));
          } else if (msg.type === 'offer'){
            if (pc) try{ pc.close(); }catch(_){}
            pc = createPc();
            await pc.setRemoteDescription(new RTCSessionDescription(msg.payload));
            remoteDescSet = true;
            await flushEarlyIce();
            const raw = await pc.createAnswer();
            const ans = {type: raw.type, sdp: preferH264(raw.sdp)};
            await pc.setLocalDescription(ans);
            sendSig('answer', ans);
          } else if (msg.type === 'bye' || msg.type === 'error'){
            cleanup(true);
          }
        } catch (_) { cleanup(true); }
      };
    } catch (_) { cleanup(true); }
  }

  window.addEventListener('beforeunload', () => {
    dead = true;
    if (reconTimer){ clearTimeout(reconTimer); reconTimer = null; }
    sendSig('bye', {reason: 'OBS closed'});
    cleanup(false);
  });
  connect();
})();
</script>
</body>
</html>''';