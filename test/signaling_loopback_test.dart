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
}
