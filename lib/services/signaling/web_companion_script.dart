/// Embedded WebRTC and WebSocket signaling runtime for the Browser Web Companion (`GET /`),
/// executed inside the shared IIFE alongside [webCompanionUiScript].
const String webCompanionScript = r'''
  const CFG = __CFG_JSON__;
  const byId = (id) => document.getElementById(id);
  const statusEl = byId('status'), rttEl = byId('rtt'), errEl = byId('err'), preview = byId('preview');
  const btnCam = byId('btnCam'), btnScr = byId('btnScr'), btnStop = byId('btnStop');
  const btnWatch = byId('btnWatch'), btnClipSend = byId('btnClipSend'), btnClipCopy = byId('btnClipCopy');
  const clipOut = byId('clipOut'), clipIn = byId('clipIn');

  let ws = null, pc = null, dc = null, stream = null, pingTimer = null;
  let remoteDescSet = false, earlyIce = [], latestClip = '', mediaBusy = false;
  let activeSource = '', currentLens = 'environment', micMuted = false;
  const iceCfg = {iceServers: [{urls: 'stun:stun.l.google.com:19302'}]};

  const setStatus = (txt, cls) => { statusEl.textContent = txt; statusEl.className = 'pill' + (cls ? ' ' + cls : ''); };
  const setErr = (msg) => { if (errEl) errEl.textContent = msg || ''; };
  const sendSig = (type, payload) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify({type, sessionId: CFG.sessionId, payload: payload || {}})); };
  const canDisplayMedia = () => Boolean(navigator.mediaDevices && typeof navigator.mediaDevices.getDisplayMedia === 'function');
  const isSecureMediaReady = () => Boolean(window.isSecureContext && navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function');

  function setControlsBusy(active){
    if (btnCam) btnCam.disabled = active;
    if (btnScr && canDisplayMedia()) btnScr.disabled = active;
    if (btnWatch) btnWatch.disabled = active;
    if (btnStop) btnStop.disabled = !active;
  }

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

  function describeError(err){
    if (!window.isSecureContext || !navigator.mediaDevices)
      return 'Browser blocked camera/screen on plain HTTP. Use the HTTPS link above or open localhost on this PC.';
    const n = (err && err.name) || '';
    if (n === 'NotAllowedError' || n === 'PermissionDeniedError') return 'Permission denied. Allow camera/microphone or screen-share access in your browser prompt.';
    if (n === 'NotFoundError' || n === 'DevicesNotFoundError') return 'No camera found on this device. Connect a webcam or use Share Screen.';
    if (n === 'NotReadableError' || n === 'TrackStartError') return 'Camera is already in use by another app. Close it and retry.';
    if (n === 'OverconstrainedError') return 'Requested camera resolution or lens is unavailable on this device.';
    return (err && err.message) || String(err);
  }

  async function flushEarlyIce(){
    // Drain candidates that arrived before setRemoteDescription completed.
    while (earlyIce.length > 0 && pc){
      const c = earlyIce.shift();
      if (c && c.candidate) await pc.addIceCandidate(new RTCIceCandidate(c)).catch(() => {});
    }
  }
  async function applyRemoteAndFlush(payload){ await pc.setRemoteDescription(new RTCSessionDescription(payload)); remoteDescSet = true; await flushEarlyIce(); }
  async function sendLocalSdp(kind, raw){ const msg = {type: raw.type, sdp: preferH264(raw.sdp)}; await pc.setLocalDescription(msg); sendSig(kind, msg); }

  function cleanup(sendBye){
    if (pingTimer){ clearInterval(pingTimer); pingTimer = null; }
    if (sendBye) sendSig('bye', {reason: 'Browser stopped session'});
    if (dc){ try{ dc.close(); }catch(_){} dc = null; }
    if (pc){ try{ pc.close(); }catch(_){} pc = null; }
    if (ws){ try{ ws.onclose = null; ws.close(); }catch(_){} ws = null; }
    if (stream){ stream.getTracks().forEach((t) => t.stop()); stream = null; }
    preview.srcObject = null; remoteDescSet = false; earlyIce = []; activeSource = ''; micMuted = false;
    if (btnClipSend) btnClipSend.disabled = true;
    rttEl.textContent = 'RTT -- ms'; setControlsBusy(false); setStageLive(false); updateDockState();
  }

  function setupDataChannel(channel){
    dc = channel;
    dc.onopen = () => {
      if (btnClipSend) btnClipSend.disabled = false;
      pingTimer = setInterval(() => { if (dc && dc.readyState === 'open') dc.send(JSON.stringify({kind: 'ping', ts: Date.now()})); }, 1000);
    };
    dc.onclose = () => { if (btnClipSend) btnClipSend.disabled = true; };
    dc.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.kind === 'ping' && dc && dc.readyState === 'open') dc.send(JSON.stringify({kind: 'pong', ts: msg.ts}));
        else if (msg.kind === 'pong' && typeof msg.ts === 'number') rttEl.textContent = 'RTT ' + Math.max(0, Date.now() - msg.ts) + ' ms';
        else if (msg.kind === 'clipboard' && typeof msg.text === 'string'){
          onClipboardReceived(msg.text);
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(msg.text).catch(() => {});
        }
      } catch (_) {}
    };
  }
  function sendClipboardText(text){ if (!text || !dc || dc.readyState !== 'open') return false; dc.send(JSON.stringify({kind: 'clipboard', text, ts: Date.now()})); return true; }

  function createPc(){
    const conn = new RTCPeerConnection(iceCfg); remoteDescSet = false; earlyIce = [];
    conn.onicecandidate = (e) => { if (e.candidate && e.candidate.candidate) sendSig('ice', {candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex}); };
    conn.onconnectionstatechange = () => {
      if (!pc || pc !== conn) return;
      if (conn.connectionState === 'connected') setStatus(CFG.mode === 'viewer' ? 'Watching' : 'Streaming', 'ok');
      else if (conn.connectionState === 'failed' || conn.connectionState === 'closed'){ setStatus('Disconnected', 'err'); cleanup(false); }
    };
    return conn;
  }

  async function acquireMedia(kind, wantAudio, lens){
    if (kind === 'screen'){
      if (!canDisplayMedia()) throw new Error('Screen share requires a desktop browser or the Phone2Screen Android app. Try Stream Camera instead.');
      try { return await navigator.mediaDevices.getDisplayMedia({video: true, audio: wantAudio}); }
      catch (e) { if (!wantAudio || (e && (e.name === 'NotAllowedError' || e.name === 'AbortError'))) throw e; return await navigator.mediaDevices.getDisplayMedia({video: true, audio: false}); }
    }
    const videoCfg = {facingMode: {ideal: lens}, width: {ideal: 1280}, height: {ideal: 720}};
    try { return await navigator.mediaDevices.getUserMedia({video: videoCfg, audio: wantAudio}); }
    catch (firstErr) {
      if (firstErr && firstErr.name === 'NotAllowedError') throw firstErr;
      if (wantAudio){ try { return await navigator.mediaDevices.getUserMedia({video: videoCfg, audio: false}); } catch (_) {} }
      return await navigator.mediaDevices.getUserMedia({video: true, audio: false});
    }
  }

  // Swap the active video RTCRtpSender track seamlessly without dropping WebRTC.
  async function swapLiveVideo(kind, lens, onApplied){
    if (mediaBusy || !stream) return;
    mediaBusy = true;
    try {
      const next = await acquireMedia(kind, false, lens), track = next.getVideoTracks()[0];
      if (track){
        const oldTracks = stream.getVideoTracks(), sender = pc ? pc.getSenders().find((s) => s.track && s.track.kind === 'video') : null;
        if (sender) await sender.replaceTrack(track);
        oldTracks.forEach((t) => { stream.removeTrack(t); t.stop(); });
        stream.addTrack(track); track.onended = () => { setStatus('Stopped', ''); cleanup(true); };
        preview.srcObject = stream; preview.play().catch(() => {});
        onApplied(); setErr(''); updateDockState();
      }
    } catch (err) { const msg = describeError(err); setErr(msg); showStageToast(msg); }
    finally { mediaBusy = false; }
  }

  function switchLiveCamera(){
    if (CFG.mode !== 'sender' || activeSource !== 'camera') return;
    const nextLens = currentLens === 'environment' ? 'user' : 'environment';
    return swapLiveVideo('camera', nextLens, () => { currentLens = nextLens; const lensEl = byId('lens'); if (lensEl) lensEl.value = nextLens; });
  }
  function switchLiveSource(mode){ if (!stream) return startSender(mode); if (activeSource !== mode) return swapLiveVideo(mode, currentLens, () => { activeSource = mode; }); }

  function toggleLiveMic(){
    if (CFG.mode !== 'sender') return;
    if (!stream){ const micEl = byId('mic'); if (micEl) micEl.checked = !micEl.checked; updateDockState(); return; }
    const tracks = stream.getAudioTracks();
    if (!tracks.length) return;
    micMuted = !micMuted; tracks.forEach((t) => { t.enabled = !micMuted; }); updateDockState();
  }

  function openSocket(role, pin, onMessage){
    ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws');
    ws.onopen = () => sendSig('hello', {deviceName: role === 'viewer' ? 'Web Viewer' : 'Web Browser', role, pin});
    ws.onerror = () => { setErr('WebSocket signaling failed.'); setStatus('Error', 'err'); cleanup(false); };
    ws.onclose = () => { if (ws) { setStatus('Disconnected', ''); cleanup(false); } };
    ws.onmessage = async (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === 'ice'){
          if (!remoteDescSet) earlyIce.push(msg.payload);
          else if (msg.payload && msg.payload.candidate) await pc.addIceCandidate(new RTCIceCandidate(msg.payload));
        } else if (msg.type === 'error'){ setErr((msg.payload && msg.payload.message) || 'Connection rejected.'); setStatus('Rejected', 'err'); cleanup(false); }
        else if (msg.type === 'bye'){ setStatus(role === 'viewer' ? 'Sender ended' : 'Session ended', ''); cleanup(false); }
        else await onMessage(msg);
      } catch (err) { setErr(describeError(err)); setStatus('Failed', 'err'); cleanup(false); }
    };
  }

  function readPinOrWarn(){
    const pinEl = byId('pin'), pin = pinEl ? pinEl.value.trim() : '';
    if (CFG.requiresPin && !pin){ setErr('Please enter the session PIN first.'); if (pinEl) pinEl.focus(); return null; }
    return pin;
  }

  async function startSender(mode){
    if (mediaBusy) return;
    setErr(''); const pin = readPinOrWarn(); if (pin === null) return;
    mediaBusy = true;
    try {
      const wantAudio = Boolean(byId('mic') && byId('mic').checked);
      currentLens = byId('lens') ? byId('lens').value : 'environment';
      stream = await acquireMedia(mode, wantAudio, currentLens);
      activeSource = mode; micMuted = false;
      const vTrack = stream.getVideoTracks()[0];
      if (vTrack) vTrack.onended = () => { setStatus('Stopped', ''); cleanup(true); };
      preview.srcObject = stream; preview.play().catch(() => {});
      setControlsBusy(true); setStageLive(true); setStatus('Connecting...', '');
      openSocket('sender', pin, async (msg) => {
        if (msg.type === 'welcome'){
          pc = createPc(); stream.getTracks().forEach((t) => pc.addTrack(t, stream));
          setupDataChannel(pc.createDataChannel('phone2screen-control', {ordered: true}));
          await sendLocalSdp('offer', await pc.createOffer());
        } else if (msg.type === 'answer') await applyRemoteAndFlush(msg.payload);
      });
    } catch (err) { setErr(describeError(err)); setStatus('Failed', 'err'); cleanup(false); }
    finally { mediaBusy = false; }
  }

  async function startViewer(){
    setErr(''); const pin = readPinOrWarn(); if (pin === null) return;
    cleanup(false); setControlsBusy(true); setStatus('Connecting...', '');
    try {
      openSocket('viewer', pin, async (msg) => {
        if (msg.type === 'welcome') setStatus('Waiting stream...', '');
        else if (msg.type === 'offer'){
          if (pc) try{ pc.close(); }catch(_){}
          pc = createPc(); pc.ondatachannel = (e) => setupDataChannel(e.channel);
          pc.ontrack = (e) => {
            const inc = (e.streams && e.streams[0]) || null;
            if (inc){ if (preview.srcObject !== inc) preview.srcObject = inc; }
            else {
              const cur = preview.srcObject instanceof MediaStream ? preview.srcObject : new MediaStream();
              cur.addTrack(e.track); if (preview.srcObject !== cur) preview.srcObject = cur;
            }
            preview.play().catch(() => {}); setStageLive(true);
          };
          await applyRemoteAndFlush(msg.payload);
          await sendLocalSdp('answer', await pc.createAnswer());
        }
      });
    } catch (err) { setErr(describeError(err)); setStatus('Failed', 'err'); cleanup(false); }
  }

  function initCompanionSession(){
    if (CFG.mode === 'viewer'){ if (btnWatch) btnWatch.onclick = startViewer; if (!CFG.requiresPin) startViewer(); return; }
    const secBanner = byId('secBanner'), btnHttps = byId('btnHttps'), btnLocal = byId('btnLocal');
    if (!isSecureMediaReady()){
      if (secBanner) secBanner.style.display = 'grid';
      if (btnCam) btnCam.disabled = true; if (btnScr) btnScr.disabled = true;
      setStatus('HTTPS Required', 'err');
      if (btnHttps && CFG.httpsPort) btnHttps.onclick = () => { location.href = 'https://' + location.hostname + ':' + CFG.httpsPort + '/'; };
      if (btnLocal) btnLocal.onclick = () => { location.href = 'http://localhost:' + CFG.httpPort + '/'; };
    } else if (btnScr && !canDisplayMedia()){
      btnScr.disabled = true; btnScr.title = 'Screen share requires a desktop browser or the Phone2Screen Android app; use Stream Camera here.';
    }
    if (btnCam) btnCam.onclick = () => startSender('camera');
    if (btnScr) btnScr.onclick = () => startSender('screen');
  }
''';
