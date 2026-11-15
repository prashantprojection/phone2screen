import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/sha256.dart';
import '../../models/obs_sync_state.dart';

/// Native `dart:io` OBS Studio WebSocket v5 (`rpcVersion: 1`) client.
class ObsWebSocketImpl {
  final _stateController = StreamController<ObsSyncState>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  ObsSyncState _state = const ObsSyncState();
  ObsConnectionConfig _config = const ObsConnectionConfig();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Completer<bool>? _identifiedCompleter;
  bool _sawAuthChallenge = false;
  String? _handshakeError;
  int _nextRequestId = 1;
  int _tallyGen = 0;
  int _connEpoch = 0;
  bool _disposed = false;

  Stream<ObsSyncState> get stateStream => _stateController.stream;
  ObsSyncState get currentState => _state;
  bool get isConnected =>
      _state.connected && _socket != null && _socket!.readyState == WebSocket.open;

  Future<bool> connect(ObsConnectionConfig config) async {
    if (_disposed) return false;
    await disconnect();
    if (_disposed) return false;
    final epoch = ++_connEpoch;
    _config = config;
    _sawAuthChallenge = false;
    _handshakeError = null;
    _emit(const ObsSyncState(connecting: true));

    final host = config.host.trim().isEmpty ? '127.0.0.1' : config.host.trim();
    final url = 'ws://$host:${config.port.clamp(1, 65535)}';
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(url, compression: CompressionOptions.compressionOff)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (epoch == _connEpoch) _emit(ObsSyncState(errorMessage: 'Could not reach OBS at $url: $e'));
      return false;
    }
    if (_disposed || epoch != _connEpoch) {
      try { await socket.close(); } catch (_) {}
      return false;
    }

