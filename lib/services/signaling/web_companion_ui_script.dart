/// Embedded JavaScript UI controller for the Browser Web Companion (`GET /`),
/// executed inside the shared IIFE alongside [webCompanionScript].
const String webCompanionUiScript = r'''
  const stage = byId('stage'), unmutePill = byId('unmutePill'), fsToast = byId('fsToast');
  const btnMute = byId('btnMute'), btnFit = byId('btnFit'), btnRotate = byId('btnRotate');
  const btnMirror = byId('btnMirror'), btnStats = byId('btnStats'), btnFs = byId('btnFs');
  const btnFlip = byId('btnFlip'), btnMic = byId('btnMic');
  const btnCamDock = byId('btnCamDock'), btnScrDock = byId('btnScrDock');
  const btnRemoteFlip = byId('btnRemoteFlip'), btnRemoteTorch = byId('btnRemoteTorch');
  const btnRemoteZoom = byId('btnRemoteZoom'), btnObsLink = byId('btnObsLink');
  const clipSheet = byId('clipSheet'), clipBadge = byId('clipBadge'), clipDockBadge = byId('clipDockBadge');

  let rot = 0, mirrored = false, coverFit = false, showStats = false;
  let stageLive = false, fsTimer = null, copyTimer = null, sendTimer = null, obsTimer = null;
  const origSendLabel = btnClipSend ? btnClipSend.textContent : 'Send';
  const onClick = (id, fn) => { const el = byId(id); if (el) el.onclick = fn; };
  const setLbl = (el, txt) => { const s = el && el.querySelector('span'); if (s) s.textContent = txt; };
  const isFs = () => Boolean(document.fullscreenElement || document.webkitFullscreenElement);

  // Scale 90/270-rotated video to fit #stage without clipping letterbox or video edges.
  function updateVideoTransform(){
    preview.className = 'rot-' + rot + (coverFit ? ' fit-cover' : '') + (mirrored ? ' mirrored' : '');
    if (rot !== 90 && rot !== 270){ preview.style.removeProperty('--rscale'); return; }
    const w = stage.clientWidth || 1, h = stage.clientHeight || 1;
    const vw = preview.videoWidth, vh = preview.videoHeight;
    let scale = coverFit ? Math.max(w / h, h / w) : Math.min(w / h, h / w);
    if (!coverFit && vw > 0 && vh > 0){
      const k = Math.min(w / vw, h / vh);
      scale = Math.min(w / (vh * k), h / (vw * k));
    }
    preview.style.setProperty('--rscale', scale.toFixed(4));
  }

  function showStageToast(msg){
    if (!fsToast) return;
    if (fsTimer){ clearTimeout(fsTimer); fsTimer = null; }
    fsToast.textContent = msg;
    fsToast.hidden = false;
    fsTimer = setTimeout(() => { fsToast.hidden = true; }, 3000);
  }

  function updateDockState(){
    const isViewer = CFG.mode === 'viewer', hasAudio = Boolean(stream && stream.getAudioTracks().length);
    const micEl = byId('mic'), canDisplay = canDisplayMedia(), secureOk = isSecureMediaReady();

    if (unmutePill) unmutePill.hidden = !(isViewer && stageLive && preview.muted);
    if (btnMute){
      btnMute.classList.toggle('is-muted', preview.muted);
      btnMute.classList.toggle('active', !preview.muted);
      setLbl(btnMute, preview.muted ? 'Muted' : 'Sound');
    }
    if (btnFit){ btnFit.classList.toggle('active', coverFit); setLbl(btnFit, coverFit ? 'Fill' : 'Fit'); }
    if (btnRotate){ btnRotate.classList.toggle('active', rot !== 0); setLbl(btnRotate, rot === 0 ? 'Rotate' : rot + '°'); }
    if (btnMirror) btnMirror.classList.toggle('active', mirrored);
    if (btnStats){ btnStats.classList.toggle('active', showStats); rttEl.hidden = !showStats; }
    if (btnFs){ const fs = isFs(); btnFs.classList.toggle('active', fs); setLbl(btnFs, fs ? 'Exit' : 'Fullscreen'); }

    if (!isViewer){
      if (btnFlip) btnFlip.disabled = !secureOk || !stream || activeSource !== 'camera';
      if (btnCamDock){ btnCamDock.disabled = !secureOk; btnCamDock.classList.toggle('active', activeSource === 'camera'); }
      if (btnScrDock){ btnScrDock.disabled = !secureOk || !canDisplay; btnScrDock.classList.toggle('active', activeSource === 'screen'); }
      if (btnMic){
        const muted = stream ? (!hasAudio || micMuted) : !(micEl && micEl.checked);
        btnMic.disabled = Boolean(stream && !hasAudio);
        btnMic.classList.toggle('is-muted', muted);
        btnMic.classList.toggle('active', !muted);
        setLbl(btnMic, stream && !hasAudio ? 'No Mic' : (muted ? 'Mic Off' : 'Mic On'));
      }
    } else {
      const dcOpen = Boolean(dc && dc.readyState === 'open'), rigOk = dcOpen && remoteCam.controlsSupported;
      if (btnRemoteFlip){
        btnRemoteFlip.disabled = !rigOk;
        btnRemoteFlip.classList.toggle('active', rigOk && remoteCam.lens === 'front');
        setLbl(btnRemoteFlip, dcOpen ? (remoteCam.lens === 'front' ? 'Front' : 'Back') : 'Flip Cam');
      }
      if (btnRemoteTorch){
        btnRemoteTorch.disabled = !rigOk;
        btnRemoteTorch.classList.toggle('warn-active', rigOk && remoteCam.torchOn);
        setLbl(btnRemoteTorch, remoteCam.torchOn ? 'Light On' : 'Light');
      }
      if (btnRemoteZoom){
        const canZoom = rigOk && remoteCam.maxZoom > 1.05;
        btnRemoteZoom.disabled = !canZoom;
        btnRemoteZoom.classList.toggle('active', canZoom && remoteCam.zoom >= 1.5);
        setLbl(btnRemoteZoom, remoteCam.zoom >= 1.5 ? remoteCam.zoom.toFixed(1).replace(/\.0$/, '') + 'x' : '1x');
      }
    }
  }

  function setStageLive(live){
    stageLive = Boolean(live);
    stage.classList.toggle('is-live', stageLive);
    updateDockState(); updateVideoTransform();
  }

  function onClipboardReceived(text){
    latestClip = text;
    if (clipIn) clipIn.textContent = text;
    if (btnClipCopy) btnClipCopy.disabled = false;
    if (clipSheet && clipSheet.hidden){
      if (clipBadge) clipBadge.hidden = false;
      if (clipDockBadge) clipDockBadge.hidden = false;
    }
  }

  function rotateVideo(){ rot = (rot + 90) % 360; updateVideoTransform(); updateDockState(); }
  function toggleMirror(){ mirrored = !mirrored; updateVideoTransform(); updateDockState(); }
  function toggleFit(){ coverFit = !coverFit; updateVideoTransform(); updateDockState(); }
  function toggleStats(){ showStats = !showStats; updateDockState(); }
  function setHudHidden(hidden){ stage.classList.toggle('hud-hidden', Boolean(hidden)); }

  function toggleViewerMute(forceUnmute){
    if (CFG.mode !== 'viewer') return;
    preview.muted = forceUnmute ? false : !preview.muted;
    preview.play().catch(() => {});
    updateDockState();
  }

  function toggleFullscreen(){
    if (isFs()){
      const exitFn = document.exitFullscreen || document.webkitExitFullscreen;
      if (exitFn) Promise.resolve(exitFn.call(document)).catch(() => {});
      return;
    }
    if (stage.requestFullscreen) stage.requestFullscreen().catch(() => {});
    else if (stage.webkitRequestFullscreen) stage.webkitRequestFullscreen();
    else if (preview.webkitEnterFullscreen) try{ preview.webkitEnterFullscreen(); }catch(_){}
  }

  function onFullscreenChange(){
    const inFs = isFs();
    stage.classList.toggle('is-fs', inFs);
    setHudHidden(false);
    if (inFs) showStageToast('Press Esc or tap video to toggle controls');
    else if (fsToast) fsToast.hidden = true;
    updateDockState();
    setTimeout(updateVideoTransform, 60);
  }

  function openClipSheet(){
    if (!clipSheet) return;
    clipSheet.hidden = false;
    if (clipBadge) clipBadge.hidden = true;
    if (clipDockBadge) clipDockBadge.hidden = true;
    if (clipOut && window.innerWidth >= 640) clipOut.focus();
  }
  function closeClipSheet(){ if (clipSheet) clipSheet.hidden = true; }

  async function copyText(text){
    if (!text) return;
    try { if (navigator.clipboard && navigator.clipboard.writeText){ await navigator.clipboard.writeText(text); return; } } catch (_) {}
    const ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;left:-9999px;opacity:0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } catch (_) {}
    document.body.removeChild(ta);
  }

  function buildObsUrl(){
    const base = location.origin + '/obs', pinEl = byId('pin'), pin = pinEl ? pinEl.value.trim() : '';
    return (CFG.requiresPin && pin) ? base + '?pin=' + encodeURIComponent(pin) : base;
  }

  onClick('btnMute', () => toggleViewerMute(false));
  onClick('unmutePill', (e) => { e.stopPropagation(); toggleViewerMute(true); });
  onClick('btnFit', toggleFit);
  onClick('btnRotate', rotateVideo);
  onClick('btnMirror', toggleMirror);
  onClick('btnRemoteFlip', () => sendCamCtrl('flip'));
  onClick('btnRemoteTorch', () => sendCamCtrl('torch', {enabled: !remoteCam.torchOn}));
  onClick('btnRemoteZoom', () => sendCamCtrl('zoom', {value: remoteCam.zoom >= 1.5 ? 1 : Math.min(2, remoteCam.maxZoom || 2)}));
  onClick('btnObsLink', async () => {
    await copyText(buildObsUrl());
    if (obsTimer) clearTimeout(obsTimer);
    if (btnObsLink){
      setLbl(btnObsLink, 'Copied!'); btnObsLink.classList.add('active');
      obsTimer = setTimeout(() => { setLbl(btnObsLink, 'OBS URL'); btnObsLink.classList.remove('active'); }, 1500);
    }
    showStageToast('OBS Clean Feed URL copied');
  });
  onClick('btnStats', toggleStats);
  onClick('btnFs', toggleFullscreen);
  onClick('btnHideHud', (e) => { e.stopPropagation(); setHudHidden(true); });
  onClick('btnFsExit', (e) => { e.stopPropagation(); toggleFullscreen(); });
  onClick('btnFlip', switchLiveCamera);
  onClick('btnMic', () => toggleLiveMic());
  onClick('btnCamDock', () => switchLiveSource('camera'));
  onClick('btnScrDock', () => switchLiveSource('screen'));
  onClick('btnStop', () => { setStatus('Stopped', ''); cleanup(true); });
  onClick('btnClipOpen', openClipSheet);
  onClick('btnClipOpenDock', openClipSheet);
  onClick('btnClipClose', closeClipSheet);
  onClick('clipBackdrop', closeClipSheet);

  const micChk = byId('mic'), pinEl = byId('pin');
  if (micChk) micChk.addEventListener('change', updateDockState);
  if (pinEl) pinEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter'){ e.preventDefault(); CFG.mode === 'viewer' ? startViewer() : startSender('camera'); }
  });
  if (btnClipSend) btnClipSend.onclick = () => {
    const text = clipOut ? clipOut.value : '';
    if (text && sendClipboardText(text)){
      clipOut.value = '';
      if (sendTimer) clearTimeout(sendTimer);
      btnClipSend.textContent = 'Sent!';
      sendTimer = setTimeout(() => { btnClipSend.textContent = origSendLabel; }, 1200);
    }
  };
  if (clipOut) clipOut.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter' && btnClipSend && !btnClipSend.disabled){ e.preventDefault(); btnClipSend.click(); }
  });
  if (btnClipCopy) btnClipCopy.onclick = async () => {
    if (!latestClip) return;
    await copyText(latestClip);
    if (copyTimer) clearTimeout(copyTimer);
    btnClipCopy.textContent = 'Copied!';
    copyTimer = setTimeout(() => { btnClipCopy.textContent = 'Copy'; }, 1800);
  };

  stage.addEventListener('click', (e) => {
    if (isFs() && !e.target.closest('button,.hero-wrap')) setHudHidden(!stage.classList.contains('hud-hidden'));
  });
  document.addEventListener('fullscreenchange', onFullscreenChange);
  document.addEventListener('webkitfullscreenchange', onFullscreenChange);
  preview.addEventListener('loadedmetadata', updateVideoTransform);
  window.addEventListener('resize', updateVideoTransform);
  if (typeof ResizeObserver === 'function') new ResizeObserver(updateVideoTransform).observe(stage);

  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const key = e.key.toLowerCase();
    if (key === 'escape'){
      if (clipSheet && !clipSheet.hidden){ e.preventDefault(); closeClipSheet(); }
      else if (isFs()) toggleFullscreen();
      return;
    }
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return;
    const actions = {
      f: toggleFullscreen, r: rotateVideo, h: toggleMirror, z: toggleFit, s: toggleStats,
      o: () => { if (isFs()) setHudHidden(!stage.classList.contains('hud-hidden')); },
      m: () => (CFG.mode === 'viewer' ? toggleViewerMute(false) : toggleLiveMic()),
      c: () => (clipSheet && !clipSheet.hidden ? closeClipSheet() : openClipSheet()),
    };
    if (actions[key]){ e.preventDefault(); actions[key](); }
  });

  window.addEventListener('beforeunload', () => cleanup(true));
  initCompanionSession();
  updateDockState();
  updateVideoTransform();
''';
