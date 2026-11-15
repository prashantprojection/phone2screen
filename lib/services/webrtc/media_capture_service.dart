import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/stream_config.dart';

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

  MediaStream? _activeStream;
  bool _projectionServiceStarted = false;

  /// Currently captured local [MediaStream], or null when idle.
  MediaStream? get activeStream => _activeStream;

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

    final videoConstraints = config.desktopSourceId != null
        ? <String, dynamic>{
            'deviceId': {'exact': config.desktopSourceId},
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
  }) {
    final facingMode = config.cameraLens == .front ? 'user' : 'environment';
    return navigator.mediaDevices.getUserMedia({
      'audio': captureAudio,
      'video': {
        'facingMode': facingMode,
        'width': {'ideal': config.width},
        'height': {'ideal': config.height},
        'frameRate': {'ideal': config.frameRate},
      },
    });
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
