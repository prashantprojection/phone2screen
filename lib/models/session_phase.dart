/// Lifecycle state of a Phone2Screen streaming or discovery session.
enum SessionPhase {
  idle,
  hosting,
  discovering,
  connecting,
  streaming,
  reconnecting,
  failed;

  bool get isActive => switch (this) {
    .hosting ||
    .discovering ||
    .connecting ||
    .streaming ||
    .reconnecting => true,
    .idle || .failed => false,
  };

  String get label => switch (this) {
    .idle => 'Idle',
    .hosting => 'Hosting',
    .discovering => 'Discovering',
    .connecting => 'Connecting',
    .streaming => 'Streaming',
    .reconnecting => 'Reconnecting',
    .failed => 'Failed',
  };
}
