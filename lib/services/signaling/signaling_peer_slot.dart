import 'dart:async';

import '../../models/signaling_message.dart';

/// Authenticated signaling message tagged with the originating peer slot ID.
class const PeerSignalingEvent({
  required final String peerId,
  required final bool isPrimary,
  required final SignalingMessage message,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerSignalingEvent &&
          runtimeType == other.runtimeType &&
          peerId == other.peerId &&
          isPrimary == other.isPrimary &&
          message == other.message;

  @override
  int get hashCode => Object.hash(peerId, isPrimary, message);
}

/// Lifecycle transition for an authenticated signaling peer slot.
class const PeerConnectionEvent({
  required final String peerId,
  required final bool isPrimary,
  required final bool connected,
  final String? deviceName,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerConnectionEvent &&
          runtimeType == other.runtimeType &&
          peerId == other.peerId &&
          isPrimary == other.isPrimary &&
          connected == other.connected &&
          deviceName == other.deviceName;

  @override
  int get hashCode => Object.hash(peerId, isPrimary, connected, deviceName);
}

/// Shared broadcast event hub for primary-peer legacy streams and multi-peer
/// slot-tagged streams.
class SignalingEventHub {
  final _messages = StreamController<SignalingMessage>.broadcast();
  final _clientEvents = StreamController<bool>.broadcast();
  final _peerMessages = StreamController<PeerSignalingEvent>.broadcast();
  final _peerEvents = StreamController<PeerConnectionEvent>.broadcast();

  Stream<SignalingMessage> get messages => _messages.stream;
  Stream<bool> get clientConnectionEvents => _clientEvents.stream;
  Stream<PeerSignalingEvent> get peerMessages => _peerMessages.stream;
  Stream<PeerConnectionEvent> get peerConnectionEvents => _peerEvents.stream;

  void emitConnection({
    required String peerId,
    required bool isPrimary,
    required bool connected,
    String? deviceName,
  }) {
    if (!_peerEvents.isClosed) {
      _peerEvents.add(PeerConnectionEvent(
        peerId: peerId,
        isPrimary: isPrimary,
        connected: connected,
        deviceName: deviceName,
      ));
    }
    if (isPrimary && !_clientEvents.isClosed) _clientEvents.add(connected);
  }

  void emitMessage({
    required String peerId,
    required bool isPrimary,
    required SignalingMessage message,
  }) {
    if (!_peerMessages.isClosed) {
      _peerMessages.add(
        PeerSignalingEvent(peerId: peerId, isPrimary: isPrimary, message: message),
      );
    }
    if (isPrimary && !_messages.isClosed) _messages.add(message);
  }

  Future<void> close() async {
    await _messages.close();
    await _clientEvents.close();
    await _peerMessages.close();
    await _peerEvents.close();
  }
}

/// Validates an unauthenticated client's first `hello` handshake frame.
String? validateHelloHandshake(SignalingMessage message, String expectedPin) {
  if (message.type != .hello) return 'Expected hello handshake first';
  final rawPin = message.payload['pin'];
  final provided = rawPin is String ? rawPin : '';
  if (expectedPin.isNotEmpty && provided != expectedPin) return 'Invalid PIN';
  return null;
}

/// Extracts a trimmed non-empty device name from a `hello` payload.
String? extractPeerDeviceName(SignalingMessage hello) {
  final raw = hello.payload['deviceName'];
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

SignalingMessage buildServerWelcome(String sessionId, String name, String peerId) =>
    SignalingMessage(
      type: .welcome,
      sessionId: sessionId,
      payload: {'deviceName': name, 'peerId': peerId},
    );

SignalingMessage buildServerBye(String sessionId, String reason) =>
    SignalingMessage(type: .bye, sessionId: sessionId, payload: {'reason': reason});

SignalingMessage buildServerError(String sessionId, String message) =>
    SignalingMessage(type: .error, sessionId: sessionId, payload: {'message': message});
