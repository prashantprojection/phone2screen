import 'dart:async';

import '../../core/constants/stream_constants.dart';
import '../../models/signaling_message.dart';
import 'signaling_peer_slot.dart';
import 'web_companion_mode.dart';

/// Web stub: browsers cannot bind an embedded `HttpServer`.
class SignalingServerImpl {
  final _hub = SignalingEventHub();

  Stream<SignalingMessage> get messages => _hub.messages;
  Stream<bool> get clientConnectionEvents => _hub.clientConnectionEvents;
  Stream<PeerSignalingEvent> get peerMessages => _hub.peerMessages;
  Stream<PeerConnectionEvent> get peerConnectionEvents => _hub.peerConnectionEvents;
  int? get boundPort => null;
  int? get boundHttpsPort => null;
  WebCompanionMode get companionMode => .sendToReceiver;
  bool get isRunning => false;

  Future<int> start({
    int preferredPort = 8080,
    int? preferredHttpsPort = StreamConstants.defaultHttpsPort,
    WebCompanionMode companionMode = .sendToReceiver,
    required String sessionId,
    required String deviceName,
    String? pin,
    int maxPeers = StreamConstants.maxActivePeers,
  }) {
    throw UnsupportedError('Hosting a signaling server is not supported on Web.');
  }

  void send(SignalingMessage message, {String? peerId}) {}

  Future<void> disconnectClient([
    String reason = 'Host ended session',
    String? peerId,
  ]) async {}

  Future<void> stop() async {}

  Future<void> dispose() => _hub.close();
}
