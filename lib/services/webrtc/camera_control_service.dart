import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/camera_control_state.dart';

/// Safe adapter for hardware camera controls (`zoom`, `exposure`, `focus`) on
/// an active [MediaStreamTrack]. Returns `false` gracefully on unsupported
/// desktop, web, or screen-capture tracks rather than throwing.
class CameraControlService {
  /// Whether the current target exposes native mobile WebRTC camera helpers.
  bool get isCameraControlPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == .android || defaultTargetPlatform == .iOS);

  bool get _isNativeDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == .windows ||
          defaultTargetPlatform == .macOS ||
          defaultTargetPlatform == .linux);

  /// Applies hardware zoom (`1.0..8.0`) via `Helper.setZoom` when supported.
  Future<bool> setZoom(MediaStreamTrack? track, double zoom) async {
    if (track == null || track.kind != 'video' || !isCameraControlPlatform) {
      return false;
    }
    try {
      await Helper.setZoom(track, zoom.clamp(1.0, 8.0).toDouble());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Applies exposure compensation offset (`-2.0..2.0` EV) via
  /// `MediaStreamTrack.applyConstraints` (`flutter_webrtc ^1.2.1` exposes
  /// `Helper.setExposureMode` but no `Helper.setExposureOffset`).
  Future<bool> setExposureOffset(MediaStreamTrack? track, double ev) async {
    if (track == null || track.kind != 'video' || _isNativeDesktop) {
      return false;
    }
    try {
      final clamped = ev.clamp(-2.0, 2.0).toDouble();
      await track.applyConstraints({
        'advanced': [
          {'exposureCompensation': clamped},
        ],
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Locks or unlocks auto-focus via `Helper.setFocusMode` (`locked`/`auto`).
  Future<bool> setFocusLocked(MediaStreamTrack? track, bool locked) async {
    if (track == null || track.kind != 'video' || !isCameraControlPlatform) {
      return false;
    }
    try {
      await Helper.setFocusMode(track, locked ? .locked : .auto);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Executes [cmd] against the active capture stream and returns the resulting
  /// authoritative [RemoteCameraState] (leaving fields unchanged on failure).
  Future<RemoteCameraState> applyCommand(
    RemoteCameraCommand cmd,
    RemoteCameraState current, {
    required MediaStream? stream,
    required Future<bool> Function() switchCamera,
    required Future<bool> Function(bool enabled) toggleTorch,
    required void Function(bool muted) setMicMuted,
  }) async {
    final track = stream?.getVideoTracks().firstOrNull;
    switch (cmd.command) {
      case .flip:
        if (!await switchCamera()) return current;
        return current.copyWith(
          lens: current.lens == .front ? .back : .front,
          torchOn: false,
          zoom: 1.0,
          exposureOffset: 0.0,
          focusLocked: false,
        );
      case .torch:
        final on = cmd.enabled ?? !current.torchOn;
        return await toggleTorch(on) ? current.copyWith(torchOn: on) : current;
      case .micMute:
        final muted = cmd.enabled ?? !current.micMuted;
        setMicMuted(muted);
        return current.copyWith(micMuted: muted);
      case .zoom:
        final z = (cmd.value ?? current.zoom)
            .clamp(current.minZoom, current.maxZoom)
            .toDouble();
        return await setZoom(track, z) ? current.copyWith(zoom: z) : current;
      case .exposure:
        final ev = (cmd.value ?? current.exposureOffset)
            .clamp(-2.0, 2.0)
            .toDouble();
        return await setExposureOffset(track, ev)
            ? current.copyWith(exposureOffset: ev)
            : current;
      case .focusLock:
        final lock = cmd.enabled ?? !current.focusLocked;
        return await setFocusLocked(track, lock)
            ? current.copyWith(focusLocked: lock)
            : current;
      case .voiceMode:
        final clean = cmd.enabled ?? !current.voiceClean;
        final audioTrack = stream?.getAudioTracks().firstOrNull;
        try {
          await audioTrack?.applyConstraints({
            'echoCancellation': clean,
            'noiseSuppression': clean,
            'autoGainControl': clean,
          });
        } catch (_) {
          // Best-effort DSP toggle; unsupported tracks keep desired mode flag.
        }
        return current.copyWith(voiceClean: clean);
    }
  }
}
