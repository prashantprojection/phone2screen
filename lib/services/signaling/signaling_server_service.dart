import '../../core/constants/stream_constants.dart';
import '../../models/signaling_message.dart';
import 'signaling_peer_slot.dart';
import 'signaling_server_stub.dart'
    if (dart.library.io) 'signaling_server_io.dart'
    as impl;
import 'web_companion_mode.dart';

export 'signaling_peer_slot.dart';
export 'web_companion_mode.dart';

/// Embedded HTTP/HTTPS + WebSocket signaling server hosted for Receiver or
/// Browser-Viewer modes (`GET /` Web Companion, `GET /health`, `GET /ws`).
class SignalingServerService {
  SignalingServerService() : _impl = impl.SignalingServerImpl();

  final impl.SignalingServerImpl _impl;

  /// Broadcast stream of authenticated primary-peer signaling messages.
  Stream<SignalingMessage> get messages => _impl.messages;

  /// Broadcast stream emitting `true` after `hello -> welcome` auth and
  /// `false` when the primary authenticated peer disconnects.
  Stream<bool> get clientConnectionEvents => _impl.clientConnectionEvents;

  /// Broadcast stream of authenticated signaling messages tagged by `peerId`.
  Stream<PeerSignalingEvent> get peerMessages => _impl.peerMessages;

  /// Broadcast stream of peer auth/disconnect lifecycle events tagged by `peerId`.
  Stream<PeerConnectionEvent> get peerConnectionEvents =>
      _impl.peerConnectionEvents;

  /// TCP port the HTTP/WebSocket server is bound to, or `null` if stopped.
  int? get boundPort => _impl.boundPort;

  /// TCP port the companion HTTPS/WSS server is bound to, or `null` if unused.
  int? get boundHttpsPort => _impl.boundHttpsPort;

  /// Active Browser Web Companion operating mode for `GET /`.
  WebCompanionMode get companionMode => _impl.companionMode;

  /// Whether the signaling HTTP/WebSocket server is currently running.
  bool get isRunning => _impl.isRunning;

  /// Starts HTTP + `/ws` (and companion HTTPS when available) on [preferredPort]
  /// (`0` for ephemeral, or `preferredPort..maxSignalingPort`) allowing up to
  /// [maxPeers] concurrent authenticated WebSocket clients.
  Future<int> start({
    int preferredPort = 8080,
    int? preferredHttpsPort = StreamConstants.defaultHttpsPort,
    WebCompanionMode companionMode = .sendToReceiver,
    required String sessionId,
    required String deviceName,
    String? pin,
    int maxPeers = StreamConstants.maxActivePeers,
  }) => _impl.start(
    preferredPort: preferredPort,
    preferredHttpsPort: preferredHttpsPort,
    companionMode: companionMode,
    sessionId: sessionId,
    deviceName: deviceName,
    pin: pin,
    maxPeers: maxPeers,
  );

  /// Sends a [SignalingMessage] to [peerId] (or the primary peer if omitted).
  void send(SignalingMessage message, {String? peerId}) =>
      _impl.send(message, peerId: peerId);

  /// Sends `bye` (if authenticated) and closes [peerId] (or all active peers).
  Future<void> disconnectClient([
    String reason = 'Host ended session',
    String? peerId,
  ]) => _impl.disconnectClient(reason, peerId);

  /// Disconnects all active clients and closes the underlying servers.
  Future<void> stop() => _impl.stop();

  /// Stops the server and closes all broadcast streams.
  Future<void> dispose() => _impl.dispose();
}
