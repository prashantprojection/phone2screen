import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sha256.dart';

/// App-only authenticated stream cipher for encrypted `P2S1.` QR pairing tokens.
abstract final class QrCipher {
  static const String tokenPrefix = 'P2S1.';
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  // App-scoped key provides authenticated QR obfuscation and tamper protection
  // so external camera/QR apps cannot read host IPs, ports, session IDs, or PIN flags.
  static const List<int> _appPairingKey = <int>[
    0x7c, 0x39, 0xe1, 0x4b, 0x92, 0x0f, 0xd4, 0x61,
    0x28, 0xb7, 0x55, 0xa3, 0x1e, 0x8d, 0xc9, 0x40,
    0xf3, 0x62, 0x19, 0x84, 0xab, 0x0d, 0x77, 0xe5,
    0x3a, 0xce, 0x91, 0x26, 0x5f, 0xb0, 0x48, 0xd2,
  ];

  /// Returns whether [raw] starts with the encrypted `P2S1.` pairing prefix.
  static bool isEncryptedToken(String raw) =>
      raw.trim().startsWith(tokenPrefix);

  /// Encrypts [plaintext] into an unpadded `P2S1.<base64url>` pairing token.
  static String encryptPayload(String plaintext, {List<int>? nonceOverride}) {
    final nonce = _resolveNonce(nonceOverride);
    final encKey = _deriveKey(nonce, isMac: false);
    final macKey = _deriveKey(nonce, isMac: true);

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final cipherBytes = _xorKeystream(encKey, nonce, plainBytes);
    final tag = _computeTag(macKey, nonce, cipherBytes);

    final cipherEnd = _nonceLength + cipherBytes.length;
    final packed = Uint8List(cipherEnd + _tagLength)
      ..setRange(0, _nonceLength, nonce)
      ..setRange(_nonceLength, cipherEnd, cipherBytes)
      ..setRange(cipherEnd, cipherEnd + _tagLength, tag);

    return '$tokenPrefix${base64UrlEncode(packed).replaceAll('=', '')}';
  }

  /// Verifies and decrypts a `P2S1.<base64url>` token, throwing
  /// [FormatException] on any prefix, decoding, length, or MAC mismatch.
  static String decryptPayload(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith(tokenPrefix)) {
      throw const FormatException('Invalid QR token: missing P2S1. prefix');
    }

    final body = trimmed.substring(tokenPrefix.length);
    if (body.isEmpty) {
      throw const FormatException('Invalid QR token: empty payload');
    }

    final padCount = (4 - body.length % 4) % 4;
    final padded = padCount == 0 ? body : '$body${'=' * padCount}';
    final packed = base64Url.decode(padded);

    if (packed.length <= _nonceLength + _tagLength) {
      throw const FormatException('Invalid QR token: truncated payload');
    }

    final cipherEnd = packed.length - _tagLength;
    final nonce = packed.sublist(0, _nonceLength);
    final cipherBytes = packed.sublist(_nonceLength, cipherEnd);
    final actualTag = packed.sublist(cipherEnd);

    final encKey = _deriveKey(nonce, isMac: false);
    final macKey = _deriveKey(nonce, isMac: true);
    final expectedTag = _computeTag(macKey, nonce, cipherBytes);

    if (!_constantTimeEquals(expectedTag, actualTag)) {
      throw const FormatException('Invalid QR token: authentication tag mismatch');
    }

    final plainBytes = _xorKeystream(encKey, nonce, cipherBytes);
    return utf8.decode(plainBytes);
  }

  static Uint8List _resolveNonce(List<int>? nonceOverride) {
    if (nonceOverride != null && nonceOverride.length != _nonceLength) {
      throw ArgumentError.value(
        nonceOverride.length,
        'nonceOverride',
        'Nonce must be exactly $_nonceLength bytes',
      );
    }
    final rng = nonceOverride == null ? math.Random.secure() : null;
    final nonce = Uint8List(_nonceLength);
    for (var i = 0; i < _nonceLength; i++) {
      nonce[i] = (nonceOverride != null ? nonceOverride[i] : rng!.nextInt(256)) & 0xff;
    }
    return nonce;
  }

  static Uint8List _deriveKey(List<int> nonce, {required bool isMac}) {
    final label = isMac ? 'P2S1-MAC' : 'P2S1-ENC';
    return hmacSha256(_appPairingKey, [isMac ? 0x02 : 0x01, ...utf8.encode(label), ...nonce]);
  }

  static Uint8List _computeTag(List<int> macKey, List<int> nonce, List<int> cipherBytes) =>
      hmacSha256(macKey, [...utf8.encode('P2S1'), ...nonce, ...cipherBytes])
          .sublist(0, _tagLength);

  // Counter-mode HMAC-SHA256 keystream XOR using big-endian 32-bit block index.
  static Uint8List _xorKeystream(
    List<int> encKey,
    List<int> nonce,
    List<int> input,
  ) {
    final out = Uint8List(input.length);
    final counterBlock = Uint8List(_nonceLength + 4);
    counterBlock.setRange(0, _nonceLength, nonce);
    final bd = ByteData.sublistView(counterBlock);

    var blockIndex = 0;
    for (var offset = 0; offset < input.length; offset += 32) {
      bd.setUint32(_nonceLength, blockIndex);
      final stream = hmacSha256(encKey, counterBlock);
      final end = math.min(offset + 32, input.length);
      for (var i = offset; i < end; i++) {
        out[i] = (input[i] & 0xff) ^ stream[i - offset];
      }
      blockIndex++;
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
