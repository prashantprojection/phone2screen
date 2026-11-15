import 'dart:convert';

import '../core/utils/qr_cipher.dart';

/// Connection endpoint metadata exchanged via QR code or LAN UDP discovery.
class const SignalingData({
  required final String ip,
  required final int port,
  final int? httpsPort,
  required final String sessionId,
  final String deviceName = 'Phone2Screen',
  final bool requiresPin = false,
}) {
  String get wsUrl => 'ws://$ip:$port/ws';
  String get browserUrl => 'http://$ip:$port';
  String? get httpsBrowserUrl =>
      httpsPort != null ? 'https://$ip:$httpsPort' : null;

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    if (httpsPort != null) 'httpsPort': httpsPort,
    'sessionId': sessionId,
    'deviceName': deviceName,
    'requiresPin': requiresPin,
  };

  factory SignalingData.fromJson(Map<String, dynamic> json) {
    return SignalingData(
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      httpsPort: (json['httpsPort'] as num?)?.toInt(),
      sessionId: json['sessionId'] as String,
      deviceName: (json['deviceName'] as String?) ?? 'Phone2Screen',
      requiresPin: (json['requiresPin'] as bool?) ?? false,
    );
  }

  /// Encrypts endpoint metadata into an authenticated app-only `P2S1.` QR token.
  String toQrString({List<int>? nonceOverride}) => QrCipher.encryptPayload(
    jsonEncode(toJson()),
    nonceOverride: nonceOverride,
  );

  /// Decrypts and verifies an app-only `P2S1.` QR pairing token.
  factory SignalingData.fromQrString(String qrString) {
    final decrypted = QrCipher.decryptPayload(qrString);
    final decoded = jsonDecode(decrypted);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid QR payload: expected JSON object');
    }
    return SignalingData.fromJson(decoded);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalingData &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          httpsPort == other.httpsPort &&
          sessionId == other.sessionId &&
          deviceName == other.deviceName &&
          requiresPin == other.requiresPin;

  @override
  int get hashCode =>
      Object.hash(ip, port, httpsPort, sessionId, deviceName, requiresPin);

  @override
  String toString() =>
      'SignalingData(ip: $ip, port: $port, httpsPort: $httpsPort, '
      'sessionId: $sessionId, deviceName: $deviceName, requiresPin: $requiresPin)';
}
