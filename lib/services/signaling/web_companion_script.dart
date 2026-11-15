/// Embedded JavaScript runtime for the Browser Web Companion (`GET /`),
/// handling both `sender` (Camera/Screen -> Receiver) and `viewer`
/// (Sender -> Browser over plain HTTP) WebRTC sessions.
const String webCompanionScript = r'''
(function(){
  const CFG = __CFG_JSON__;
  const byId = (id) => document.getElementById(id);
  const statusEl = byId('status'), rttEl = byId('rtt'), errEl = byId('err'), preview = byId('preview');
  const btnCam = byId('btnCam'), btnScr = byId('btnScr'), btnStop = byId('btnStop');
  const btnWatch = byId('btnWatch'), btnMute = byId('btnMute'), btnFs = byId('btnFs');
  const btnClipSend = byId('btnClipSend'), btnClipCopy = byId('btnClipCopy');
  const clipOut = byId('clipOut'), clipIn = byId('clipIn');
  const secBanner = byId('secBanner'), btnHttps = byId('btnHttps'), btnLocal = byId('btnLocal');

  let ws = null, pc = null, dc = null, stream = null, pingTimer = null;
  let remoteDescSet = false, earlyIce = [], latestClip = '';
  const iceCfg = {iceServers: [{urls: 'stun:stun.l.google.com:19302'}]};

  function setStatus(txt, cls){ statusEl.textContent = txt; statusEl.className = 'pill' + (cls ? ' ' + cls : ''); }
  function setErr(msg){ errEl.textContent = msg || ''; }
  function sendSig(type, payload){ if (ws && ws.readyState === 1) ws.send(JSON.stringify({type, sessionId: CFG.sessionId, payload: payload || {}})); }

  function setControlsBusy(active){
    if (btnCam) btnCam.disabled = active;
    if (btnScr && typeof navigator !== 'undefined' && navigator.mediaDevices && typeof navigator.mediaDevices.getDisplayMedia === 'function'){
      btnScr.disabled = active;
    }
    if (btnWatch) btnWatch.disabled = active;
    if (btnStop) btnStop.disabled = !active;
  }

  function preferH264(sdp){
    if (!sdp) return sdp;
    const nl = sdp.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
    const lines = sdp.split(nl);
    let mIdx = -1, endIdx = lines.length;
    for (let i = 0; i < lines.length; i++){
      if (lines[i].startsWith('m=video ')) mIdx = i;
      else if (mIdx !== -1 && lines[i].startsWith('m=')){ endIdx = i; break; }
    }
    if (mIdx === -1) return sdp;
    const h264 = new Set();
    for (let i = mIdx + 1; i < endIdx; i++){
      const m = lines[i].match(/^a=rtpmap:(\d+)\s+H264\//i);
      if (m) h264.add(m[1]);
    }
    if (!h264.size) return sdp;
    const p = lines[mIdx].split(' ');
    if (p.length <= 3) return sdp;
    const pref = [], rest = [];
    for (const pt of p.slice(3)) (h264.has(pt) ? pref : rest).push(pt);
    if (!pref.length) return sdp;
    lines[mIdx] = [...p.slice(0, 3), ...pref, ...rest].join(' ');
    return lines.join(nl);
  }

  function describeError(err){
    if (!window.isSecureContext || !navigator.mediaDevices){
      return 'Browser blocked camera/screen on plain HTTP. Use the HTTPS link above or open localhost on this PC.';
    }
    const name = err && err.name ? err.name : '';
    const msg = err && err.message ? err.message : String(err);
    if (name === 'NotAllowedError' || name === 'PermissionDeniedError'){
      return 'Permission denied. Allow camera/microphone or screen-share access in your browser prompt.';
    }
    if (name === 'NotFoundError' || name === 'DevicesNotFoundError'){
      return 'No camera found on this device. Connect a webcam or use Share Screen.';
    }
    if (name === 'NotReadableError' || name === 'TrackStartError'){
      return 'Camera is already in use by another app. Close it and retry.';
    }
    if (name === 'OverconstrainedError'){
      return 'Requested camera resolution or lens is unavailable on this device.';
    }
    return msg;
  }

  async function flushEarlyIce(){
    // Drain candidates that arrived before setRemoteDescription completed.
    while (earlyIce.length > 0 && pc){
      const c = earlyIce.shift();
      if (c && c.candidate) await pc.addIceCandidate(new RTCIceCandidate(c)).catch(() => {});
    }
  }

  function cleanup(sendBye){
    if (pingTimer){ clearInterval(pingTimer); pingTimer = null; }
    if (sendBye) sendSig('bye', {reason: 'Browser stopped session'});
    if (dc){ try{ dc.close(); }catch(_){} dc = null; }
    if (pc){ try{ pc.close(); }catch(_){} pc = null; }
    if (ws){ try{ ws.onclose = null; ws.close(); }catch(_){} ws = null; }
    if (stream){ stream.getTracks().forEach((t) => t.stop()); stream = null; }
    preview.srcObject = null;
    remoteDescSet = false; earlyIce = [];
    btnClipSend.disabled = true; rttEl.textContent = 'RTT -- ms';
    setControlsBusy(false);
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

  function createPc(){
    const conn = new RTCPeerConnection(iceCfg);
    remoteDescSet = false; earlyIce = [];
    conn.onicecandidate = (e) => {
      if (e.candidate && e.candidate.candidate){
        sendSig('ice', {candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex});
      }
    };
    conn.onconnectionstatechange = () => {
      if (!pc || pc !== conn) return;
      if (conn.connectionState === 'connected') setStatus(CFG.mode === 'viewer' ? 'Watching' : 'Streaming', 'ok');
      else if (conn.connectionState === 'failed' || conn.connectionState === 'closed'){
        setStatus('Disconnected', 'err'); cleanup(false);
      }
    };
    return conn;
  }

  async function acquireMedia(kind, wantAudio, lens){
    if (kind === 'screen'){
      if (!navigator.mediaDevices || typeof navigator.mediaDevices.getDisplayMedia !== 'function'){
        throw new Error('Screen share requires a desktop browser or the Phone2Screen Android app. Try Stream Camera instead.');
      }
      try {
        return await navigator.mediaDevices.getDisplayMedia({video: true, audio: wantAudio});
      } catch (e) {
        if (!wantAudio || (e && (e.name === 'NotAllowedError' || e.name === 'AbortError'))) throw e;
        return await navigator.mediaDevices.getDisplayMedia({video: true, audio: false});
      }
    }
    const videoCfg = {facingMode: {ideal: lens}, width: {ideal: 1280}, height: {ideal: 720}};
    try {
      return await navigator.mediaDevices.getUserMedia({video: videoCfg, audio: wantAudio});
    } catch (firstErr) {
      if (firstErr && firstErr.name === 'NotAllowedError') throw firstErr;
      if (wantAudio){
        try { return await navigator.mediaDevices.getUserMedia({video: videoCfg, audio: false}); }
        catch (_) {}
      }
      return await navigator.mediaDevices.getUserMedia({video: true, audio: false});
    }
  }

  function openSocket(role, onOpenReady){
    const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
    ws = new WebSocket(proto + location.host + '/ws');
    ws.onopen = () => sendSig('hello', {deviceName: role === 'viewer' ? 'Web Viewer' : 'Web Browser', role, pin: onOpenReady});
    ws.onerror = () => { setErr('WebSocket signaling failed.'); setStatus('Error', 'err'); cleanup(false); };
    ws.onclose = () => { if (ws) { setStatus('Disconnected', ''); cleanup(false); } };
  }

  async function startSender(mode){
    setErr('');
    const pinEl = byId('pin');
    const pin = pinEl ? pinEl.value.trim() : '';
    if (CFG.requiresPin && !pin){ setErr('Please enter the session PIN first.'); if (pinEl) pinEl.focus(); return; }
    try {
      const wantAudio = Boolean(byId('mic') && byId('mic').checked);
      const lens = byId('lens') ? byId('lens').value : 'environment';
      stream = await acquireMedia(mode, wantAudio, lens);
      const vTrack = stream.getVideoTracks()[0];
      if (vTrack) vTrack.onended = () => { setStatus('Stopped', ''); cleanup(true); };
      preview.srcObject = stream;
      setControlsBusy(true);
      setStatus('Connecting...', '');
      openSocket('sender', pin);
      ws.onmessage = async (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === 'welcome'){
            pc = createPc();
            stream.getTracks().forEach((t) => pc.addTrack(t, stream));
            setupDataChannel(pc.createDataChannel('phone2screen-control', {ordered: true}));
            const raw = await pc.createOffer();
            const offer = {type: raw.type, sdp: preferH264(raw.sdp)};
            await pc.setLocalDescription(offer);
            sendSig('offer', offer);
          } else if (msg.type === 'answer'){
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
        } catch (err) { setErr(describeError(err)); setStatus('Failed', 'err'); cleanup(false); }
      };
    } catch (err) {
      setErr(describeError(err));
      setStatus('Failed', 'err'); cleanup(false);
    }
  }

  async function startViewer(){
    setErr('');
    const pinEl = byId('pin');
    const pin = pinEl ? pinEl.value.trim() : '';
    if (CFG.requiresPin && !pin){ setErr('Please enter the session PIN first.'); if (pinEl) pinEl.focus(); return; }
    cleanup(false);
    setControlsBusy(true);
    setStatus('Connecting...', '');
    try {
      openSocket('viewer', pin);
      ws.onmessage = async (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === 'welcome'){
            setStatus('Waiting stream...', '');
          } else if (msg.type === 'offer'){
            if (pc) try{ pc.close(); }catch(_){}
            pc = createPc();
            pc.ondatachannel = (e) => setupDataChannel(e.channel);
            pc.ontrack = (e) => {
              preview.srcObject = (e.streams && e.streams[0]) || new MediaStream([e.track]);
              preview.play().catch(() => {});
            };
            await pc.setRemoteDescription(new RTCSessionDescription(msg.payload));
            remoteDescSet = true;
            await flushEarlyIce();
            const raw = await pc.createAnswer();
            const answer = {type: raw.type, sdp: preferH264(raw.sdp)};
            await pc.setLocalDescription(answer);
            sendSig('answer', answer);
          } else if (msg.type === 'ice'){
            if (!remoteDescSet) earlyIce.push(msg.payload);
            else if (msg.payload && msg.payload.candidate) await pc.addIceCandidate(new RTCIceCandidate(msg.payload));
          } else if (msg.type === 'error'){
            setErr((msg.payload && msg.payload.message) || 'Connection rejected.');
            setStatus('Rejected', 'err'); cleanup(false);
          } else if (msg.type === 'bye'){
            setStatus('Sender ended', ''); cleanup(false);
          }
        } catch (err) { setErr(describeError(err)); setStatus('Failed', 'err'); cleanup(false); }
      };
    } catch (err) {
      setErr(describeError(err));
      setStatus('Failed', 'err'); cleanup(false);
    }
  }

  if (CFG.mode === 'viewer'){
    if (btnWatch) btnWatch.onclick = startViewer;
    if (btnMute) btnMute.onclick = () => {
      preview.muted = !preview.muted;
      btnMute.textContent = preview.muted ? 'Unmute Audio' : 'Mute Audio';
      preview.play().catch(() => {});
    };
    if (btnFs) btnFs.onclick = () => {
      if (preview.requestFullscreen) preview.requestFullscreen().catch(() => {});
      else if (preview.webkitEnterFullscreen) preview.webkitEnterFullscreen();
    };
    if (!CFG.requiresPin) startViewer();
  } else {
    const secureOk = window.isSecureContext && navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function';
    if (!secureOk){
      if (secBanner) secBanner.style.display = 'grid';
      if (btnCam) btnCam.disabled = true;
      if (btnScr) btnScr.disabled = true;
      setStatus('HTTPS Required', 'err');
      if (btnHttps && CFG.httpsPort){
        btnHttps.onclick = () => { location.href = 'https://' + location.hostname + ':' + CFG.httpsPort + '/'; };
      }
      if (btnLocal){
        btnLocal.onclick = () => { location.href = 'http://localhost:' + CFG.httpPort + '/'; };
      }
    } else if (btnScr && typeof navigator.mediaDevices.getDisplayMedia !== 'function'){
      btnScr.disabled = true;
      btnScr.title = 'Screen share requires a desktop browser or the Phone2Screen Android app; use Stream Camera here.';
    }
    if (btnCam) btnCam.onclick = () => startSender('camera');
    if (btnScr) btnScr.onclick = () => startSender('screen');
  }

  if (btnStop) btnStop.onclick = () => { setStatus('Stopped', ''); cleanup(true); };
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
''';
