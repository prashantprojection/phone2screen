import 'dart:async';

import '../../models/signaling_message.dart';

/// Web stub: browsers cannot bind an embedded `HttpServer`.
class SignalingServerImpl {
  final _messagesController = StreamController<SignalingMessage>.broadcast();
  final _connectionEventsController = StreamController<bool>.broadcast();

  Stream<SignalingMessage> get messages => _messagesController.stream;

  Stream<bool> get clientConnectionEvents => _connectionEventsController.stream;

  int? get boundPort => null;

  bool get isRunning => false;

  Future<int> start({
    int preferredPort = 8080,
    required String sessionId,
    required String deviceName,
    String? pin,
  }) {
    throw UnsupportedError(
      'Hosting a signaling server is not supported on Web.',
    );
  }

  void send(SignalingMessage message) {}

  Future<void> disconnectClient([String reason = 'Host ended session']) async {}

  Future<void> stop() async {}

  Future<void> dispose() async {
    await _messagesController.close();
    await _connectionEventsController.close();
  }
}
