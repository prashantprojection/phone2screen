import 'dart:convert';

import 'web_companion_mode.dart';
import 'web_companion_script.dart';

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

  final pinBlock = requiresPin
      ? '<label class="field"><span>Session PIN</span>'
            '<input id="pin" type="password" inputmode="numeric" '
            'placeholder="Enter PIN" autocomplete="off" /></label>'
      : '';

  final httpsAction = httpsPort != null
      ? '<button id="btnHttps" type="button">Switch to Secure HTTPS (:$httpsPort)</button>'
      : '';

  final isViewer = mode == .viewSenderStream;
  final subtitle = isViewer
      ? 'Watching live video from $escapedName on your Wi-Fi'
      : 'Stream your camera or screen to $escapedName on your Wi-Fi';

  final topNotice = isViewer
      ? ''
      : _senderHttpsBanner.replaceAll('__HTTPS_BTN__', httpsAction);

  final controlsBlock = isViewer
      ? _viewerControlsTemplate.replaceAll('__PIN_BLOCK__', pinBlock)
      : _senderControlsTemplate.replaceAll('__PIN_BLOCK__', pinBlock);

  final clipTargetLabel = isViewer ? 'Send to Sender' : 'Send to Screen';
  const clipPlaceholder = 'Type or paste a link or note to share...';

  return _companionShellTemplate
      .replaceAll('__ESCAPED_NAME__', escapedName)
      .replaceAll('__SUBTITLE__', subtitle)
      .replaceAll('__TOP_NOTICE__', topNotice)
      .replaceAll('__CONTROLS__', controlsBlock)
      .replaceAll('__CLIP_BTN__', clipTargetLabel)
      .replaceAll('__CLIP_PLACEHOLDER__', clipPlaceholder)
      .replaceAll(
        '__SCRIPT_BODY__',
        webCompanionScript.replaceAll('__CFG_JSON__', cfgJson),
      );
}

const String _senderHttpsBanner = r'''
  <div id="secBanner" class="card warn" style="display:none">
    <div style="font-weight:700">Secure Link Required for Camera or Screen</div>
    <div class="sub">Browsers require a secure link before sharing your camera or screen. Tap <strong>Switch to Secure HTTPS</strong> below, then tap <em>Advanced &rarr; Proceed</em> once — or open <code>localhost</code> on the same PC.</div>
    <div class="clip-actions">__HTTPS_BTN__<button id="btnLocal" class="sec" type="button">Open on Same PC (localhost)</button></div>
  </div>''';

const String _senderControlsTemplate = r'''
  <div class="card">
    <div class="controls">
      __PIN_BLOCK__
      <label class="field"><span>Camera</span><select id="lens"><option value="environment">Back Camera</option><option value="user">Front Camera</option></select></label>
      <label class="chk"><input id="mic" type="checkbox" /><span>Include Mic</span></label>
      <button id="btnCam" type="button">Stream Camera</button>
      <button id="btnScr" class="sec" type="button">Share Screen</button>
      <button id="btnStop" class="stop" type="button" disabled>Stop</button>
    </div>
    <div id="err" class="err-box"></div>
  </div>''';

const String _viewerControlsTemplate = r'''
  <div class="card">
    <div class="controls">
      __PIN_BLOCK__
      <button id="btnWatch" type="button">Watch Stream</button>
      <button id="btnMute" class="sec" type="button">Unmute Audio</button>
      <button id="btnFs" class="sec" type="button">Fullscreen</button>
      <button id="btnStop" class="stop" type="button" disabled>Disconnect</button>
    </div>
    <div id="err" class="err-box"></div>
  </div>''';

const String _companionShellTemplate = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Phone2Screen Web • __ESCAPED_NAME__</title>
<style>
:root{color-scheme:dark;--bg:#0A0E17;--card:#141A26;--el:#1C2434;--bd:#28334A;--pri:#2F6BFF;--ok:#10B981;--warn:#F59E0B;--err:#EF4444;--tx:#F3F6FC;--mut:#94A3B8}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:18px}
.wrap{max-width:780px;margin:0 auto;display:grid;gap:16px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:16px;padding:18px}
.warn{border-color:rgba(245,158,11,.55);background:rgba(245,158,11,.08);display:grid;gap:10px}
.top{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px}
.brand{font-weight:700;font-size:18px;letter-spacing:-.2px}.sub{color:var(--mut);font-size:13px}
.badges{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.pill{padding:5px 11px;border-radius:999px;background:var(--el);border:1px solid var(--bd);font-size:12px;font-weight:600}
.pill.ok{border-color:rgba(16,185,129,.45);color:var(--ok)}.pill.err{border-color:rgba(239,68,68,.45);color:var(--err)}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:end}
.field{display:grid;gap:5px;flex:1 1 160px;font-size:12px;color:var(--mut)}
input,select,textarea{background:var(--el);color:var(--tx);border:1px solid var(--bd);border-radius:10px;padding:9px 11px;font:inherit;outline:none}
input:focus,textarea:focus{border-color:var(--pri)}
.chk{display:flex;align-items:center;gap:8px;padding:9px 12px;background:var(--el);border:1px solid var(--bd);border-radius:10px;cursor:pointer;user-select:none;font-size:13px}
button{border:0;border-radius:10px;padding:10px 15px;font:600 13px inherit;cursor:pointer;color:#fff;background:var(--pri)}
button.sec{background:var(--el);border:1px solid var(--bd);color:var(--tx)}
button.stop{background:var(--err)}button:disabled{opacity:.45;cursor:not-allowed}
video{width:100%;min-height:200px;max-height:460px;background:#05070B;border-radius:12px;border:1px solid var(--bd);object-fit:contain;display:block}
.clip-row{display:grid;gap:10px;margin-top:12px}.clip-actions{display:flex;gap:8px;flex-wrap:wrap}
.err-box{color:#FCA5A5;font-size:13px;margin-top:8px;min-height:18px}
</style>
</head>
<body>
<div class="wrap">
  <div class="card top">
    <div><div class="brand">Phone2Screen Web</div><div class="sub">__SUBTITLE__</div></div>
    <div class="badges"><span id="status" class="pill">Ready</span><span id="rtt" class="pill">RTT -- ms</span></div>
  </div>
  __TOP_NOTICE__
  __CONTROLS__
  <div class="card"><video id="preview" autoplay playsinline muted></video></div>
  <details class="card">
    <summary style="cursor:pointer;font-weight:600">Share Text (Clipboard)</summary>
    <div class="clip-row">
      <textarea id="clipOut" rows="2" placeholder="__CLIP_PLACEHOLDER__"></textarea>
      <div class="clip-actions">
        <button id="btnClipSend" type="button" disabled>__CLIP_BTN__</button>
        <button id="btnClipCopy" class="sec" type="button" disabled>Copy Received Text</button>
      </div>
      <div id="clipIn" class="sub">No shared text received yet.</div>
    </div>
  </details>
</div>
<script>
__SCRIPT_BODY__
</script>
</body>
</html>''';
