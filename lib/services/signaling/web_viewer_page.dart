import 'dart:convert';

import 'web_companion_mode.dart';
import 'web_companion_script.dart';
import 'web_companion_styles.dart';
import 'web_companion_ui_script.dart';

/// Builds the self-contained HTML5/CSS/JS Browser Web Companion served at
/// `GET /` by `SignalingServerService`, supporting both `sendToReceiver`
/// (Browser -> Receiver) and `viewSenderStream` (Sender -> Browser) flows.
String buildWebCompanionHtml({
  required String sessionId,
  required String deviceName,
  required bool requiresPin,
  WebCompanionMode mode = .sendToReceiver,
  int httpPort = 8080,
  int? httpsPort,
}) {
  final escapedName = const HtmlEscape().convert(deviceName);
  // Escape '</' so a deviceName containing '</script>' cannot close the script tag.
  final cfgJson = jsonEncode({
    'sessionId': sessionId,
    'deviceName': deviceName,
    'requiresPin': requiresPin,
    'mode': mode == .viewSenderStream ? 'viewer' : 'sender',
    'httpPort': httpPort,
    'httpsPort': httpsPort,
  }).replaceAll('</', r'<\/');

  final isViewer = mode == .viewSenderStream;
  final pinBlock = requiresPin
      ? '<label class="field"><span>Session PIN</span><input id="pin" type="password" inputmode="numeric" placeholder="Enter PIN" autocomplete="off" /></label>'
      : '';
  final httpsBtn = httpsPort != null
      ? '<button id="btnHttps" class="btn-pri" type="button">Switch to Secure HTTPS (:$httpsPort)</button>'
      : '';
  final hero = (isViewer ? _viewerHero : _senderHero)
      .replaceAll('__ESCAPED_NAME__', escapedName)
      .replaceAll('__PIN_BLOCK__', pinBlock)
      .replaceAll('__HTTPS_BTN__', httpsBtn);

  final dock = _dockButtons(isViewer);
  final script = '(function(){\n${webCompanionScript.replaceAll('__CFG_JSON__', cfgJson)}\n$webCompanionUiScript\n})();';

  return _shellTemplate
      .replaceAll('__ESCAPED_NAME__', escapedName)
      .replaceAll('__STYLES__', webCompanionStyles)
      .replaceAll('__HERO__', hero)
      .replaceAll('__DOCK__', dock)
      .replaceAll('__CLIP_BTN__', isViewer ? 'Send to Sender' : 'Send to Screen')
      .replaceAll('__SCRIPT__', script);
}

String _ico(String d, {String cls = '', int s = 20}) =>
    '<svg class="$cls" width="$s" height="$s" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">$d</svg>';

String _btn(String id, String icon, String label, {String cls = '', bool off = false, String extra = ''}) =>
    '<button id="$id" class="btn-dock $cls" type="button"${off ? ' disabled' : ''}>$icon<span>$label</span>$extra</button>';

const _iSoundOn = '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>';
const _iSoundOff = '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/>';
const _iMicOn = '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/>';
const _iMicOff = '<line x1="2" y1="2" x2="22" y2="22"/><path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"/><path d="M5 10v2a7 7 0 0 0 12 5"/><path d="M15 9.34V5a3 3 0 0 0-5.68-1.33"/>';
const _iFit = '<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>';
const _iRot = '<path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/>';
const _iMir = '<path d="M8 3H5a2 2 0 0 0-2 2v14c0 1.1.9 2 2 2h3M16 3h3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-3M12 20v2M12 14v2M12 8v2M12 2v2"/>';
const _iStats = '<polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>';
const _iTxt = '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>';
const _iFs = '<path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/>';
const _iFlip = '<path d="M11 19H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h5M13 5h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-5"/><circle cx="12" cy="12" r="3"/><path d="m18 22-3-3 3-3M6 2l3 3-3 3"/>';
const _iCam = '<path d="m22 8-6 4 6 4V8Z"/><rect x="2" y="6" width="14" height="12" rx="2"/>';
const _iScr = '<rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>';
const _iStop = '<rect x="5" y="5" width="14" height="14" rx="2"/>';

String _dockButtons(bool isViewer) => (isViewer
    ? [
        _btn('btnMute', _ico(_iSoundOn, cls: 'ico-on') + _ico(_iSoundOff, cls: 'ico-off'), 'Muted', cls: 'is-muted'),
        _btn('btnFit', _ico(_iFit), 'Fit'),
        _btn('btnRotate', _ico(_iRot), 'Rotate'),
        _btn('btnMirror', _ico(_iMir), 'Mirror'),
        _btn('btnStats', _ico(_iStats), 'Stats'),
        _btn('btnClipOpenDock', _ico(_iTxt), 'Text', extra: '<span id="clipDockBadge" class="badge-dot" hidden></span>'),
        _btn('btnFs', _ico(_iFs), 'Fullscreen'),
        _btn('btnStop', _ico(_iStop), 'End', cls: 'stop', off: true),
      ]
    : [
        _btn('btnFlip', _ico(_iFlip), 'Flip Cam', off: true),
        _btn('btnMic', _ico(_iMicOn, cls: 'ico-on') + _ico(_iMicOff, cls: 'ico-off'), 'Mic Off', cls: 'is-muted'),
        _btn('btnCamDock', _ico(_iCam), 'Camera'),
        _btn('btnScrDock', _ico(_iScr), 'Screen'),
        _btn('btnMirror', _ico(_iMir), 'Mirror'),
        _btn('btnStats', _ico(_iStats), 'Stats'),
        _btn('btnFs', _ico(_iFs), 'Fullscreen'),
        _btn('btnStop', _ico(_iStop), 'Stop', cls: 'stop', off: true),
      ]).join();

