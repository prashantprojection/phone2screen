import 'dart:convert';

/// Builds the self-contained HTML5/CSS/JS Browser Web Companion served at
/// `GET /` by `SignalingServerService`, allowing any LAN browser to stream
/// camera or screen video and sync clipboard/RTT with this Receiver.
String buildWebCompanionHtml({
  required String sessionId,
  required String deviceName,
  required bool requiresPin,
}) {
  final escapedName = const HtmlEscape().convert(deviceName);
  // Escape '</' so a deviceName containing '</script>' cannot close the script tag.
  final cfgJson = jsonEncode({
    'sessionId': sessionId,
    'deviceName': deviceName,
    'requiresPin': requiresPin,
  }).replaceAll('</', r'<\/');
  final pinBlock = requiresPin
      ? '<label class="field"><span>Session PIN</span>'
            '<input id="pin" type="password" inputmode="numeric" '
            'placeholder="Enter receiver PIN" autocomplete="off" /></label>'
      : '';

  return _companionTemplate
      .replaceAll('__ESCAPED_NAME__', escapedName)
      .replaceAll('__PIN_BLOCK__', pinBlock)
      .replaceAll('__CFG_JSON__', cfgJson);
}

const String _companionTemplate = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Phone2Screen • __ESCAPED_NAME__</title>
<style>
:root{color-scheme:dark;--bg:#0A0E17;--card:#141A26;--el:#1C2434;--bd:#28334A;--pri:#2F6BFF;--cyn:#00D2FF;--ok:#10B981;--err:#EF4444;--tx:#F3F6FC;--mut:#94A3B8}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:16px}
.wrap{max-width:780px;margin:0 auto;display:grid;gap:14px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:16px;padding:16px}
.top{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px}
.brand{font-weight:700;font-size:17px;letter-spacing:-.2px}.sub{color:var(--mut);font-size:12px}
.badges{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.pill{padding:5px 10px;border-radius:999px;background:var(--el);border:1px solid var(--bd);font-size:12px;font-weight:600}
.pill.ok{border-color:rgba(16,185,129,.45);color:var(--ok)}.pill.err{border-color:rgba(239,68,68,.45);color:var(--err)}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:end}
.field{display:grid;gap:5px;flex:1 1 160px;font-size:12px;color:var(--mut)}
input,select,textarea{background:var(--el);color:var(--tx);border:1px solid var(--bd);border-radius:10px;padding:9px 11px;font:inherit;outline:none}
input:focus,textarea:focus{border-color:var(--pri)}
.chk{display:flex;align-items:center;gap:7px;padding:9px 11px;background:var(--el);border:1px solid var(--bd);border-radius:10px;cursor:pointer;user-select:none}
button{border:0;border-radius:10px;padding:10px 14px;font:600 13px inherit;cursor:pointer;color:#fff;background:var(--pri)}
button.sec{background:var(--el);border:1px solid var(--bd);color:var(--tx)}
button.stop{background:var(--err)}button:disabled{opacity:.45;cursor:not-allowed}
video{width:100%;max-height:380px;background:#05070B;border-radius:12px;border:1px solid var(--bd);object-fit:contain}
.clip-row{display:grid;gap:8px;margin-top:8px}.clip-actions{display:flex;gap:8px;flex-wrap:wrap}
.err-box{color:#FCA5A5;font-size:12px;margin-top:8px;min-height:16px}
</style>
</head>
<body>
<div class="wrap">
  <div class="card top">
    <div><div class="brand">Phone2Screen Web Companion</div><div class="sub">Target receiver: __ESCAPED_NAME__</div></div>
    <div class="badges"><span id="status" class="pill">Ready</span><span id="rtt" class="pill">RTT -- ms</span></div>
  </div>
  <div class="card">
    <div class="controls">
      __PIN_BLOCK__
      <label class="field"><span>Camera Lens</span><select id="lens"><option value="environment">Rear Camera</option><option value="user">Front Camera</option></select></label>
      <label class="chk"><input id="mic" type="checkbox" /><span>Include Audio</span></label>
      <button id="btnCam" type="button">Stream Camera</button>
      <button id="btnScr" class="sec" type="button">Share Screen</button>
      <button id="btnStop" class="stop" type="button" disabled>Stop</button>
    </div>
    <div id="err" class="err-box"></div>
  </div>
  <div class="card"><video id="preview" autoplay playsinline muted></video></div>
  <div class="card">
    <div style="font-weight:600;margin-bottom:4px">Clipboard Sync</div>
    <div class="clip-row">
      <textarea id="clipOut" rows="2" placeholder="Type or paste text to send to receiver..."></textarea>
      <div class="clip-actions">
        <button id="btnClipSend" type="button" disabled>Send to Receiver</button>
        <button id="btnClipCopy" class="sec" type="button" disabled>Copy Latest Received</button>
      </div>
      <div id="clipIn" class="sub">No clipboard text received yet.</div>
    </div>
  </div>
</div>
<script>
(function(){
  const CFG = __CFG_JSON__;
  const byId = (id) => document.getElementById(id);
  const statusEl = byId('status'), rttEl = byId('rtt'), errEl = byId('err'), preview = byId('preview');
  const btnCam = byId('btnCam'), btnScr = byId('btnScr'), btnStop = byId('btnStop');
  const btnClipSend = byId('btnClipSend'), btnClipCopy = byId('btnClipCopy');
  const clipOut = byId('clipOut'), clipIn = byId('clipIn');

  let ws = null, pc = null, dc = null, stream = null, pingTimer = null;
  let remoteDescSet = false, earlyIce = [], latestClip = '';

  function setStatus(txt, cls){ statusEl.textContent = txt; statusEl.className = 'pill' + (cls ? ' ' + cls : ''); }
  function setErr(msg){ errEl.textContent = msg || ''; }
  function setStreamingUi(active){ btnCam.disabled = active; btnScr.disabled = active; btnStop.disabled = !active; }
  function sendSig(type, payload){ if (ws && ws.readyState === 1) ws.send(JSON.stringify({type, sessionId: CFG.sessionId, payload: payload || {}})); }

  async function flushEarlyIce(){
    // Drain candidates that arrived before setRemoteDescription completed.
    while (earlyIce.length > 0 && pc){
      const c = earlyIce.shift();
      if (c && c.candidate) await pc.addIceCandidate(new RTCIceCandidate(c)).catch(() => {});
    }
  }

  function cleanup(sendBye){
    if (pingTimer){ clearInterval(pingTimer); pingTimer = null; }
    if (sendBye) sendSig('bye', {reason: 'Browser stopped stream'});
    if (dc){ try{ dc.close(); }catch(_){} dc = null; }
    if (pc){ try{ pc.close(); }catch(_){} pc = null; }
    if (ws){ try{ ws.close(); }catch(_){} ws = null; }
    if (stream){ stream.getTracks().forEach((t) => t.stop()); stream = null; }
    preview.srcObject = null;
    remoteDescSet = false; earlyIce = [];
    btnClipSend.disabled = true; rttEl.textContent = 'RTT -- ms';
    setStreamingUi(false);
  }

  function setupDataChannel(channel){
    dc = channel;
    dc.onopen = () => {
      btnClipSend.disabled = false;
      pingTimer = setInterval(() => {
        if (dc && dc.readyState === 'open') dc.send(JSON.stringify({kind: 'ping', ts: Date.now()}));
      }, 1000);
    };
    dc.onclose = () => { btnClipSend.disabled = true; };
    dc.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.kind === 'ping' && dc && dc.readyState === 'open'){
          dc.send(JSON.stringify({kind: 'pong', ts: msg.ts}));
        } else if (msg.kind === 'pong' && typeof msg.ts === 'number'){
          rttEl.textContent = 'RTT ' + Math.max(0, Date.now() - msg.ts) + ' ms';
        } else if (msg.kind === 'clipboard' && typeof msg.text === 'string'){
          latestClip = msg.text;
          clipIn.textContent = 'Received: ' + msg.text;
          btnClipCopy.disabled = false;
          if (navigator.clipboard && navigator.clipboard.writeText){
            navigator.clipboard.writeText(msg.text).catch(() => {});
          }
        }
      } catch (_) {}
    };
  }

  async function startOffer(){
    pc = new RTCPeerConnection({iceServers: [{urls: 'stun:stun.l.google.com:19302'}]});
    remoteDescSet = false; earlyIce = [];
    stream.getTracks().forEach((t) => pc.addTrack(t, stream));
    setupDataChannel(pc.createDataChannel('phone2screen-control', {ordered: true}));
    pc.onicecandidate = (e) => {
      if (e.candidate && e.candidate.candidate){
        sendSig('ice', {candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex});
      }
    };
    pc.onconnectionstatechange = () => {
      if (!pc) return;
      if (pc.connectionState === 'connected') setStatus('Streaming', 'ok');
      else if (pc.connectionState === 'failed' || pc.connectionState === 'closed'){
        setStatus('Disconnected', 'err'); cleanup(false);
      }
    };
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    sendSig('offer', {sdp: offer.sdp, type: offer.type});
  }

  async function startSession(mode){
    setErr('');
    const pinEl = byId('pin');
    const pin = pinEl ? pinEl.value.trim() : '';
    if (CFG.requiresPin && !pin){ setErr('Please enter the session PIN first.'); if (pinEl) pinEl.focus(); return; }
    try {
      const audio = byId('mic').checked;
      stream = mode === 'screen'
        ? await navigator.mediaDevices.getDisplayMedia({video: true, audio})
        : await navigator.mediaDevices.getUserMedia({video: {facingMode: byId('lens').value, width: {ideal: 1280}, height: {ideal: 720}}, audio});
      const vTrack = stream.getVideoTracks()[0];
      if (vTrack) vTrack.onended = () => { setStatus('Stopped', ''); cleanup(true); };
      preview.srcObject = stream;
      setStreamingUi(true);
      setStatus('Connecting...', '');
      const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
      ws = new WebSocket(proto + location.host + '/ws');
      ws.onopen = () => sendSig('hello', {deviceName: 'Web Browser', pin});
      ws.onerror = () => { setErr('WebSocket connection error.'); setStatus('Error', 'err'); cleanup(false); };
      ws.onclose = () => { if (ws) { setStatus('Disconnected', ''); cleanup(false); } };
      ws.onmessage = async (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === 'welcome'){ await startOffer(); }
          else if (msg.type === 'answer'){
            await pc.setRemoteDescription(new RTCSessionDescription(msg.payload));
            remoteDescSet = true;
            await flushEarlyIce();
          } else if (msg.type === 'ice'){
            if (!remoteDescSet) earlyIce.push(msg.payload);
            else if (msg.payload && msg.payload.candidate) await pc.addIceCandidate(new RTCIceCandidate(msg.payload));
          } else if (msg.type === 'error'){
            setErr((msg.payload && msg.payload.message) || 'Connection rejected.');
            setStatus('Rejected', 'err'); cleanup(false);
          } else if (msg.type === 'bye'){
            setStatus('Session ended', ''); cleanup(false);
          }
        } catch (err) { setErr(String(err)); }
      };
    } catch (err) {
      setErr('Media or signaling failed: ' + (err.message || err));
      setStatus('Failed', 'err'); cleanup(false);
    }
  }

  btnCam.onclick = () => startSession('camera');
  btnScr.onclick = () => startSession('screen');
  btnStop.onclick = () => { setStatus('Stopped', ''); cleanup(true); };
  btnClipSend.onclick = () => {
    const text = clipOut.value;
    if (text && dc && dc.readyState === 'open'){
      dc.send(JSON.stringify({kind: 'clipboard', text, ts: Date.now()}));
      clipOut.value = '';
    }
  };
  btnClipCopy.onclick = () => {
    if (latestClip && navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(latestClip).catch(() => {});
    }
  };
  window.addEventListener('beforeunload', () => cleanup(true));
})();
</script>
</body>
</html>''';
