import 'dart:convert';

/// Wire message types exchanged over the `/ws` signaling WebSocket.
enum SignalingType { hello, welcome, offer, answer, ice, bye, error }

/// JSON signaling envelope shared between sender and receiver peers.
class const SignalingMessage({
  required final SignalingType type,
  required final String sessionId,
  final Map<String, dynamic> payload = const {},
}) {
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'sessionId': sessionId,
    'payload': payload,
  };

  String encode() => jsonEncode(toJson());

  factory SignalingMessage.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Signaling message must be a JSON object');
    }

    final rawType = decoded['type'];
    if (rawType is! String) {
      throw const FormatException('Signaling message missing string "type"');
    }

    final rawSessionId = decoded['sessionId'];
    if (rawSessionId is! String || rawSessionId.isEmpty) {
      throw const FormatException('Signaling message missing "sessionId"');
    }

    final rawPayload = decoded['payload'];
    final payload = switch (rawPayload) {
      final Map map => Map<String, dynamic>.from(map),
      null => const <String, dynamic>{},
      _ => throw const FormatException('Signaling "payload" must be an object'),
    };

    return SignalingMessage(
      type: _parseType(rawType),
      sessionId: rawSessionId,
      payload: payload,
    );
  }

  static SignalingType _parseType(String rawType) {
    for (final value in SignalingType.values) {
      if (value.name == rawType) return value;
    }
    throw FormatException('Unknown signaling message type: $rawType');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalingMessage &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          sessionId == other.sessionId &&
          _mapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(
    type,
    sessionId,
    Object.hashAllUnordered(
      payload.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'SignalingMessage(${type.name}, sessionId: $sessionId, '
      '${payload.keys.length} keys)';
}
