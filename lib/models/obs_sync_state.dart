/// Broadcast tally status indicating whether the phone feed is live in OBS.
enum TallyState {
  off,
  standby,
  preview,
  program;

  /// Short uppercase badge text displayed on Sender and Receiver tally indicators.
  String get badgeLabel => switch (this) {
    .program => 'ON AIR',
    .preview => 'PREVIEW',
    .standby => 'STANDBY',
    .off => 'OFF',
  };
}

/// Live OBS tally message forwarded from Receiver to Sender over DataChannel.
class const LiveTallyMessage({
  required final TallyState state,
  final String? sceneName,
}) {
  /// Encodes this tally update as a `tally` DataChannel JSON payload.
  Map<String, dynamic> toJson() => {
    'kind': 'tally',
    'state': state.name,
    if (sceneName != null && sceneName!.isNotEmpty) 'scene': sceneName,
  };

  /// Parses a `tally` JSON payload, returning `null` if malformed or unknown.
  static LiveTallyMessage? tryFromJson(Map<String, dynamic> map) {
    if (map['kind'] != 'tally') return null;
    final parsed = map['state'] is String
        ? TallyState.values.where((s) => s.name == map['state']).firstOrNull
        : null;
    if (parsed == null) return null;
    final rawScene = map['scene'];
    final scene = rawScene is String && rawScene.isNotEmpty ? rawScene : null;
    return LiveTallyMessage(state: parsed, sceneName: scene);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTallyMessage &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          sceneName == other.sceneName;

  @override
  int get hashCode => Object.hash(state, sceneName);
}

/// Persisted connection settings for OBS Studio WebSocket v5 (`rpcVersion: 1`).
class const ObsConnectionConfig({
  final String host = '127.0.0.1',
  final int port = 4455,
  final String password = '',
  final bool autoConnect = false,
  final String sourceFilter = 'Phone2Screen',
}) {
  ObsConnectionConfig copyWith({
    String? host,
    int? port,
    String? password,
    bool? autoConnect,
    String? sourceFilter,
  }) => ObsConnectionConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    password: password ?? this.password,
    autoConnect: autoConnect ?? this.autoConnect,
    sourceFilter: sourceFilter ?? this.sourceFilter,
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'password': password,
    'autoConnect': autoConnect,
    'sourceFilter': sourceFilter,
  };

  /// Decodes [ObsConnectionConfig] from [json], clamping port to `1..65535`.
  factory ObsConnectionConfig.fromJson(Map<String, dynamic> json) {
    final rawHost = json['host'];
    final rawPort = json['port'];
    final parsedPort = switch (rawPort) {
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
    return ObsConnectionConfig(
      host: rawHost is String && rawHost.trim().isNotEmpty
          ? rawHost.trim()
          : '127.0.0.1',
      port: (parsedPort ?? 4455).clamp(1, 65535),
      password: json['password'] is String ? json['password'] as String : '',
      autoConnect: json['autoConnect'] is bool && (json['autoConnect'] as bool),
      sourceFilter: json['sourceFilter'] is String
          ? json['sourceFilter'] as String
          : 'Phone2Screen',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObsConnectionConfig &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          password == other.password &&
          autoConnect == other.autoConnect &&
          sourceFilter == other.sourceFilter;

  @override
  int get hashCode =>
      Object.hash(host, port, password, autoConnect, sourceFilter);
}

/// Live connection, virtual camera, scene, and tally status from OBS Studio.
class const ObsSyncState({
  final bool connected = false,
  final bool connecting = false,
  final bool virtualCamActive = false,
  final bool studioModeEnabled = false,
  final String? programScene,
  final String? previewScene,
  final TallyState tallyState = .off,
  final String? errorMessage,
  final String? obsVersion,
}) {
  ObsSyncState copyWith({
    bool? connected,
    bool? connecting,
    bool? virtualCamActive,
    bool? studioModeEnabled,
    String? programScene,
    String? previewScene,
    TallyState? tallyState,
    String? errorMessage,
    String? obsVersion,
    bool clearError = false,
    bool clearPreview = false,
    bool clearProgram = false,
  }) => ObsSyncState(
    connected: connected ?? this.connected,
    connecting: connecting ?? this.connecting,
    virtualCamActive: virtualCamActive ?? this.virtualCamActive,
    studioModeEnabled: studioModeEnabled ?? this.studioModeEnabled,
    programScene: clearProgram ? null : (programScene ?? this.programScene),
    previewScene: clearPreview ? null : (previewScene ?? this.previewScene),
    tallyState: tallyState ?? this.tallyState,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    obsVersion: obsVersion ?? this.obsVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObsSyncState &&
          runtimeType == other.runtimeType &&
          connected == other.connected &&
          connecting == other.connecting &&
          virtualCamActive == other.virtualCamActive &&
          studioModeEnabled == other.studioModeEnabled &&
          programScene == other.programScene &&
          previewScene == other.previewScene &&
          tallyState == other.tallyState &&
          errorMessage == other.errorMessage &&
          obsVersion == other.obsVersion;

  @override
  int get hashCode => Object.hash(
    connected, connecting, virtualCamActive, studioModeEnabled,
    programScene, previewScene, tallyState, errorMessage, obsVersion,
  );
}
