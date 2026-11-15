import 'dart:async';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import '../../models/signaling_message.dart';
import 'signaling_peer_slot.dart';
import 'signaling_port_binder.dart';
import 'web_companion_mode.dart';

class _PeerSlot {
  _PeerSlot({required this.peerId, required this.isPrimary, required this.socket});

  final String peerId;
  final bool isPrimary;
  final WebSocket socket;
  StreamSubscription<dynamic>? sub;
  bool authenticated = false;
  String? deviceName;
}

/// Native `dart:io` HTTP/HTTPS + WebSocket signaling server supporting single-peer
/// (`maxPeers = 1`) or multi-peer (`maxPeers > 1`) slot tracking.
class SignalingServerImpl {
  final _hub = SignalingEventHub();
  final Map<String, _PeerSlot> _slots = {};

  HttpServer? _server;
  HttpServer? _httpsServer;
  StreamSubscription<HttpRequest>? _serverSub;
  StreamSubscription<HttpRequest>? _httpsServerSub;
  int? _boundPort;
  int? _boundHttpsPort;
  WebCompanionMode _companionMode = .sendToReceiver;
  String _sessionId = '';
  String _deviceName = 'Phone2Screen';
  String _pin = '';
  int _maxPeers = StreamConstants.maxActivePeers;
  int _nextPeerSeq = 1;
  bool _disposed = false;

  Stream<SignalingMessage> get messages => _hub.messages;
  Stream<bool> get clientConnectionEvents => _hub.clientConnectionEvents;
  Stream<PeerSignalingEvent> get peerMessages => _hub.peerMessages;
  Stream<PeerConnectionEvent> get peerConnectionEvents => _hub.peerConnectionEvents;
  int? get boundPort => _boundPort;
  int? get boundHttpsPort => _boundHttpsPort;
  WebCompanionMode get companionMode => _companionMode;
  bool get isRunning => _server != null;

  Future<int> start({
    int preferredPort = 8080,
    int? preferredHttpsPort = StreamConstants.defaultHttpsPort,
    WebCompanionMode companionMode = .sendToReceiver,
    required String sessionId,
    required String deviceName,
    String? pin,
    int maxPeers = StreamConstants.maxActivePeers,
  }) async {
    if (_disposed) throw StateError('SignalingServerService has been disposed.');
    if (isRunning) await stop();

    final server = await bindHttpPortRange(preferredPort);
    final effectiveHttpsPort =
        preferredPort == 0 && preferredHttpsPort == StreamConstants.defaultHttpsPort
        ? 0
        : preferredHttpsPort;
    final httpsServer = await tryBindHttpsPortRange(effectiveHttpsPort);

    if (_disposed) {
      await server.close(force: true);
      await httpsServer?.close(force: true);
      throw StateError('SignalingServerService was disposed while starting.');
    }

    _server = server;
    _httpsServer = httpsServer;
    _boundPort = server.port;
    _boundHttpsPort = httpsServer?.port;
    _companionMode = companionMode;
    _sessionId = sessionId;
    _deviceName = deviceName;
    _pin = pin?.trim() ?? '';
    _maxPeers = maxPeers < 1 ? 1 : maxPeers;

    _serverSub = server.listen((r) => unawaited(_handleRequest(r)), onError: (_) {});
    _httpsServerSub = httpsServer?.listen(
      (r) => unawaited(_handleRequest(r)),
      onError: (_) {},
    );
    return server.port;
  }

  void send(SignalingMessage message, {String? peerId}) {
    if (_disposed) return;
    final slot = peerId != null
        ? _slots[peerId]
        : _slots.values.where((s) => s.isPrimary).firstOrNull;
    _sendToSlot(slot, message);
  }

  Future<void> disconnectClient([String reason = 'Host ended session', String? peerId]) async {
    if (peerId != null) {
      final slot = _slots[peerId];
      if (slot != null) await _closeSlot(slot, byeReason: reason);
      return;
    }
    for (final slot in _slots.values.toList()) {
      await _closeSlot(slot, byeReason: reason);
    }
  }