const String _viewerHero = r'''
  <div class="hero-title">Watch __ESCAPED_NAME__</div>
  <div class="hero-sub">Live low-latency stream over local Wi-Fi</div>
  __PIN_BLOCK__
  <button id="btnWatch" class="btn-pri" type="button">Watch Stream</button>
  <div id="err" class="err-box"></div>''';

const String _senderHero = r'''
  <div class="hero-title">Cast to __ESCAPED_NAME__</div>
  <div class="hero-sub">Share your camera or screen over local Wi-Fi</div>
  <div id="secBanner" class="warn" style="display:none">
    <div class="warn-title">Secure Link Required for Camera or Screen</div>
    <div>Browsers require HTTPS before sharing camera or screen. Tap <strong>Switch to Secure HTTPS</strong>, then <em>Advanced &rarr; Proceed</em> once.</div>
    __HTTPS_BTN__<button id="btnLocal" class="btn-sec" type="button">Open on Same PC (localhost)</button>
  </div>
  __PIN_BLOCK__
  <div class="hero-grid">
    <label class="field"><span>Camera Lens</span><select id="lens"><option value="environment">Back Camera</option><option value="user">Front Camera</option></select></label>
    <label class="chk"><input id="mic" type="checkbox" /><span>Include Mic</span></label>
  </div>
  <div class="btn-row">
    <button id="btnCam" class="btn-pri" type="button">Stream Camera</button>
    <button id="btnScr" class="btn-sec" type="button">Share Screen</button>
  </div>
  <div id="err" class="err-box"></div>''';

const String _shellTemplate = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover" />
<meta name="theme-color" content="#0A0E17" />
<title>Phone2Screen • __ESCAPED_NAME__</title>
<style>__STYLES__</style>
</head>
<body>
<div class="app">
  <header class="topbar">
    <div class="brand-wrap">
      <div class="brand-mark"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></svg></div>
      <span class="brand-name">Phone2Screen</span>
      <span class="pill device-pill">__ESCAPED_NAME__</span>
    </div>
    <div class="top-actions">
      <span id="status" class="pill">Ready</span>
      <span id="rtt" class="pill" hidden>RTT -- ms</span>
      <button id="btnClipOpen" class="btn-icon" type="button" title="Share Text (C)" aria-label="Share Text">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
        <span class="btn-label">Text</span><span id="clipBadge" class="badge-dot" hidden></span>
      </button>
    </div>
  </header>
  <main id="stage" class="stage">
    <video id="preview" class="rot-0" autoplay playsinline muted></video>
    <button id="unmutePill" class="float-pill unmute-pill" type="button" hidden>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
      <span>Tap for Sound</span>
    </button>
    <div id="fsToast" class="fs-toast" hidden>Press Esc or tap video to toggle controls</div>
    <div id="fsHud" class="fs-hud">
      <button id="btnHideHud" class="btn-sm" type="button">Hide</button>
      <button id="btnFsExit" class="btn-sm" type="button">Exit</button>
    </div>
    <div id="heroCard" class="hero-wrap"><div class="hero">__HERO__</div></div>
  </main>
  <nav id="dock" class="dock" aria-label="Controls">__DOCK__</nav>
</div>
<div id="clipSheet" class="sheet" hidden>
  <div id="clipBackdrop" class="sheet-backdrop"></div>
  <div class="sheet-card" role="dialog" aria-modal="true" aria-labelledby="clipTitle">
    <div class="sheet-handle"></div>
    <div class="sheet-head">
      <span id="clipTitle">Share Text</span>
      <button id="btnClipClose" class="btn-icon" type="button" aria-label="Close"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>
    <div class="sheet-sec">
      <div class="sheet-row"><span class="sheet-label">Received</span><button id="btnClipCopy" class="btn-sm" type="button" disabled>Copy</button></div>
      <div id="clipIn" class="clip-in">No shared text received yet.</div>
    </div>
    <div class="sheet-sec">
      <textarea id="clipOut" rows="3" placeholder="Type or paste a link or note to share..."></textarea>
      <button id="btnClipSend" class="btn-pri" type="button" disabled>__CLIP_BTN__</button>
    </div>
  </div>
</div>
<script>__SCRIPT__</script>
</body>
</html>''';
