import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/camera_control_state.dart';
import '../../models/stream_config.dart';
import 'camera_control_service.dart';

/// Selectable desktop screen or window capture target with optional preview.
class const DesktopSourceItem({
  required final String id,
  required final String name,
  final Uint8List? thumbnail,
  required final bool isWindow,
});

/// Manages local camera and screen-capture streams across mobile, desktop, web.
class MediaCaptureService {
  static const MethodChannel _projectionChannel = MethodChannel(
    'phone2screen/projection_service',
  );

  final CameraControlService _cameraControl = CameraControlService();

  MediaStream? _activeStream;
  bool _projectionServiceStarted = false;

  /// Currently captured local [MediaStream], or null when idle.
  MediaStream? get activeStream => _activeStream;

  /// True on mobile targets that expose native camera zoom/focus helpers.
  bool get isCameraControlPlatform => _cameraControl.isCameraControlPlatform;

  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == .android || defaultTargetPlatform == .iOS);

  bool get _isNativeDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == .windows ||
          defaultTargetPlatform == .macOS ||
          defaultTargetPlatform == .linux);

  /// Enumerates screens and windows available for desktop screen sharing.
  Future<List<DesktopSourceItem>> getDesktopSources() async {
    if (!_isNativeDesktop) return const [];
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Screen, SourceType.Window],
    );
    return sources
        .map(
          (source) => DesktopSourceItem(
            id: source.id,
            name: source.name,
            thumbnail: source.thumbnail,
            isWindow: source.type == SourceType.Window,
          ),
        )
        .toList(growable: false);
  }

  /// Requests permissions if needed and begins camera or screen capture.
  Future<MediaStream> startCapture(StreamConfig config) async {
    await stopCapture();

    var captureAudio = config.enableAudio;
    if (_isNativeMobile) {
      captureAudio = await _ensureMobilePermissions(
        requireCamera: config.sourceType == .camera,
        requestAudio: config.enableAudio,
      );
    }

    final stream = config.sourceType == .screen
        ? await _startScreenCapture(config, captureAudio: captureAudio)
        : await _startCameraCapture(config, captureAudio: captureAudio);

    _activeStream = stream;
    return stream;
  }

  Future<bool> _ensureMobilePermissions({
    required bool requireCamera,
    required bool requestAudio,
  }) async {
    if (requireCamera) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        throw StateError('Camera permission denied. Enable camera access.');
      }
    }
    if (!requestAudio) return false;
    return (await Permission.microphone.request()).isGranted;
  }

  Future<MediaStream> _startScreenCapture(
    StreamConfig config, {
    required bool captureAudio,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == .android) {
      // Android 14+ (API 34+) throws SecurityException if a mediaProjection
      // foreground service starts BEFORE MediaProjection consent is granted.
      // Always prompt Helper.requestCapturePermission() first, then start FGS.
      final granted = await Helper.requestCapturePermission();
      if (!granted) {
        throw StateError('Screen capture permission was denied.');
      }
      _projectionServiceStarted = await _invokeProjection('startService');
    }

    var effectiveSourceId = config.desktopSourceId;
    if (_isNativeDesktop && effectiveSourceId == null) {
      final screens = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      effectiveSourceId = screens.firstOrNull?.id;
    }

    final videoConstraints = effectiveSourceId != null
        ? <String, dynamic>{
            'deviceId': {'exact': effectiveSourceId},
          }
        : <String, dynamic>{
            'width': {'ideal': config.width},
            'height': {'ideal': config.height},
            'frameRate': {'ideal': config.frameRate},
          };

    try {
      try {
        return await navigator.mediaDevices.getDisplayMedia({
          'video': videoConstraints,
          'audio': captureAudio,
        });
      } catch (_) {
        if (!captureAudio) rethrow;
        // Retry without audio when platform display capture rejects audio.
        return await navigator.mediaDevices.getDisplayMedia({
          'video': videoConstraints,
          'audio': false,
        });
      }
    } catch (_) {
      await _stopProjectionService();
      rethrow;
    }
  }

  Future<MediaStream> _startCameraCapture(
    StreamConfig config, {
    required bool captureAudio,
  }) async {
    final facingMode = config.cameraLens == .front ? 'user' : 'environment';
    final videoConstraints = <String, dynamic>{
      if (!_isNativeDesktop) 'facingMode': {'ideal': facingMode},
      'width': {'ideal': config.width},
      'height': {'ideal': config.height},
      'frameRate': {'ideal': config.frameRate},
    };
    final dynamic audioConstraints = captureAudio
        ? <String, dynamic>{
            'echoCancellation': config.voiceCleanAudio,
            'noiseSuppression': config.voiceCleanAudio,
            'autoGainControl': config.voiceCleanAudio,
          }
        : false;
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': videoConstraints,
      });
    } catch (_) {
      if (captureAudio) {
        try {
          // Retry video-only when no microphone is attached or mic init fails.
          return await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': videoConstraints,
          });
        } catch (_) {}
      }
      try {
        // Retry with minimal constraints for webcams that reject ideal sizing.
        return await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': true,
        });
      } catch (_) {
        throw StateError(
          'Unable to access camera. Check camera permissions or switch Broadcast Source to Screen.',
        );
      }
    }
  }

  /// Toggles between front and back cameras on active camera streams.
  Future<bool> switchCamera() async {
    final tracks = _activeStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return false;
    try {
      return await Helper.switchCamera(tracks.first);
    } catch (_) {
      return false;
    }
  }

  /// Enables or mutes all local audio tracks without renegotiating SDP.
  void setMicMuted(bool muted) {
    final tracks = _activeStream?.getAudioTracks();
    if (tracks == null) return;
    for (final track in tracks) {
      track.enabled = !muted;
    }
  }

  /// Toggles camera flash torch when supported by the active video track.
  Future<bool> toggleTorch(bool enabled) async {
    final tracks = _activeStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return false;
    try {
      await tracks.first.setTorch(enabled);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Adjusts hardware zoom (`1.0..8.0`) on the active video track if supported.
  Future<bool> setZoom(double zoom) =>
      _cameraControl.setZoom(_activeStream?.getVideoTracks().firstOrNull, zoom);

  /// Adjusts exposure compensation (`-2.0..2.0` EV) on the active video track.
  Future<bool> setExposureOffset(double ev) => _cameraControl.setExposureOffset(
    _activeStream?.getVideoTracks().firstOrNull,
    ev,
  );

  /// Locks or unlocks auto-focus on the active camera track when supported.
  Future<bool> setFocusLocked(bool locked) => _cameraControl.setFocusLocked(
    _activeStream?.getVideoTracks().firstOrNull,
    locked,
  );

  /// Applies a remote [RemoteCameraCommand] and returns the resulting state.
  Future<RemoteCameraState> applyCameraCommand(
    RemoteCameraCommand cmd,
    RemoteCameraState current,
  ) => _cameraControl.applyCommand(
    cmd,
    current,
    stream: _activeStream,
    switchCamera: switchCamera,
    toggleTorch: toggleTorch,
    setMicMuted: setMicMuted,
  );

  /// Stops active media tracks, disposes stream, and halts Android FGS.
  Future<void> stopCapture() async {
    final stream = _activeStream;
    _activeStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    await _stopProjectionService();
  }

  Future<void> _stopProjectionService() async {
    if (!_projectionServiceStarted) return;
    _projectionServiceStarted = false;
    await _invokeProjection('stopService');
  }

  Future<bool> _invokeProjection(String method) async {
    try {
      await _projectionChannel.invokeMethod<void>(method);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
