import '../../models/signaling_message.dart';
import 'signaling_server_stub.dart'
    if (dart.library.io) 'signaling_server_io.dart'
    as impl;

/// Embedded HTTP + WebSocket signaling server hosted by the Receiver device.
/// Serves the Browser Web Companion at `GET /`, health info at `GET /health`,
/// and single-peer JSON signaling at `GET /ws`.
class SignalingServerService {
  SignalingServerService() : _impl = impl.SignalingServerImpl();

  final impl.SignalingServerImpl _impl;

  /// Broadcast stream of authenticated client signaling messages.
  Stream<SignalingMessage> get messages => _impl.messages;

  /// Broadcast stream emitting `true` after `hello -> welcome` auth and
  /// `false` when the authenticated peer disconnects.
  Stream<bool> get clientConnectionEvents => _impl.clientConnectionEvents;

  /// TCP port the HTTP/WebSocket server is bound to, or `null` if stopped.
  int? get boundPort => _impl.boundPort;

  /// Whether the signaling HTTP/WebSocket server is currently running.
  bool get isRunning => _impl.isRunning;

  /// Starts the HTTP + `/ws` server on [preferredPort] (or the next free port
  /// up to `StreamConstants.maxSignalingPort`, or ephemeral when `0`).
  Future<int> start({
    int preferredPort = 8080,
    required String sessionId,
    required String deviceName,
    String? pin,
  }) => _impl.start(
    preferredPort: preferredPort,
    sessionId: sessionId,
    deviceName: deviceName,
    pin: pin,
  );

  /// Sends a [SignalingMessage] to the currently authenticated WebSocket peer.
  void send(SignalingMessage message) => _impl.send(message);

  /// Sends `bye` (if authenticated) and closes the active client socket.
  Future<void> disconnectClient([String reason = 'Host ended session']) =>
      _impl.disconnectClient(reason);

  /// Disconnects any active client and closes the underlying `HttpServer`.
  Future<void> stop() => _impl.stop();

  /// Stops the server and closes all broadcast streams.
  Future<void> dispose() => _impl.dispose();
}
