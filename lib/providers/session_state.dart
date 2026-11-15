import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/clipboard_item.dart';
import '../models/session_phase.dart';
import '../models/signaling_data.dart';
import '../models/stream_telemetry.dart';
import '../services/webrtc/media_capture_service.dart';
import '../services/webrtc/webrtc_session_service.dart';

/// Unified runtime session state shared by Receiver and Sender workflows.
class const SessionState({
  final SessionPhase phase = .idle,
  final SignalingData? activeEndpoint,
  final String? connectedPeerName,
  final bool isWebBroadcast = false,
  final MediaStream? localStream,
  final MediaStream? remoteStream,
  final StreamTelemetry telemetry = const StreamTelemetry(),
  final bool isMicMuted = false,
  final bool isTorchOn = false,
  final List<ClipboardItem> clipboardHistory = const [],
  final String? errorMessage,
}) {
  /// Builds a clean reset state preserving clipboard history.
  SessionState reset({
    SessionPhase phase = .idle,
    SignalingData? activeEndpoint,
    String? connectedPeerName,
    bool isWebBroadcast = false,
    String? errorMessage,
  }) {
    return SessionState(
      phase: phase,
      activeEndpoint: activeEndpoint,
      connectedPeerName: connectedPeerName,
      isWebBroadcast: isWebBroadcast,
      clipboardHistory: clipboardHistory,
      errorMessage: errorMessage,
    );
  }

  /// Returns an updated [SessionState] with optional explicit null resets.
  SessionState copyWith({
    SessionPhase? phase,
    SignalingData? activeEndpoint,
    String? connectedPeerName,
    bool? isWebBroadcast,
    MediaStream? localStream,
    MediaStream? remoteStream,
    StreamTelemetry? telemetry,
    bool? isMicMuted,
    bool? isTorchOn,
    List<ClipboardItem>? clipboardHistory,
    String? errorMessage,
    bool clearEndpoint = false,
    bool clearPeerName = false,
    bool clearLocalStream = false,
    bool clearRemoteStream = false,
    bool clearError = false,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      activeEndpoint: clearEndpoint
          ? null
          : (activeEndpoint ?? this.activeEndpoint),
      connectedPeerName: clearPeerName
          ? null
          : (connectedPeerName ?? this.connectedPeerName),
      isWebBroadcast: isWebBroadcast ?? this.isWebBroadcast,
      localStream: clearLocalStream ? null : (localStream ?? this.localStream),
      remoteStream: clearRemoteStream
          ? null
          : (remoteStream ?? this.remoteStream),
      telemetry: telemetry ?? this.telemetry,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      clipboardHistory: clipboardHistory ?? this.clipboardHistory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Internal bridge exposing [SessionNotifier] state and lifecycle to flows.
abstract interface class SessionContext {
  Ref get sessionRef;
  SessionState get currentState;
  set currentState(SessionState value);
  bool get isNotifierMounted;
  bool get isHosting;
  set isHosting(bool value);
  String? get activeSessionId;
  set activeSessionId(String? value);
  int get epoch;
  int bumpEpoch();
  MediaCaptureService get mediaCapture;
  WebRtcSessionService get webrtc;
}

/// Formats thrown errors concisely for UI error banners.
String friendlySessionError(Object error) {
  final raw = error is StateError ? error.message : error.toString();
  return raw.replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), '');
}
