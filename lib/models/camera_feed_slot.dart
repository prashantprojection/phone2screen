import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'camera_control_state.dart';
import 'stream_telemetry.dart';
import 'viewer_display_config.dart';

/// Multi-camera layout presets rendered on the Receiver studio stage.
enum MultiCamLayout {
  solo,
  split2,
  grid4;

  /// Short label displayed in the studio layout selector.
  String get label => switch (this) {
    .solo => 'Solo',
    .split2 => '2-Up',
    .grid4 => '4-Up',
  };
}

/// Runtime state and per-camera framing/color settings for a connected feed.
class const CameraFeedSlot({
  required final String peerId,
  required final String deviceName,
  final MediaStream? stream,
  final StreamTelemetry telemetry = const StreamTelemetry(),
  final RemoteCameraState cameraState = const RemoteCameraState(),
  final ViewerDisplayConfig displayConfig = const ViewerDisplayConfig(),
}) {
  /// Returns an updated copy of [CameraFeedSlot].
  CameraFeedSlot copyWith({
    String? deviceName,
    MediaStream? stream,
    bool clearStream = false,
    StreamTelemetry? telemetry,
    RemoteCameraState? cameraState,
    ViewerDisplayConfig? displayConfig,
  }) {
    return CameraFeedSlot(
      peerId: peerId,
      deviceName: deviceName ?? this.deviceName,
      stream: clearStream ? null : (stream ?? this.stream),
      telemetry: telemetry ?? this.telemetry,
      cameraState: cameraState ?? this.cameraState,
      displayConfig: displayConfig ?? this.displayConfig,
    );
  }
}
