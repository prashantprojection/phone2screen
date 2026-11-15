import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for signaling condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _expectResponsiveWebShell(String html, List<String> extraTokens) {
  const sharedTokens = [
    'viewport-fit=cover',
    '100dvh',
    'btnFit',
    'btnRotate',
    'btnMirror',
    'btnClipOpen',
    'btnStats',
    'btnFs',
  ];
  for (final token in [...sharedTokens, ...extraTokens]) {
    expect(html, contains(token));
  }
}

void main() {
  test('hello -> welcome and offer -> answer -> ice loopback round-trip', () async {
    final server = SignalingServerService();
    final client = SignalingClientService();
    final serverMsgs = <SignalingMessage>[];
    final clientMsgs = <SignalingMessage>[];
    final connEvents = <bool>[];

    final sub1 = server.messages.listen(serverMsgs.add);
    final sub2 = client.messages.listen(clientMsgs.add);
    final sub3 = server.clientConnectionEvents.listen(connEvents.add);

    addTearDown(() async {
      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
      await client.dispose();
      await server.dispose();
    });

    final port = await server.start(
      preferredPort: 0,
      sessionId: 'loop-1',
      deviceName: 'DesktopRx',
      pin: '4321',
    );
    expect(port, greaterThan(0));
    expect(server.boundPort, port);
    expect(server.isRunning, isTrue);

    await client.connect(
      target: SignalingData(
        ip: '127.0.0.1',
        port: port,
        sessionId: 'loop-1',
        deviceName: 'DesktopRx',
        requiresPin: true,
      ),
      clientDeviceName: 'PixelPhone',
      pin: '4321',
    );
    expect(client.isConnected, isTrue);

    await _waitUntil(
      () =>
          serverMsgs.any((m) => m.type == .hello) &&
          clientMsgs.any((m) => m.type == .welcome) &&
          connEvents.contains(true),
    );

    client.send(
      const SignalingMessage(
        type: .offer,
        sessionId: 'loop-1',
        payload: {'sdp': 'v=0 offer', 'type': 'offer'},
      ),
    );
    await _waitUntil(() => serverMsgs.any((m) => m.type == .offer));
    expect(
      serverMsgs.firstWhere((m) => m.type == .offer).payload['sdp'],
      'v=0 offer',
    );

    server.send(
      const SignalingMessage(
        type: .answer,
        sessionId: 'loop-1',
        payload: {'sdp': 'v=0 answer', 'type': 'answer'},
      ),
    );
    await _waitUntil(() => clientMsgs.any((m) => m.type == .answer));
    expect(
      clientMsgs.firstWhere((m) => m.type == .answer).payload['sdp'],
      'v=0 answer',
    );

    client.send(
      const SignalingMessage(
        type: .ice,
        sessionId: 'loop-1',
        payload: {'candidate': 'candidate:1', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ),
    );
    server.send(
      const SignalingMessage(
        type: .ice,
        sessionId: 'loop-1',
        payload: {'candidate': 'candidate:2', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ),
    );
    await _waitUntil(
      () =>
          serverMsgs.any((m) => m.type == .ice) &&
          clientMsgs.any((m) => m.type == .ice),
    );

    await client.disconnect();
    await _waitUntil(() => connEvents.isNotEmpty && connEvents.last == false);
    expect(client.isConnected, isFalse);
  });

  test('rejects invalid PIN with hello -> error', () async {
    final server = SignalingServerService();
    final client = SignalingClientService();

    addTearDown(() async {
      await client.dispose();
      await server.dispose();
    });

    final port = await server.start(
      preferredPort: 0,
      sessionId: 'loop-pin',
      deviceName: 'PinHost',
      pin: '9999',
    );

    await expectLater(
      client.connect(
        target: SignalingData(
          ip: '127.0.0.1',
          port: port,
          sessionId: 'loop-pin',
          deviceName: 'PinHost',
          requiresPin: true,
        ),
        clientDeviceName: 'PixelPhone',
        pin: '0000',
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('Invalid PIN')),
      ),
    );
    expect(client.isConnected, isFalse);
  });

  test('serves Web Companion HTML with HTTPS endpoint in sendToReceiver mode', () async {
    final server = SignalingServerService();
    final httpClient = HttpClient()
      ..badCertificateCallback = (_, _, _) => true;

    addTearDown(() async {
      httpClient.close(force: true);
      await server.dispose();
    });

    final port = await server.start(
      preferredPort: 0,
      companionMode: .sendToReceiver,
      sessionId: 'web-tx-1',
      deviceName: 'DesktopRx',
    );
    final httpsPort = server.boundHttpsPort;
    expect(httpsPort, isNotNull);

    final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/'));
    final resp = await req.close();
    final body = await utf8.decodeStream(resp);
    expect(resp.statusCode, HttpStatus.ok);
    expect(body, contains('"mode":"sender"'));
    expect(body, contains('"httpsPort":$httpsPort'));
    _expectResponsiveWebShell(body, const [
      'Stream Camera',
      'Share Screen',
      'Switch to Secure HTTPS',
    ]);

    final tlsReq = await httpClient.getUrl(
      Uri.parse('https://127.0.0.1:$httpsPort/health'),
    );
    final tlsResp = await tlsReq.close();
    final tlsJson = jsonDecode(await utf8.decodeStream(tlsResp))
        as Map<String, dynamic>;
    expect(tlsResp.statusCode, HttpStatus.ok);
    expect(tlsJson['sessionId'], 'web-tx-1');
    expect(tlsJson['httpsPort'], httpsPort);
    expect(tlsJson['mode'], 'sendToReceiver');
  });

  test('serves Viewer HTML and handles server-offer -> viewer-answer flow', () async {
    final server = SignalingServerService();
    final client = SignalingClientService();
    final httpClient = HttpClient();
    final serverMsgs = <SignalingMessage>[];
    final clientMsgs = <SignalingMessage>[];

    final sub1 = server.messages.listen(serverMsgs.add);
    final sub2 = client.messages.listen(clientMsgs.add);

    addTearDown(() async {
      httpClient.close(force: true);
      await sub1.cancel();
      await sub2.cancel();
      await client.dispose();
      await server.dispose();
    });

    final port = await server.start(
      preferredPort: 0,
      preferredHttpsPort: null,
      companionMode: .viewSenderStream,
      sessionId: 'view-1',
      deviceName: 'PhoneSender',
    );
    expect(server.boundHttpsPort, isNull);
    expect(server.companionMode, WebCompanionMode.viewSenderStream);

    final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/'));
    final resp = await req.close();
    final html = await utf8.decodeStream(resp);
    expect(resp.statusCode, HttpStatus.ok);
    expect(html, contains('"mode":"viewer"'));
    _expectResponsiveWebShell(html, const [
      'Watch Stream',
      'id="btnFit"',
      'id="btnRotate"',
    ]);

    await client.connect(
      target: SignalingData(
        ip: '127.0.0.1',
        port: port,
        sessionId: 'view-1',
        deviceName: 'PhoneSender',
      ),
      clientDeviceName: 'Web Viewer',
    );
    await _waitUntil(() => clientMsgs.any((m) => m.type == .welcome));

    server.send(
      const SignalingMessage(
        type: .offer,
        sessionId: 'view-1',
        payload: {'sdp': 'v=0 server-offer', 'type': 'offer'},
      ),
    );
    await _waitUntil(() => clientMsgs.any((m) => m.type == .offer));

    client.send(
      const SignalingMessage(
        type: .answer,
        sessionId: 'view-1',
        payload: {'sdp': 'v=0 viewer-answer', 'type': 'answer'},
      ),
    );
    await _waitUntil(() => serverMsgs.any((m) => m.type == .answer));
    expect(
      serverMsgs.firstWhere((m) => m.type == .answer).payload['sdp'],
      'v=0 viewer-answer',
    );
  });
}
