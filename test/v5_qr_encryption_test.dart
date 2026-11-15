import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/core/theme/app_theme.dart';
import 'package:phone2screen/core/utils/qr_cipher.dart';
import 'package:phone2screen/core/utils/sha256.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/views/receiver/widgets/qr_pairing_card.dart';
import 'package:qr_flutter/qr_flutter.dart';

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _decodeTokenBytes(String token) {
  final body = token.substring(QrCipher.tokenPrefix.length);
  final pad = (4 - body.length % 4) % 4;
  return base64Url.decode('$body${'=' * pad}');
}

String _encodeTokenBytes(List<int> packed) =>
    '${QrCipher.tokenPrefix}${base64UrlEncode(packed).replaceAll('=', '')}';

class const _QrStabilityHarness({
  required final SignalingData endpoint,
  required final int tick,
}) extends StatefulWidget {
  @override
  State<_QrStabilityHarness> createState() => _QrStabilityHarnessState();
}

class _QrStabilityHarnessState extends State<_QrStabilityHarness> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Text('tick:${widget.tick}'),
        QrPairingCard(endpoint: widget.endpoint),
      ],
    );
  }
}

void main() {
  const sampleEndpoint = SignalingData(
    ip: '192.168.1.42',
    port: 8082,
    httpsPort: 8443,
    sessionId: 'SESS9988',
    deviceName: 'StudioDeskPC',
    requiresPin: true,
  );

  group('hmacSha256', () {
    test('matches RFC 4231 Test Case 2 and >64-byte key Test Case 6', () {
      final tc2 = hmacSha256(
        utf8.encode('Jefe'),
        utf8.encode('what do ya want for nothing?'),
      );
      expect(
        _toHex(tc2),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );

      final tc6 = hmacSha256(
        List<int>.filled(131, 0xaa),
        utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
      );
      expect(
        _toHex(tc6),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });
  });

  group('Encrypted SignalingData QR tokens', () {
    test('hides cleartext metadata, randomizes nonces, and round-trips', () {
      final tokenA = sampleEndpoint.toQrString();
      final tokenB = sampleEndpoint.toQrString();

      expect(tokenA, startsWith('P2S1.'));
      expect(tokenB, startsWith('P2S1.'));
      expect(QrCipher.isEncryptedToken(tokenA), isTrue);
      expect(tokenA.contains('='), isFalse);
      expect(tokenA, isNot(equals(tokenB)));

      for (final secret in [
        sampleEndpoint.ip,
        sampleEndpoint.port.toString(),
        sampleEndpoint.httpsPort.toString(),
        sampleEndpoint.sessionId,
        sampleEndpoint.deviceName,
        'requiresPin',
      ]) {
        expect(tokenA, isNot(contains(secret)));
        expect(tokenB, isNot(contains(secret)));
      }

      expect(SignalingData.fromQrString(tokenA), sampleEndpoint);
      expect(SignalingData.fromQrString('  $tokenB\n'), sampleEndpoint);
    });

    test('supports deterministic nonceOverride and validates nonce length', () {
      final nonce = List<int>.generate(12, (i) => i + 10);
      final det1 = sampleEndpoint.toQrString(nonceOverride: nonce);
      final det2 = sampleEndpoint.toQrString(nonceOverride: nonce);

      expect(det1, det2);
      expect(SignalingData.fromQrString(det1), sampleEndpoint);
      expect(
        () => sampleEndpoint.toQrString(nonceOverride: const [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('rejects cleartext JSON, URLs, tampered bytes, and truncated tokens', () {
      final nonce = List<int>.generate(12, (i) => 0x40 + i);
      final validToken = sampleEndpoint.toQrString(nonceOverride: nonce);
      final validBytes = _decodeTokenBytes(validToken);

      final flippedTag = Uint8List.fromList(validBytes);
      flippedTag[flippedTag.length - 1] ^= 0x01;

      final flippedCipher = Uint8List.fromList(validBytes);
      flippedCipher[12] ^= 0x80;

      final zeroCipherPacket = _encodeTokenBytes(Uint8List(28));
      final clipped = validToken.substring(0, validToken.length - 8);
      final nonObjectEncrypted = QrCipher.encryptPayload('[1, 2, 3]');

      final badInputs = <String>[
        jsonEncode(sampleEndpoint.toJson()),
        'http://192.168.1.42:8082',
        'ws://192.168.1.42:8082/ws',
        _encodeTokenBytes(flippedTag),
        _encodeTokenBytes(flippedCipher),
        'P2S1.',
        zeroCipherPacket,
        clipped,
        'P2S1.not!valid!base64',
        nonObjectEncrypted,
      ];

      for (final bad in badInputs) {
        expect(
          () => SignalingData.fromQrString(bad),
          throwsFormatException,
          reason: 'Should reject: $bad',
        );
      }
      expect(QrCipher.isEncryptedToken(jsonEncode(sampleEndpoint.toJson())), isFalse);
      expect(QrCipher.isEncryptedToken('http://192.168.1.42:8082'), isFalse);
    });
  });

  group('QrPairingCard encrypted caching & layout', () {
    Widget wrapWithApp(Widget child) => MaterialApp(
          theme: AppTheme.darkTheme,
          // ignore: deprecated_member_use
          builder: (context, inner) => MaterialUiCompatibilityBridge(
            child: inner ?? const SizedBox.shrink(),
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets('caches QR token across parent rebuilds and updates on endpoint change', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final endpointCopy = SignalingData(
        ip: sampleEndpoint.ip,
        port: sampleEndpoint.port,
        httpsPort: sampleEndpoint.httpsPort,
        sessionId: sampleEndpoint.sessionId,
        deviceName: sampleEndpoint.deviceName,
        requiresPin: sampleEndpoint.requiresPin,
      );
      const changedEndpoint = SignalingData(
        ip: '192.168.1.99',
        port: 8084,
        sessionId: 'NEWSESS1',
        deviceName: 'StudioDeskPC',
        requiresPin: false,
      );

      await tester.pumpWidget(
        wrapWithApp(const _QrStabilityHarness(endpoint: sampleEndpoint, tick: 1)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Encrypted • App-Only QR'), findsOneWidget);
      expect(find.text('3. Tap this screen or scan in Phone2Screen'), findsOneWidget);

      String currentQr() {
        final qrWidget = tester.widget<QrImageView>(find.byType(QrImageView));
        return (qrWidget.key! as ValueKey<String>).value;
      }

      final initialQr = currentQr();
      expect(initialQr, startsWith('P2S1.'));
      expect(SignalingData.fromQrString(initialQr), sampleEndpoint);

      // Unrelated parent rebuild with equal SignalingData instance must keep the exact same QR.
      await tester.pumpWidget(
        wrapWithApp(_QrStabilityHarness(endpoint: endpointCopy, tick: 2)),
      );
      expect(find.text('tick:2'), findsOneWidget);
      expect(currentQr(), initialQr);

      // Endpoint change must regenerate a new encrypted QR token.
      await tester.pumpWidget(
        wrapWithApp(const _QrStabilityHarness(endpoint: changedEndpoint, tick: 3)),
      );
      expect(tester.takeException(), isNull);
      final updatedQr = currentQr();
      expect(updatedQr, isNot(equals(initialQr)));
      expect(SignalingData.fromQrString(updatedQr), changedEndpoint);
    });
  });
}
