import 'dart:async';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import '../../models/signaling_message.dart';
import 'signaling_port_binder.dart';
import 'web_companion_mode.dart';

/// Native `dart:io` HTTP/HTTPS + WebSocket signaling server with single-peer
/// limit (`maxActivePeers = 1`), optional PIN auth, and Web Companion modes.
class SignalingServerImpl {
  final _messagesController = StreamController<SignalingMessage>.broadcast();
  final _connectionEventsController = StreamController<bool>.broadcast();

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

  WebSocket? _activeSocket;
  StreamSubscription<dynamic>? _clientSub;
  bool _clientAuthenticated = false;
  bool _disposed = false;

  Stream<SignalingMessage> get messages => _messagesController.stream;

  Stream<bool> get clientConnectionEvents => _connectionEventsController.stream;

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
  }) async {
    if (_disposed) {
      throw StateError('SignalingServerService has been disposed.');
    }
    if (isRunning) {
      await stop();
    }

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

    _serverSub = server.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (_) {},
    );
    _httpsServerSub = httpsServer?.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (_) {},
    );

    return server.port;
  }

  void send(SignalingMessage message) {
    final socket = _activeSocket;
    if (_disposed || socket == null || !_clientAuthenticated) return;
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(message.encode());
    } catch (_) {
      // Ignore send errors on races where the socket just closed.
    }
  }

  Future<void> disconnectClient([String reason = 'Host ended session']) async {
    final socket = _activeSocket;
    if (socket == null) return;

    final wasAuthenticated = _clientAuthenticated;
    final sub = _detachActiveSocket();
    await sub?.cancel();

    if (wasAuthenticated && socket.readyState == WebSocket.open) {
      try {
        socket.add(
          SignalingMessage(
            type: .bye,
            sessionId: _sessionId,
            payload: {'reason': reason},
          ).encode(),
        );
      } catch (_) {}
    }

    try {
      await socket.close(WebSocketStatus.normalClosure, reason);
    } catch (_) {}

    _emitDisconnected(wasAuthenticated);
  }

  Future<void> stop() async {
    await disconnectClient('Host stopped session');
    final sub = _serverSub;
    final httpsSub = _httpsServerSub;
    _serverSub = null;
    _httpsServerSub = null;
    await sub?.cancel();
    await httpsSub?.cancel();

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
    await _messagesController.close();
    await _connectionEventsController.close();
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
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Expected WebSocket upgrade');
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    if (_disposed) {
      await socket.close(WebSocketStatus.goingAway, 'Server disposed');
      return;
    }
    socket.pingInterval = const Duration(seconds: 10);

    // Enforce maxActivePeers = 1 so a stray second client cannot hijack an
    // ongoing stream on low-end mobile hardware.
    if (_activeSocket != null) {
      await _rejectSocket(
        socket,
        message: 'Host is already in an active session',
      );
      return;
    }

    _activeSocket = socket;
    _clientAuthenticated = false;
    _clientSub = socket.listen(
      (raw) => _onClientFrame(socket, raw),
      onError: (_) => _onClientClosed(socket),
      onDone: () => _onClientClosed(socket),
      cancelOnError: true,
    );
  }

  void _onClientFrame(WebSocket socket, dynamic raw) {
    if (_disposed || _activeSocket != socket || raw is! String) return;

    SignalingMessage message;
    try {
      message = SignalingMessage.decode(raw);
    } catch (_) {
      unawaited(
        _rejectActiveSocket(socket, message: 'Malformed signaling message'),
      );
      return;
    }

    if (!_clientAuthenticated) {
      if (message.type != .hello) {
        unawaited(
          _rejectActiveSocket(socket, message: 'Expected hello handshake first'),
        );
        return;
      }
      // Validate optional session PIN before admitting the peer and forwarding
      // signaling messages to the WebRTC layer.
      final rawPin = message.payload['pin'];
      final providedPin = rawPin is String ? rawPin : '';
      if (_pin.isNotEmpty && providedPin != _pin) {
        unawaited(_rejectActiveSocket(socket, message: 'Invalid PIN'));
        return;
      }

      _clientAuthenticated = true;
      send(
        SignalingMessage(
          type: .welcome,
          sessionId: _sessionId,
          payload: {'deviceName': _deviceName},
        ),
      );
      if (!_connectionEventsController.isClosed) {
        _connectionEventsController.add(true);
      }
      if (!_messagesController.isClosed) {
        _messagesController.add(message);
      }
      return;
    }

    switch (message.type) {
      case .offer || .answer || .ice || .bye:
        if (!_messagesController.isClosed) {
          _messagesController.add(message);
        }
      case .hello || .welcome || .error:
        // Ignore duplicate handshake or non-client control frames once joined.
        break;
    }
  }

  Future<void> _rejectSocket(
    WebSocket socket, {
    required String message,
  }) async {
    try {
      socket.add(
        SignalingMessage(
          type: .error,
          sessionId: _sessionId,
          payload: {'message': message},
        ).encode(),
      );
    } catch (_) {}
    try {
      await socket.close(WebSocketStatus.policyViolation, message);
    } catch (_) {}
  }

  Future<void> _rejectActiveSocket(
    WebSocket socket, {
    required String message,
  }) async {
    if (_activeSocket == socket) {
      await _detachActiveSocket()?.cancel();
    }
    await _rejectSocket(socket, message: message);
  }

  void _onClientClosed(WebSocket socket) {
    if (_activeSocket != socket) return;
    final wasAuthenticated = _clientAuthenticated;
    _detachActiveSocket();
    _emitDisconnected(wasAuthenticated);
  }

  StreamSubscription<dynamic>? _detachActiveSocket() {
    final sub = _clientSub;
    _activeSocket = null;
    _clientAuthenticated = false;
    _clientSub = null;
    return sub;
  }

  void _emitDisconnected(bool wasAuthenticated) {
    if (wasAuthenticated && !_disposed && !_connectionEventsController.isClosed) {
      _connectionEventsController.add(false);
    }
  }
}
