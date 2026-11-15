/// Video capture source selected on a sender device.
enum MediaSourceType {
  camera,
  screen;

  String get label => switch (this) {
    .camera => 'Camera',
    .screen => 'Screen',
  };
}

/// Camera facing lens when [MediaSourceType.camera] is active.
enum CameraLens {
  front,
  back;

  String get label => switch (this) {
    .front => 'Front',
    .back => 'Back',
  };
}
