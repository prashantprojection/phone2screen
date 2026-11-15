import 'dart:convert';

/// Connection endpoint metadata exchanged via QR code or LAN UDP discovery.
class const SignalingData({
  required final String ip,
  required final int port,
  required final String sessionId,
  final String deviceName = 'Phone2Screen',
  final bool requiresPin = false,
}) {
  String get wsUrl => 'ws://$ip:$port/ws';
  String get browserUrl => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'sessionId': sessionId,
    'deviceName': deviceName,
    'requiresPin': requiresPin,
  };

  factory SignalingData.fromJson(Map<String, dynamic> json) {
    return SignalingData(
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      sessionId: json['sessionId'] as String,
      deviceName: (json['deviceName'] as String?) ?? 'Phone2Screen',
      requiresPin: (json['requiresPin'] as bool?) ?? false,
    );
  }

  String toQrString() => jsonEncode(toJson());

  factory SignalingData.fromQrString(String qrString) {
    final json = jsonDecode(qrString) as Map<String, dynamic>;
    return SignalingData.fromJson(json);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalingData &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          sessionId == other.sessionId &&
          deviceName == other.deviceName &&
          requiresPin == other.requiresPin;

  @override
  int get hashCode => Object.hash(ip, port, sessionId, deviceName, requiresPin);

  @override
  String toString() =>
      'SignalingData(ip: $ip, port: $port, sessionId: $sessionId, '
      'deviceName: $deviceName, requiresPin: $requiresPin)';
}
