import '../../models/obs_sync_state.dart';
import 'obs_websocket_stub.dart'
    if (dart.library.io) 'obs_websocket_io.dart'
    as impl;

/// Controls OBS Studio via OBS WebSocket v5 (`rpcVersion: 1`) for virtual cam,
/// browser source provisioning, live tally tracking, and audio sync offset.
class ObsWebSocketService {
  ObsWebSocketService() : _impl = impl.ObsWebSocketImpl();

  final impl.ObsWebSocketImpl _impl;

  /// Broadcast stream emitting OBS connection, virtual cam, and tally updates.
  Stream<ObsSyncState> get stateStream => _impl.stateStream;

  /// Latest [ObsSyncState] snapshot.
  ObsSyncState get currentState => _impl.currentState;

  /// Whether the WebSocket is open and the `Hello -> Identify -> Identified`
  /// handshake succeeded.
  bool get isConnected => _impl.isConnected;

  /// Connects and authenticates with OBS WebSocket v5 using [config].
  Future<bool> connect(ObsConnectionConfig config) => _impl.connect(config);

  /// Disconnects the active OBS WebSocket session and resets state to off.
  Future<void> disconnect() => _impl.disconnect();

  /// Starts or stops the OBS Virtual Camera (`StartVirtualCam` / `StopVirtualCam`).
  Future<bool> setVirtualCamActive(bool active) =>
      _impl.setVirtualCamActive(active);

  /// Toggles the OBS Virtual Camera (`ToggleVirtualCam`).
  Future<bool> toggleVirtualCam() => _impl.toggleVirtualCam();

  /// Creates or updates an OBS Browser Source pointing at [cleanFeedUrl] and
  /// applies [audioDelayMs] audio sync offset.
  Future<bool> ensureBrowserSource({
    required String cleanFeedUrl,
    String inputName = 'Phone2Screen Clean Feed',
    int width = 1920,
    int height = 1080,
    int audioDelayMs = 0,
  }) => _impl.ensureBrowserSource(
    cleanFeedUrl: cleanFeedUrl,
    inputName: inputName,
    width: width,
    height: height,
    audioDelayMs: audioDelayMs,
  );

  /// Sets the OBS audio sync offset for [inputName] in milliseconds (`0..500`).
  Future<bool> setAudioSyncOffset({
    String inputName = 'Phone2Screen Clean Feed',
    required int delayMs,
  }) => _impl.setAudioSyncOffset(inputName: inputName, delayMs: delayMs);

  /// Releases socket and stream resources permanently.
  Future<void> dispose() => _impl.dispose();
}
