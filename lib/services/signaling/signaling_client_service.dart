import 'dart:async';

import '../../core/constants/stream_constants.dart';
import '../../models/signaling_data.dart';
import '../../models/signaling_message.dart';
import 'ws_connector_io.dart'
    if (dart.library.js_interop) 'ws_connector_web.dart'
    as ws_impl;

/// WebSocket signaling client used by the Sender (native or Web) to perform
/// the `hello -> welcome` handshake and exchange WebRTC SDP/ICE messages.
class SignalingClientService {
  final _messagesController = StreamController<SignalingMessage>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();

  ws_impl.WsConnection? _conn;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<void>? _doneSub;
  Completer<void>? _welcomeCompleter;

  bool _connected = false;
  bool _disposed = false;
  bool _intentionalDisconnect = false;

  /// Broadcast stream of decoded [SignalingMessage] envelopes from the host.
  Stream<SignalingMessage> get messages => _messagesController.stream;

  /// Broadcast stream firing when an established signaling session drops
  /// unexpectedly (not on local [disconnect] / [dispose]).
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// Whether the WebSocket is open and the `hello -> welcome` handshake passed.
  bool get isConnected => _connected && (_conn?.isOpen ?? false);

  /// Connects to `target.wsUrl`, sends `hello` (with optional [pin]), and
  /// waits for `.welcome`. Throws a descriptive [StateError] on rejection or
  /// timeout.
  Future<void> connect({
    required SignalingData target,
    required String clientDeviceName,
    String? pin,
  }) async {
    if (_disposed) {
      throw StateError('SignalingClientService has been disposed.');
    }
    if (_conn != null) {
      await disconnect();
    }

    _intentionalDisconnect = false;

    final ws_impl.WsConnection conn;
    try {
      conn = await ws_impl.connectWs(
        target.wsUrl,
        StreamConstants.connectionTimeout,
      );
    } on TimeoutException {
      throw StateError(
        'Timed out connecting to receiver at ${target.wsUrl}.',
      );
    } catch (e) {
      throw StateError(
        'Could not connect to receiver at ${target.wsUrl}: $e',
      );
    }

    if (_disposed || _intentionalDisconnect) {
      await conn.close();
      throw StateError('Signaling connection aborted.');
    }

    _conn = conn;
    _connected = false;
    final welcomeCompleter = Completer<void>();
    _welcomeCompleter = welcomeCompleter;

    // Subscribe before sending hello so an immediate welcome/error frame is
    // never missed.
    _msgSub = conn.incoming.listen((raw) => _onRawFrame(conn, raw));
    _doneSub = conn.onDone.listen((_) => _onSocketDone(conn));

    conn.sendText(
      SignalingMessage(
        type: .hello,
        sessionId: target.sessionId,
        payload: {'deviceName': clientDeviceName, 'pin': pin ?? ''},
      ).encode(),
    );

    try {
      await welcomeCompleter.future.timeout(StreamConstants.connectionTimeout);
    } on TimeoutException {
      await _closeConnection();
      throw StateError(
        'Timed out waiting for welcome handshake from ${target.wsUrl}.',
      );
    } catch (e) {
      await _closeConnection();
      if (e is StateError) rethrow;
      throw StateError('Signaling handshake failed: $e');
    } finally {
      if (_welcomeCompleter == welcomeCompleter) {
        _welcomeCompleter = null;
      }
    }
  }

  /// Sends a signaling message once the `hello -> welcome` handshake succeeded.
  void send(SignalingMessage message) {
    if (_disposed || !_connected) return;
    _conn?.sendText(message.encode());
  }

  /// Gracefully closes the active WebSocket signaling session.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    final pending = _welcomeCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Disconnected during handshake.'));
    }
    await _closeConnection();
  }

  /// Disconnects any active session and closes broadcast streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _messagesController.close();
    await _disconnectedController.close();
  }

  void _onRawFrame(ws_impl.WsConnection conn, String raw) {
    if (_disposed || _conn != conn) return;

    final SignalingMessage message;
    try {
      message = SignalingMessage.decode(raw);
    } catch (_) {
      return;
    }

    final pending = _welcomeCompleter;
    if (pending != null && !pending.isCompleted) {
      if (message.type == .welcome) {
        _connected = true;
        pending.complete();
        if (!_messagesController.isClosed) {
          _messagesController.add(message);
        }
        return;
      }
      if (message.type == .error) {
        final rawReason = message.payload['message'];
        final reason = rawReason is String && rawReason.isNotEmpty
            ? rawReason
            : 'Connection rejected by receiver.';
        pending.completeError(StateError(reason));
        return;
      }
    }

    if (_connected && !_messagesController.isClosed) {
      _messagesController.add(message);
    }
  }

  void _onSocketDone(ws_impl.WsConnection conn) {
    if (_conn != conn) return;

    final pending = _welcomeCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('Signaling server closed connection before welcome.'),
      );
    }

    final wasConnected = _connected;
    final intentional = _intentionalDisconnect;

    _conn = null;
    _connected = false;
    _msgSub = null;
    _doneSub = null;

    // Suppress disconnect notifications when handshake never succeeded or when
    // the caller triggered disconnect() locally.
    if (wasConnected &&
        !intentional &&
        !_disposed &&
        !_disconnectedController.isClosed) {
      _disconnectedController.add(null);
    }
  }

  Future<void> _closeConnection() async {
    final conn = _conn;
    _conn = null;
    _connected = false;

    final msgSub = _msgSub;
    _msgSub = null;
    final doneSub = _doneSub;
    _doneSub = null;

    await msgSub?.cancel();
    await doneSub?.cancel();
    await conn?.close();
  }
}
