import '../../core/constants/stream_constants.dart';
import '../../models/signaling_message.dart';
import 'signaling_server_stub.dart'
    if (dart.library.io) 'signaling_server_io.dart'
    as impl;
import 'web_companion_mode.dart';

export 'web_companion_mode.dart';

/// Embedded HTTP/HTTPS + WebSocket signaling server hosted for Receiver or
/// Browser-Viewer modes (`GET /` Web Companion, `GET /health`, `GET /ws`).
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

  /// TCP port the companion HTTPS/WSS server is bound to, or `null` if unused.
  int? get boundHttpsPort => _impl.boundHttpsPort;

  /// Active Browser Web Companion operating mode for `GET /`.
  WebCompanionMode get companionMode => _impl.companionMode;

  /// Whether the signaling HTTP/WebSocket server is currently running.
  bool get isRunning => _impl.isRunning;

  /// Starts HTTP + `/ws` (and companion HTTPS when available) on [preferredPort]
  /// (`0` for ephemeral, or `preferredPort..maxSignalingPort`).
  Future<int> start({
    int preferredPort = 8080,
    int? preferredHttpsPort = StreamConstants.defaultHttpsPort,
    WebCompanionMode companionMode = .sendToReceiver,
    required String sessionId,
    required String deviceName,
    String? pin,
  }) => _impl.start(
    preferredPort: preferredPort,
    preferredHttpsPort: preferredHttpsPort,
    companionMode: companionMode,
    sessionId: sessionId,
    deviceName: deviceName,
    pin: pin,
  );

  /// Sends a [SignalingMessage] to the currently authenticated WebSocket peer.
  void send(SignalingMessage message) => _impl.send(message);

  /// Sends `bye` (if authenticated) and closes the active client socket.
  Future<void> disconnectClient([String reason = 'Host ended session']) =>
      _impl.disconnectClient(reason);

  /// Disconnects any active client and closes the underlying servers.
  Future<void> stop() => _impl.stop();

  /// Stops the server and closes all broadcast streams.
  Future<void> dispose() => _impl.dispose();
}