    _socket = socket;
    final identified = Completer<bool>();
    _identifiedCompleter = identified;
    _socketSub = socket.listen(
      (raw) => _onRawFrame(socket, raw),
      onError: (Object err) => _onSocketClosed(socket, error: '$err'),
      onDone: () => _onSocketClosed(socket),
      cancelOnError: true,
    );
    var ok = false;
    try { ok = await identified.future.timeout(const Duration(seconds: 5)); } on TimeoutException {
      _handshakeError = 'Timed out waiting for OBS WebSocket handshake.';
    }
    if (_identifiedCompleter == identified) _identifiedCompleter = null;
    if (!ok || _disposed || _socket != socket) {
      final err = _handshakeError ?? 'OBS WebSocket authentication failed. Check password.';
      await _dropSocket(socket);
      if (!_disposed && epoch == _connEpoch) _emit(ObsSyncState(errorMessage: err));
      return false;
    }
    _emit(_state.copyWith(connected: true, connecting: false, clearError: true));
    await _refreshInitialState();
    return isConnected;
  }

  Future<void> disconnect() async {
    _connEpoch++;
    _tallyGen++;
    final pendingId = _identifiedCompleter;
    _identifiedCompleter = null;
    if (pendingId != null && !pendingId.isCompleted) pendingId.complete(false);
    await _dropSocket(_socket);
    if (!_disposed) _emit(const ObsSyncState());
  }

  Future<bool> setVirtualCamActive(bool active) async {
    if (await _request(active ? 'StartVirtualCam' : 'StopVirtualCam') == null) return false;
    _emit(_state.copyWith(virtualCamActive: active, clearError: true));
    return true;
  }

  Future<bool> toggleVirtualCam() async {
    final resp = await _request('ToggleVirtualCam');
    if (resp == null) return false;
    final next = resp['outputActive'] is bool ? resp['outputActive'] as bool : !_state.virtualCamActive;
    _emit(_state.copyWith(virtualCamActive: next, clearError: true));
    return true;
  }

  Future<bool> ensureBrowserSource({
    required String cleanFeedUrl, String inputName = 'Phone2Screen Clean Feed',
    int width = 1920, int height = 1080, int audioDelayMs = 0,
  }) async {
    if (!isConnected) return false;
    final listResp = await _request('GetInputList');
    if (listResp == null) return false;
    final inputs = listResp['inputs'];
    final exists = inputs is List && inputs.any((e) => e is Map && e['inputName'] == inputName);
    final settings = {'url': cleanFeedUrl, 'width': width, 'height': height, 'reroute_audio': true};
    if (exists) {
      if (await _request('SetInputSettings', {'inputName': inputName, 'inputSettings': settings}) == null) {
        return false;
      }
    } else {
      final scene = _state.programScene?.isNotEmpty == true
          ? _state.programScene
          : (await _request('GetSceneList'))?['currentProgramSceneName'] as String?;
      if (scene == null || scene.isEmpty) return false;
      final created = await _request('CreateInput', {
        'sceneName': scene, 'inputName': inputName, 'inputKind': 'browser_source',
        'inputSettings': settings, 'sceneItemEnabled': true,
      });
      if (created == null) return false;
    }
    await setAudioSyncOffset(inputName: inputName, delayMs: audioDelayMs);
    await _recomputeTally();
    return true;
  }

  Future<bool> setAudioSyncOffset({String inputName = 'Phone2Screen Clean Feed', required int delayMs}) async {
    // OBS WebSocket v5 expects audio sync offset in nanoseconds.
    final resp = await _request('SetInputAudioSyncOffset', {
      'inputName': inputName, 'inputAudioSyncOffset': delayMs.clamp(0, 500) * 1000000,
    });
    return resp != null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _stateController.close();
  }

  void _onRawFrame(WebSocket socket, Object? raw) {
    if (_disposed || _socket != socket || raw is! String) return;
    final Object? decoded;
    try { decoded = jsonDecode(raw); } catch (_) { return; }
    if (decoded is! Map) return;
    final d = decoded['d'] is Map ? Map<String, dynamic>.from(decoded['d'] as Map) : const <String, dynamic>{};
    switch (decoded['op']) {
      case 0: _handleHello(socket, d);
      case 2:
        final completer = _identifiedCompleter;
        if (completer != null && !completer.isCompleted) completer.complete(true);
      case 5: _handleEvent(d);
      case 7:
        final reqId = d['requestId'];
        if (reqId is String) _pendingRequests.remove(reqId)?.complete(d);
    }
  }

  void _handleHello(WebSocket socket, Map<String, dynamic> d) {
    String? auth;
    final rawAuth = d['authentication'];
    if (rawAuth is Map && rawAuth['challenge'] is String && rawAuth['salt'] is String) {
      final challenge = rawAuth['challenge'] as String;
      if (challenge.isNotEmpty) {
        _sawAuthChallenge = true;
        auth = computeObsWebSocketAuth(password: _config.password, salt: rawAuth['salt'] as String, challenge: challenge);
      }
    }
    try {
      socket.add(jsonEncode({'op': 1, 'd': {'rpcVersion': 1, 'authentication': ?auth, 'eventSubscriptions': 1023}}));
    } catch (_) {}
  }

  void _handleEvent(Map<String, dynamic> d) {
    final data = d['eventData'] is Map ? Map<String, dynamic>.from(d['eventData'] as Map) : const <String, dynamic>{};
    switch (d['eventType']) {
      case 'CurrentProgramSceneChanged':
        final name = data['sceneName'] as String?;
        _emit(_state.copyWith(programScene: name, clearProgram: name == null));
        unawaited(_recomputeTally());
      case 'CurrentPreviewSceneChanged':
        final name = data['sceneName'] as String?;
        _emit(_state.copyWith(previewScene: name, clearPreview: name == null));
        unawaited(_recomputeTally());
      case 'StudioModeStateChanged':
        final enabled = data['studioModeEnabled'] == true;
        _emit(_state.copyWith(studioModeEnabled: enabled, clearPreview: !enabled));
        unawaited(_recomputeTally());
      case 'VirtualcamStateChanged':
        _emit(_state.copyWith(virtualCamActive: data['outputActive'] == true));
      case 'SceneItemEnableStateChanged':
      case 'SceneItemCreated':
      case 'SceneItemRemoved':
        unawaited(_recomputeTally());
    }
  }

  Future<void> _refreshInitialState() async {
    final r = await Future.wait([
      _request('GetVersion'), _request('GetVirtualCamStatus'),
      _request('GetStudioModeEnabled'), _request('GetSceneList'),
    ]);
    if (_disposed || !isConnected) return;
    final program = r[3]?['currentProgramSceneName'] as String?;
    final preview = r[3]?['currentPreviewSceneName'] as String?;
    _emit(_state.copyWith(
      obsVersion: r[0]?['obsVersion'] as String? ?? _state.obsVersion,
      virtualCamActive: r[1]?['outputActive'] as bool? ?? _state.virtualCamActive,
      studioModeEnabled: r[2]?['studioModeEnabled'] as bool? ?? _state.studioModeEnabled,
      programScene: program, previewScene: preview,
      clearProgram: program == null, clearPreview: preview == null,
    ));
    await _recomputeTally();
  }

  Future<void> _recomputeTally() async {
    if (!isConnected) return;
    final gen = ++_tallyGen;
    final filter = _config.sourceFilter.trim().toLowerCase();
    final program = _state.programScene;
    final preview = _state.previewScene;
    if (await _hasActiveSource(program, filter)) {
      if (gen == _tallyGen && isConnected) _emit(_state.copyWith(tallyState: .program));
      return;
    }
    if (gen != _tallyGen || !isConnected) return;
    if (preview != program && await _hasActiveSource(preview, filter)) {
      if (gen == _tallyGen && isConnected) _emit(_state.copyWith(tallyState: .preview));
      return;
    }
    if (gen == _tallyGen && isConnected) _emit(_state.copyWith(tallyState: .standby));
  }

  Future<bool> _hasActiveSource(String? scene, String lowerFilter) async {
    if (scene == null || scene.isEmpty) return false;
    if (lowerFilter.isEmpty) return true;
    final items = (await _request('GetSceneItemList', {'sceneName': scene}))?['sceneItems'];
    if (items is! List) return false;
    for (final raw in items) {
      if (raw is! Map || raw['sceneItemEnabled'] != true) continue;
      final name = raw['sourceName'];
      if (name is! String) continue;
      final lower = name.toLowerCase();
      if (lower.contains(lowerFilter) || lower.contains('phone2screen') || lower.contains('/obs')) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> _request(String type, [Map<String, dynamic>? data]) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open || !_state.connected) return null;
    final id = 'p2s_${_nextRequestId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;
    try {
      socket.add(jsonEncode({'op': 6, 'd': {'requestType': type, 'requestId': id, 'requestData': ?data}}));
      final resp = await completer.future.timeout(const Duration(seconds: 5));
      final status = resp['requestStatus'];
      if (status is! Map || status['result'] != true) return null;
      final body = resp['responseData'];
      return body is Map ? Map<String, dynamic>.from(body) : const {};
    } catch (_) { return null; } finally { _pendingRequests.remove(id); }
  }

  void _onSocketClosed(WebSocket socket, {String? error}) {
    if (_socket != socket) return;
    final closeCode = socket.closeCode;
    final closeReason = socket.closeReason ?? '';
    _socket = null;
    _socketSub = null;
    _failPendingRequests();
    final pendingId = _identifiedCompleter;
    if (pendingId != null && !pendingId.isCompleted) {
      final authFailed = closeCode == 4009 || closeReason.toLowerCase().contains('auth') ||
          (_sawAuthChallenge && _config.password.isEmpty);
      _handshakeError = authFailed
          ? 'OBS WebSocket authentication failed. Check password.'
          : (error != null ? 'OBS WebSocket error: $error' : 'OBS closed connection before handshake completed.');
      pendingId.complete(false);
      return;
    }
    if (!_disposed && _state.connected) {
      _emit(ObsSyncState(errorMessage: error ?? (closeReason.isNotEmpty ? closeReason : 'Disconnected from OBS WebSocket.')));
    }
  }

  Future<void> _dropSocket(WebSocket? socket) async {
    _failPendingRequests();
    if (socket == null) return;
    if (_socket == socket) _socket = null;
    final sub = _socketSub;
    _socketSub = null;
    await sub?.cancel();
    try { await socket.close(WebSocketStatus.normalClosure, 'Closed'); } catch (_) {}
  }

  void _failPendingRequests() {
    if (_pendingRequests.isEmpty) return;
    final entries = List.of(_pendingRequests.values);
    _pendingRequests.clear();
    for (final c in entries) {
      if (!c.isCompleted) c.complete(const {'requestStatus': {'result': false}});
    }
  }

  void _emit(ObsSyncState next) {
    if (_disposed) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
