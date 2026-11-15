import 'dart:async';
import 'dart:io';

/// Native `dart:io` WebSocket wrapper backing [SignalingClientService].
class WsConnection {
  WsConnection(this._socket) {
    _sub = _socket.listen(
      (data) {
        if (data is String && !_incoming.isClosed) {
          _incoming.add(data);
        }
      },
      onError: (_) => _markClosed(),
      onDone: _markClosed,
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final _incoming = StreamController<String>.broadcast();
  final _done = StreamController<void>.broadcast();
  late final StreamSubscription<dynamic> _sub;
  bool _closed = false;

  Stream<String> get incoming => _incoming.stream;

  Stream<void> get onDone => _done.stream;

  bool get isOpen => !_closed && _socket.readyState == WebSocket.open;

  void sendText(String text) {
    if (!isOpen) return;
    try {
      _socket.add(text);
    } catch (_) {
      _markClosed();
    }
  }

  Future<void> close() async {
    if (!_closed) {
      try {
        await _socket.close(WebSocketStatus.normalClosure, 'Closed');
      } catch (_) {}
    }
    await _sub.cancel();
    _markClosed();
  }

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    if (!_done.isClosed) _done.add(null);
    unawaited(_incoming.close());
    unawaited(_done.close());
  }
}

/// Opens a native WebSocket connection within [timeout].
Future<WsConnection> connectWs(String url, Duration timeout) async {
  final socket = await WebSocket.connect(url).timeout(timeout);
  socket.pingInterval = const Duration(seconds: 10);
  return WsConnection(socket);
}
