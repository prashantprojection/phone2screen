import 'dart:async';

import '../../models/obs_sync_state.dart';

/// Web stub: desktop OBS WebSocket v5 control uses `dart:io` on native targets.
class ObsWebSocketImpl {
  final _stateController = StreamController<ObsSyncState>.broadcast();
  ObsSyncState _state = const ObsSyncState();

  Stream<ObsSyncState> get stateStream => _stateController.stream;

  ObsSyncState get currentState => _state;

  bool get isConnected => false;

  Future<bool> connect(ObsConnectionConfig config) async {
    _state = const ObsSyncState(
      errorMessage: 'OBS WebSocket control is only supported on desktop/mobile.',
    );
    if (!_stateController.isClosed) _stateController.add(_state);
    return false;
  }

  Future<void> disconnect() async {
    _state = const ObsSyncState();
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  Future<bool> setVirtualCamActive(bool active) async => false;

  Future<bool> toggleVirtualCam() async => false;

  Future<bool> ensureBrowserSource({
    required String cleanFeedUrl,
    String inputName = 'Phone2Screen Clean Feed',
    int width = 1920,
    int height = 1080,
    int audioDelayMs = 0,
  }) async => false;

  Future<bool> setAudioSyncOffset({
    String inputName = 'Phone2Screen Clean Feed',
    required int delayMs,
  }) async => false;

  Future<void> dispose() async {
    await _stateController.close();
  }
}
