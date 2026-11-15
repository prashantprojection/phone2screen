import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/camera_control_state.dart';
import '../models/clipboard_item.dart';
import '../models/media_source_type.dart';
import 'session_sender_flow.dart';
import 'session_state.dart';
import 'settings_provider.dart';

/// Camera rig, privacy freeze-frame, source switch, and clipboard helpers.
class SessionCameraControls {
  const SessionCameraControls();

  /// Mutes or unmutes outgoing microphone audio and syncs `cam_state`.
  void toggleMicMute(SessionContext ctx) {
    final nextMuted = !ctx.currentState.isMicMuted;
    ctx.mediaCapture.setMicMuted(nextMuted);
    syncCameraState(ctx, ctx.currentState.remoteCameraState.copyWith(micMuted: nextMuted), isMicMuted: nextMuted);
  }

  /// Toggles privacy freeze-frame (`isVideoPaused`) on Receiver or Sender.
  void toggleVideoPause(SessionContext ctx) {
    final isReceiver = ctx.isHosting && !ctx.currentState.isWebBroadcast;
    final next = isReceiver ? !ctx.sessionRef.read(viewerDisplayProvider).isVideoPaused : !ctx.currentState.isVideoPaused;
    setVideoPaused(ctx, next);
  }

  /// Sets privacy freeze-frame (`paused`) and syncs tracks & control DC.
  void setVideoPaused(SessionContext ctx, bool paused) {
    if (ctx.isHosting && !ctx.currentState.isWebBroadcast) {
      ctx.sessionRef.read(viewerDisplayProvider.notifier).setVideoPaused(paused);
      ctx.currentState = ctx.currentState.copyWith(isVideoPaused: paused);
      ctx.webrtc.sendCameraCommand(RemoteCameraCommand(command: .videoPause, enabled: paused));
      return;
    }
    _setVideoTracksEnabled(ctx.currentState.localStream ?? ctx.mediaCapture.activeStream, enabled: !paused);
    syncCameraState(ctx, ctx.currentState.remoteCameraState.copyWith(videoPaused: paused), isVideoPaused: paused);
  }

  /// Switches between camera and screen share, preserving pause state.
  Future<void> changeSource(
    SessionContext ctx,
    SessionSenderFlow senderFlow,
    MediaSourceType source, {
    String? desktopSourceId,
  }) async {
    await senderFlow.changeSource(ctx, source, desktopSourceId: desktopSourceId);
    if (!ctx.isNotifierMounted) return;
    if (ctx.currentState.isVideoPaused) {
      _setVideoTracksEnabled(ctx.currentState.localStream ?? ctx.mediaCapture.activeStream, enabled: false);
    }
    syncCameraState(
      ctx,
      ctx.currentState.remoteCameraState.copyWith(
        torchOn: ctx.currentState.isTorchOn,
        zoom: 1.0,
        exposureOffset: 0.0,
        focusLocked: false,
        videoPaused: ctx.currentState.isVideoPaused,
        controlsSupported: source == .camera && ctx.mediaCapture.isCameraControlPlatform,
      ),
    );
  }

  /// Pushes current broadcaster camera hardware & pause snapshot on DC open.
  void publishCurrentCameraState(SessionContext ctx) {
    if (!ctx.isNotifierMounted) return;
    final cfg = ctx.sessionRef.read(streamConfigProvider);
    syncCameraState(
      ctx,
      ctx.currentState.remoteCameraState.copyWith(
        lens: cfg.cameraLens,
        torchOn: ctx.currentState.isTorchOn,
        micMuted: ctx.currentState.isMicMuted,
        voiceClean: cfg.voiceCleanAudio,
        videoPaused: ctx.currentState.isVideoPaused,
        controlsSupported: cfg.sourceType == .camera && ctx.mediaCapture.isCameraControlPlatform,
      ),
    );
  }

  /// Applies a local or remote `cam_ctrl` command on the active broadcaster.
  Future<void> applyLocalCameraCommand(SessionContext ctx, RemoteCameraCommand cmd) async {
    if (!ctx.isNotifierMounted) return;
    if (cmd.command == .videoPause) {
      setVideoPaused(ctx, cmd.enabled ?? !ctx.currentState.isVideoPaused);
      return;
    }
    final ref = ctx.sessionRef;
    final cfg = ref.read(streamConfigProvider);
    final prev = ctx.currentState.remoteCameraState.copyWith(
      lens: cfg.cameraLens,
      voiceClean: cfg.voiceCleanAudio,
      videoPaused: ctx.currentState.isVideoPaused,
    );
    final next = await ctx.mediaCapture.applyCameraCommand(cmd, prev);
    if (!ctx.isNotifierMounted) return;
    if (next.lens != cfg.cameraLens) ref.read(streamConfigProvider.notifier).setCameraLens(next.lens);
    if (next.voiceClean != prev.voiceClean) {
      ref.read(streamConfigProvider.notifier).setVoiceCleanAudio(next.voiceClean);
    }
    syncCameraState(ctx, next, isMicMuted: next.micMuted, isTorchOn: next.torchOn, isVideoPaused: next.videoPaused);
  }

  /// Updates [SessionState] and broadcasts `cam_state` when acting as Sender.
  void syncCameraState(
    SessionContext ctx,
    RemoteCameraState camState, {
    bool? isMicMuted,
    bool? isTorchOn,
    bool? isVideoPaused,
  }) {
    ctx.currentState = ctx.currentState.copyWith(
      remoteCameraState: camState, isMicMuted: isMicMuted, isTorchOn: isTorchOn, isVideoPaused: isVideoPaused,
    );
    if (!ctx.isHosting || ctx.currentState.isWebBroadcast) ctx.webrtc.sendCameraState(camState);
  }

  /// Sends clipboard text over the active `phone2screen-control` channel.
  void sendClipboardText(SessionContext ctx, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!ctx.webrtc.sendClipboard(trimmed)) {
      ctx.currentState = ctx.currentState.copyWith(errorMessage: 'Control channel is not connected yet.');
      return;
    }
    final item = ClipboardItem(text: trimmed, timestamp: DateTime.now(), fromRemote: false);
    ctx.currentState = ctx.currentState.copyWith(clipboardHistory: [item, ...ctx.currentState.clipboardHistory].take(50).toList());
  }

  void _setVideoTracksEnabled(MediaStream? stream, {required bool enabled}) {
    for (final track in stream?.getVideoTracks() ?? const []) {
      track.enabled = enabled;
    }
  }
}
