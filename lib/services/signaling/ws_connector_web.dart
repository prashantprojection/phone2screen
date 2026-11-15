import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser WebSocket wrapper built on `package:web` + `dart:js_interop`.
class WsConnection {
  WsConnection(this._socket) {
    _msgSub = _socket.onMessage.listen((event) {
      final data = event.data;
      if (data != null && data.isA<JSString>() && !_incoming.isClosed) {
        _incoming.add((data as JSString).toDart);
      }
    });
    _errSub = _socket.onError.listen((_) => _markClosed());
    _closeSub = _socket.onClose.listen((_) => _markClosed());
  }

  final web.WebSocket _socket;
  final _incoming = StreamController<String>.broadcast();
  final _done = StreamController<void>.broadcast();
  late final StreamSubscription<web.MessageEvent> _msgSub;
  late final StreamSubscription<web.Event> _errSub;
  late final StreamSubscription<web.CloseEvent> _closeSub;
  bool _closed = false;

  Stream<String> get incoming => _incoming.stream;

  Stream<void> get onDone => _done.stream;

  bool get isOpen => !_closed && _socket.readyState == web.WebSocket.OPEN;

  void sendText(String text) {
    if (!isOpen) return;
    _socket.send(text.toJS);
  }

  Future<void> close() async {
    if (!_closed &&
        (_socket.readyState == web.WebSocket.OPEN ||
            _socket.readyState == web.WebSocket.CONNECTING)) {
      _socket.close(1000, 'Closed');
    }
    await _msgSub.cancel();
    await _errSub.cancel();
    await _closeSub.cancel();
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

/// Opens a browser WebSocket connection and waits for `open` within [timeout].
Future<WsConnection> connectWs(String url, Duration timeout) async {
  final socket = web.WebSocket(url);
  final completer = Completer<void>();

  late final StreamSubscription<web.Event> openSub;
  late final StreamSubscription<web.Event> errSub;
  late final StreamSubscription<web.CloseEvent> closeSub;

  openSub = socket.onOpen.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  errSub = socket.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('WebSocket connection error ($url)'));
    }
  });
  closeSub = socket.onClose.listen((event) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('WebSocket closed before open (${event.code})'),
      );
    }
  });

  try {
    await completer.future.timeout(timeout);
    return WsConnection(socket);
  } catch (_) {
    if (socket.readyState == web.WebSocket.OPEN ||
        socket.readyState == web.WebSocket.CONNECTING) {
      socket.close(1000, 'Aborted');
    }
    rethrow;
  } finally {
    await openSub.cancel();
    await errSub.cancel();
    await closeSub.cancel();
  }
}
