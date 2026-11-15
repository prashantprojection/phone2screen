/// Responsive CSS styles for the Browser Web Companion (`GET /`), providing a
/// full-viewport `100dvh` native-app shell across phones, tablets, and desktops.
const String webCompanionStyles = r'''
:root{
  color-scheme:dark;
  --bg:#0F0F11;--surf:rgba(24,25,28,.88);--el:rgba(35,37,42,.92);--bd:rgba(255,255,255,.11);
  --pri:#3B82F6;--pri2:#06B6D4;--ok:#10B981;--warn:#F59E0B;--err:#F43F5E;--tx:#F3F4F6;--mut:#9AA0A6;
}
*,*::before,*::after{box-sizing:border-box}
html,body{height:100%;margin:0;overflow:hidden;background:var(--bg);color:var(--tx);font:15px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;-webkit-font-smoothing:antialiased}
[hidden]{display:none !important}
.app{
  position:relative;height:100vh;height:100dvh;width:100%;overflow:hidden;background:var(--bg);
}
.topbar{
  position:absolute;top:0;left:0;right:0;z-index:20;
  display:flex;align-items:center;justify-content:space-between;gap:8px;
  padding:calc(8px + env(safe-area-inset-top)) calc(12px + env(safe-area-inset-right)) 8px calc(12px + env(safe-area-inset-left));
  background:rgba(15,15,17,.72);-webkit-backdrop-filter:blur(18px);backdrop-filter:blur(18px);
  border-bottom:1px solid rgba(255,255,255,.08);
}
.brand-wrap{display:flex;align-items:center;gap:8px;min-width:0}
.brand-mark{
  width:28px;height:28px;border-radius:8px;flex:0 0 auto;display:grid;place-items:center;
  background:linear-gradient(135deg,var(--pri),var(--pri2));color:#fff;
}
.brand-name{font-weight:700;font-size:15px;letter-spacing:-.2px;white-space:nowrap}
.device-pill{max-width:110px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--mut)}
.top-actions{display:flex;align-items:center;gap:6px;flex-shrink:0}
.pill{
  padding:5px 10px;border-radius:999px;background:var(--el);border:1px solid var(--bd);
  font-size:12px;font-weight:600;white-space:nowrap;line-height:1.2;
}
.pill.ok{border-color:rgba(16,185,129,.45);color:var(--ok);background:rgba(16,185,129,.12)}
.pill.err{border-color:rgba(244,63,94,.45);color:#FDA4AF;background:rgba(244,63,94,.14)}
.btn-icon{
  position:relative;min-width:44px;min-height:44px;padding:0 12px;border-radius:999px;
  border:1px solid var(--bd);background:var(--el);color:var(--tx);cursor:pointer;
  display:inline-flex;align-items:center;justify-content:center;gap:6px;font:600 13px inherit;
  touch-action:manipulation;-webkit-tap-highlight-color:transparent;
}
.btn-icon .btn-label{display:none}
.badge-dot{
  position:absolute;top:7px;right:7px;width:9px;height:9px;border-radius:50%;
  background:var(--err);box-shadow:0 0 0 2px var(--bg);
}
.stage{
  position:relative;width:100%;height:100vh;height:100dvh;overflow:hidden;
  display:flex;align-items:center;justify-content:center;background:#050608;
}
#preview{
  width:100%;height:100%;object-fit:contain;display:block;transform-origin:center center;
  transform:scaleX(var(--sx,1)) rotate(var(--deg,0deg)) scale(var(--rscale,1));
  transition:transform .18s ease;
}
#preview.fit-cover{object-fit:cover}
#preview.mirrored{--sx:-1}
#preview.rot-0{--deg:0deg}
#preview.rot-90{--deg:90deg}
#preview.rot-180{--deg:180deg}
#preview.rot-270{--deg:270deg}
.stage.is-live .hero-wrap{display:none}
.hero-wrap{
  position:absolute;inset:0;z-index:10;display:flex;align-items:center;justify-content:center;
  padding:68px 14px 78px;overflow-y:auto;
  background:radial-gradient(circle at center,rgba(24,25,28,.72),rgba(5,6,8,.94));
}
.hero{
  width:100%;max-width:420px;margin:auto;padding:22px;border-radius:20px;display:grid;gap:12px;
  background:var(--surf);-webkit-backdrop-filter:blur(22px);backdrop-filter:blur(22px);
  border:1px solid var(--bd);box-shadow:0 20px 48px rgba(0,0,0,.55);
}
.hero-title{font-weight:700;font-size:18px;letter-spacing:-.2px}
.hero-sub{color:var(--mut);font-size:13px;margin-top:-6px}
.warn{
  display:grid;gap:8px;padding:12px;border-radius:16px;
  border:1px solid rgba(245,158,11,.45);background:rgba(245,158,11,.1);font-size:13px;
}
.warn-title{font-weight:700;color:#FDE68A}
.hero-grid{display:grid;grid-template-columns:1fr auto;gap:10px;align-items:end}
.field{display:grid;gap:5px;font-size:12px;color:var(--mut)}
input,select,textarea{
  width:100%;min-height:46px;background:var(--el);color:var(--tx);border:1px solid var(--bd);
  border-radius:12px;padding:10px 12px;font:inherit;outline:none;
}
textarea{min-height:84px;resize:vertical}
input:focus,select:focus,textarea:focus{border-color:var(--pri)}
.chk{
  min-height:46px;display:inline-flex;align-items:center;gap:8px;padding:0 12px;border-radius:12px;
  background:var(--el);border:1px solid var(--bd);cursor:pointer;user-select:none;font-size:13px;font-weight:600;
}
.chk input{width:18px;height:18px;min-height:0;margin:0;accent-color:var(--pri)}
.btn-pri,.btn-sec,.btn-sm{
  min-height:46px;border:0;border-radius:999px;padding:11px 18px;font:600 14px inherit;cursor:pointer;
  color:#fff;background:linear-gradient(135deg,var(--pri),#2563EB);touch-action:manipulation;
}
.btn-sec,.btn-sm{background:var(--el);border:1px solid var(--bd);color:var(--tx)}
.btn-sm{min-height:42px;min-width:44px;padding:8px 14px;font-size:12px}
.btn-row{display:grid;grid-template-columns:1fr 1fr;gap:10px}
button:disabled{opacity:.42;cursor:not-allowed}
.err-box{color:#FDA4AF;font-size:13px;min-height:18px;word-break:break-word}
.float-pill{
  position:absolute;z-index:12;min-height:44px;padding:10px 16px;border-radius:999px;
  border:1px solid rgba(96,165,250,.45);background:rgba(24,25,28,.86);
  -webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);
  color:#fff;font:600 13px inherit;cursor:pointer;display:inline-flex;align-items:center;gap:8px;
  box-shadow:0 10px 28px rgba(0,0,0,.45);touch-action:manipulation;
}
.unmute-pill{top:calc(68px + env(safe-area-inset-top));left:50%;transform:translateX(-50%);border-color:rgba(59,130,246,.7)}
.fs-toast{
  position:absolute;top:calc(68px + env(safe-area-inset-top));left:50%;transform:translateX(-50%);
  z-index:15;pointer-events:none;padding:8px 14px;border-radius:999px;
  background:rgba(24,25,28,.86);border:1px solid var(--bd);font-size:12px;font-weight:600;
  white-space:nowrap;-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);
}
.stage:fullscreen .unmute-pill,.stage:-webkit-full-screen .unmute-pill,.stage.is-fs .unmute-pill,
.stage:fullscreen .fs-toast,.stage:-webkit-full-screen .fs-toast,.stage.is-fs .fs-toast{top:16px}
.fs-hud{
  display:none;position:absolute;bottom:calc(18px + env(safe-area-inset-bottom));right:18px;z-index:14;
  gap:8px;align-items:center;padding:6px;border-radius:999px;
  background:rgba(24,25,28,.82);border:1px solid var(--bd);
  -webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);
}
.stage:fullscreen .fs-hud,.stage:-webkit-full-screen .fs-hud,.stage.is-fs .fs-hud{display:flex}
.stage.hud-hidden .fs-hud,.stage.hud-hidden .unmute-pill{opacity:0;pointer-events:none}
.dock{
  position:absolute;left:0;right:0;bottom:0;z-index:20;
  display:flex;align-items:center;gap:4px;width:100%;
  padding:6px calc(8px + env(safe-area-inset-right)) calc(6px + env(safe-area-inset-bottom)) calc(8px + env(safe-area-inset-left));
  background:rgba(15,15,17,.78);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);
  border-top:1px solid rgba(255,255,255,.09);
  overflow-x:auto;overflow-y:hidden;-webkit-overflow-scrolling:touch;scrollbar-width:none;
}
.dock::-webkit-scrollbar{display:none}
.btn-dock{
  position:relative;flex:0 0 auto;min-height:46px;min-width:46px;padding:6px 10px;border-radius:12px;
  border:1px solid transparent;background:transparent;color:var(--tx);cursor:pointer;
  display:inline-flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;
  font:600 11px/1.1 inherit;touch-action:manipulation;-webkit-tap-highlight-color:transparent;
  transition:background .15s,border-color .15s,color .15s;
}
.btn-dock.active{background:rgba(59,130,246,.22);border-color:rgba(96,165,250,.48);color:#93C5FD}
.btn-dock.warn-active{background:rgba(245,158,11,.22);border-color:rgba(245,158,11,.55);color:#FCD34D}
.btn-dock.stop{background:rgba(244,63,94,.16);border-color:rgba(244,63,94,.38);color:#FDA4AF}
.btn-dock span{white-space:nowrap}
.btn-dock .ico-off{display:none}
.btn-dock.is-muted .ico-on{display:none}
.btn-dock.is-muted .ico-off{display:block;color:#FDA4AF}
.sheet{
  position:fixed;inset:0;z-index:40;display:flex;align-items:flex-end;justify-content:center;
}
.sheet-backdrop{position:absolute;inset:0;background:rgba(0,0,0,.65);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}
.sheet-card{
  position:relative;width:100%;max-width:520px;background:var(--surf);border:1px solid var(--bd);
  -webkit-backdrop-filter:blur(22px);backdrop-filter:blur(22px);
  border-radius:24px 24px 0 0;padding:10px 18px calc(18px + env(safe-area-inset-bottom));
  display:grid;gap:14px;box-shadow:0 -12px 40px rgba(0,0,0,.55);
  animation:sheetUp .2s ease-out;
}
@keyframes sheetUp{from{transform:translateY(28px);opacity:0}to{transform:translateY(0);opacity:1}}
.sheet-handle{width:38px;height:4px;border-radius:999px;background:var(--bd);margin:0 auto}
.sheet-head{display:flex;align-items:center;justify-content:space-between;font-weight:700;font-size:16px}
.sheet-sec{display:grid;gap:8px}
.sheet-row{display:flex;align-items:center;justify-content:space-between;gap:8px}
.sheet-label{font-size:12px;font-weight:600;color:var(--mut);text-transform:uppercase;letter-spacing:.4px}
.clip-in{
  min-height:46px;max-height:110px;overflow-y:auto;padding:10px 12px;border-radius:14px;
  background:var(--el);border:1px solid var(--bd);font-size:13px;color:var(--tx);word-break:break-word;
}
@media(min-width:480px){
  .btn-icon .btn-label{display:inline}
  .device-pill{max-width:180px}
}
@media(min-width:640px){
  .topbar{padding:10px 20px}
  .device-pill{max-width:260px}
  .dock{
    left:50%;right:auto;bottom:calc(16px + env(safe-area-inset-bottom));transform:translateX(-50%);
    width:max-content;max-width:calc(100% - 32px);border:1px solid var(--bd);border-radius:999px;
    padding:6px 12px;background:rgba(24,25,28,.82);box-shadow:0 12px 36px rgba(0,0,0,.5);
  }
  .btn-dock{min-width:60px;border-radius:999px;padding:6px 12px}
  .sheet{align-items:center;padding:16px}
  .sheet-card{border-radius:20px;padding:18px}
  .sheet-handle{display:none}
}
''';