  Future<void> stop() async {
    await disconnectClient('Host stopped session');
    await _serverSub?.cancel();
    await _httpsServerSub?.cancel();
    _serverSub = null;
    _httpsServerSub = null;
    final server = _server;
    final httpsServer = _httpsServer;
    _server = null;
    _httpsServer = null;
    _boundPort = null;
    _boundHttpsPort = null;
    if (server != null) await server.close(force: true);
    if (httpsServer != null) await httpsServer.close(force: true);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _hub.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/ws') {
        await _handleWebSocketUpgrade(request);
        return;
      }
      await serveSignalingHttpRequest(
        request,
        sessionId: _sessionId,
        deviceName: _deviceName,
        requiresPin: _pin.isNotEmpty,
        mode: _companionMode,
        httpPort: _boundPort ?? StreamConstants.defaultSignalingPort,
        httpsPort: _boundHttpsPort,
      );
    } catch (_) {
      try { await request.response.close(); } catch (_) {}
    }
  }

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response..statusCode = HttpStatus.badRequest..write('Expected WebSocket upgrade');
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    if (_disposed) {
      await socket.close(WebSocketStatus.goingAway, 'Server disposed');
      return;
    }
    socket.pingInterval = const Duration(seconds: 10);

    // Enforce maxPeers (`1` for mobile/receiver safety, up to `maxDesktopReceiverPeers`).
    if (_slots.length >= _maxPeers) {
      final msg = _maxPeers == 1 ? 'Host is already in an active session' : 'Host reached maximum active peers';
      await _rejectSocket(socket, message: msg);
      return;
    }

    final peerId = 'peer-${_nextPeerSeq++}';
    final isPrimary = !_slots.values.any((s) => s.isPrimary);
    final slot = _PeerSlot(peerId: peerId, isPrimary: isPrimary, socket: socket);
    _slots[peerId] = slot;
    slot.sub = socket.listen(
      (raw) => _onClientFrame(slot, raw),
      onError: (_) => _onClientClosed(slot),
      onDone: () => _onClientClosed(slot),
      cancelOnError: true,
    );
  }

  void _onClientFrame(_PeerSlot slot, dynamic raw) {
    if (_disposed || _slots[slot.peerId] != slot || raw is! String) return;

    final SignalingMessage message;
    try {
      message = SignalingMessage.decode(raw);
    } catch (_) {
      unawaited(_closeSlot(slot, errorMessage: 'Malformed signaling message'));
      return;
    }

    if (!slot.authenticated) {
      final err = validateHelloHandshake(message, _pin);
      if (err != null) {
        unawaited(_closeSlot(slot, errorMessage: err));
        return;
      }
      slot.authenticated = true;
      slot.deviceName = extractPeerDeviceName(message);
      _sendToSlot(slot, buildServerWelcome(_sessionId, _deviceName, slot.peerId));
      _hub.emitConnection(
        peerId: slot.peerId,
        isPrimary: slot.isPrimary,
        connected: true,
        deviceName: slot.deviceName,
      );
      _hub.emitMessage(peerId: slot.peerId, isPrimary: slot.isPrimary, message: message);
      return;
    }

    if (message.type == .offer ||
        message.type == .answer ||
        message.type == .ice ||
        message.type == .bye) {
      _hub.emitMessage(peerId: slot.peerId, isPrimary: slot.isPrimary, message: message);
    }
  }

  void _sendToSlot(_PeerSlot? slot, SignalingMessage message) {
    if (_disposed || slot == null || !slot.authenticated) return;
    if (slot.socket.readyState != WebSocket.open) return;
    try {
      slot.socket.add(message.encode());
    } catch (_) {}
  }

  Future<void> _rejectSocket(WebSocket socket, {required String message}) async {
    try {
      socket.add(buildServerError(_sessionId, message).encode());
    } catch (_) {}
    try {
      await socket.close(WebSocketStatus.policyViolation, message);
    } catch (_) {}
  }

  Future<void> _closeSlot(
    _PeerSlot slot, {
    String? byeReason,
    String? errorMessage,
  }) async {
    if (_slots.remove(slot.peerId) == null) return;
    final wasAuthed = slot.authenticated;
    slot.authenticated = false;
    final sub = slot.sub;
    slot.sub = null;
    await sub?.cancel();

    if (errorMessage != null) {
      await _rejectSocket(slot.socket, message: errorMessage);
    } else {
      if (wasAuthed && byeReason != null && slot.socket.readyState == WebSocket.open) {
        try {
          slot.socket.add(buildServerBye(_sessionId, byeReason).encode());
        } catch (_) {}
      }
      try {
        await slot.socket.close(WebSocketStatus.normalClosure, byeReason ?? 'Closed');
      } catch (_) {}
    }
    _emitDisconnected(slot, wasAuthed);
  }

  void _onClientClosed(_PeerSlot slot) {
    if (_slots.remove(slot.peerId) == null) return;
    final wasAuthed = slot.authenticated;
    slot.authenticated = false;
    slot.sub = null;
    _emitDisconnected(slot, wasAuthed);
  }

  void _emitDisconnected(_PeerSlot slot, bool wasAuthed) {
    if (wasAuthed && !_disposed) {
      _hub.emitConnection(
        peerId: slot.peerId,
        isPrimary: slot.isPrimary,
        connected: false,
        deviceName: slot.deviceName,
      );
    }
  }
}
