import 'package:flutter_test/flutter_test.dart';
import 'package:phone2screen/core/constants/stream_constants.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/models/stream_config.dart';
import 'package:phone2screen/models/viewer_display_config.dart';

void main() {
  group('StreamConstants', () {
    test('exposes canonical protocol defaults', () {
      expect(StreamConstants.defaultSignalingPort, 8080);
      expect(StreamConstants.maxSignalingPort, 8095);
      expect(StreamConstants.udpDiscoveryPort, 41234);
      expect(StreamConstants.discoveryMagic, 'P2S_V1');
      expect(StreamConstants.controlChannelLabel, 'phone2screen-control');
      expect(StreamConstants.maxActivePeers, 1);
    });
  });

  group('SignalingData', () {
    test('round-trips JSON and QR payloads with URL getters', () {
      const endpoint = SignalingData(
        ip: '192.168.1.42',
        port: 8082,
        sessionId: 'AB12CD34',
        deviceName: 'Studio PC',
        requiresPin: true,
      );

      expect(endpoint.wsUrl, 'ws://192.168.1.42:8082/ws');
      expect(endpoint.browserUrl, 'http://192.168.1.42:8082');

      final fromJson = SignalingData.fromJson(endpoint.toJson());
      final fromQr = SignalingData.fromQrString(endpoint.toQrString());
      expect(fromJson, endpoint);
      expect(fromQr, endpoint);
    });

    test('applies default deviceName and requiresPin when omitted', () {
      final parsed = SignalingData.fromJson({
        'ip': '10.0.0.5',
        'port': 8080,
        'sessionId': 'S1',
      });
      expect(parsed.deviceName, 'Phone2Screen');
      expect(parsed.requiresPin, isFalse);
    });
  });

  group('SignalingMessage', () {
    test('encodes and decodes all signaling types', () {
      for (final type in SignalingType.values) {
        final message = SignalingMessage(
          type: type,
          sessionId: 'sess-1',
          payload: {'k': 'v', 'n': 42},
        );
        final decoded = SignalingMessage.decode(message.encode());
        expect(decoded, message);
      }
    });

    test('treats omitted or null payload as empty map', () {
      final decoded = SignalingMessage.decode(
        '{"type":"bye","sessionId":"sess-2","payload":null}',
      );
      expect(decoded.type, SignalingType.bye);
      expect(decoded.sessionId, 'sess-2');
      expect(decoded.payload, isEmpty);
    });

    test('throws FormatException for malformed messages', () {
      expect(() => SignalingMessage.decode('[]'), throwsFormatException);
      expect(
        () => SignalingMessage.decode('{"sessionId":"s1"}'),
        throwsFormatException,
      );
      expect(
        () => SignalingMessage.decode('{"type":"hello","sessionId":""}'),
        throwsFormatException,
      );
      expect(
        () => SignalingMessage.decode(
          '{"type":"hello","sessionId":"s1","payload":123}',
        ),
        throwsFormatException,
      );
      expect(
        () => SignalingMessage.decode('{"type":"bogus","sessionId":"s1"}'),
        throwsFormatException,
      );
    });
  });

  group('StreamConfig & ViewerDisplayConfig', () {
    test('StreamConfig resolves dimensions and supports clearDesktopSource', () {
      const base = StreamConfig(
        resolution: .p1080,
        sourceType: .screen,
        desktopSourceId: 'display:1',
      );
      expect(base.width, 1920);
      expect(base.height, 1080);
      expect(StreamResolution.p720.recommendedBitrate, StreamConstants.videoBitrate720p);
      expect(StreamResolution.p4k.width, 3840);

      final updated = base.copyWith(
        resolution: .p720,
        frameRate: 60,
        clearDesktopSource: true,
      );
      expect(updated.resolution, StreamResolution.p720);
      expect(updated.frameRate, 60);
      expect(updated.desktopSourceId, isNull);
    });

    test('ViewerDisplayConfig copyWith updates display transforms', () {
      const defaults = ViewerDisplayConfig();
      expect(defaults.coverFit, isFalse);
      expect(defaults.fullscreenHudVisible, isTrue);
      expect(defaults.showTelemetry, isFalse);

      final updated = defaults.copyWith(
        coverFit: true,
        mirrored: true,
        quarterTurns: 1,
        audioMuted: true,
        isFullscreen: true,
        fullscreenHudVisible: false,
        showTelemetry: true,
      );
      expect(updated.coverFit, isTrue);
      expect(updated.mirrored, isTrue);
      expect(updated.quarterTurns, 1);
      expect(updated.audioMuted, isTrue);
      expect(updated.isFullscreen, isTrue);
      expect(updated.fullscreenHudVisible, isFalse);
      expect(updated.showTelemetry, isTrue);
    });
  });
}
