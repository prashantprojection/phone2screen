import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone2screen/core/constants/stream_constants.dart';
import 'package:phone2screen/models/audio_routing_config.dart';
import 'package:phone2screen/models/camera_control_state.dart';
import 'package:phone2screen/models/discovered_peer.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/stream_config.dart';
import 'package:phone2screen/services/network/usb_bridge_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/services/webrtc/audio_routing_service.dart';
import 'package:phone2screen/services/webrtc/camera_control_service.dart';
import 'package:phone2screen/services/windowing/windows_studio_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsStudioService & AudioRoutingConfig', () {
    test('detectVirtualCamName and MethodChannel calls handle data & errors', () async {
      expect(VideoCaptureDeviceInfo.detectVirtualCamName('OBS Virtual Camera'), isTrue);
      expect(VideoCaptureDeviceInfo.detectVirtualCamName('Elgato Facecam Virtual'), isTrue);
      expect(VideoCaptureDeviceInfo.detectVirtualCamName('Logitech BRIO'), isFalse);

      const channel = MethodChannel('phone2screen/windows_studio');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      var alwaysOnTop = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'listVideoCaptureDevices':
            return [
              {'name': 'OBS Virtual Camera', 'devicePath': 'obs://0', 'isVirtualCam': true},
              {'name': 'USB Webcam', 'devicePath': 'usb://1', 'isVirtualCam': false},
            ];
          case 'listAudioOutputDevices':
            return [
              {'id': '0', 'name': 'Speakers (Realtek)', 'isVirtualCable': false},
              {'id': '1', 'name': 'CABLE Input (VB-Audio Virtual Cable)', 'isVirtualCable': true},
            ];
          case 'setAlwaysOnTop':
            alwaysOnTop = (call.arguments as Map)['enabled'] as bool;
            return true;
          case 'getAlwaysOnTop':
            return alwaysOnTop;
          default:
            return null;
        }
      });

      final win = WindowsStudioService(channel: channel, isSupportedOverride: true);
      final cams = await win.listVideoCaptureDevices();
      expect(cams.length, 2);
      expect(cams.first.isVirtualCam, isTrue);
      expect(cams.last.isVirtualCam, isFalse);

      final outs = await win.listAudioOutputDevices();
      expect(outs.length, 2);
      expect(outs.last.isVirtualCable, isTrue);

      expect(await win.setAlwaysOnTop(true), isTrue);
      expect(await win.getAlwaysOnTop(), isTrue);

      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await win.listVideoCaptureDevices(), isEmpty);
      expect(await win.setAlwaysOnTop(false), isFalse);

      final unsupported = WindowsStudioService(channel: channel, isSupportedOverride: false);
      expect(await unsupported.listAudioOutputDevices(), isEmpty);
      expect(await unsupported.getAlwaysOnTop(), isFalse);
    });

    test('AudioStudioConfig clamps values, serializes, and falls back via AudioRoutingService', () async {
      expect(MicProcessingMode.voiceClean.label, 'Voice Clean');
      expect(MicProcessingMode.studioRaw.label, 'Studio Raw');
      expect(AudioEndpointDevice.detectVirtualCableLabel('VoiceMeeter Input'), isTrue);
      expect(AudioEndpointDevice.detectVirtualCableLabel('Desktop Speakers'), isFalse);

      const cfg = AudioStudioConfig(
        outputDeviceId: '1',
        gain: 1.5,
        lipSyncDelayMs: 120,
        micMode: .studioRaw,
      );
      expect(AudioStudioConfig.fromJson(cfg.toJson()), cfg);
      final clamped = AudioStudioConfig.fromJson({
        'gain': 9.0,
        'lipSyncDelayMs': 999,
        'micMode': 'unknown',
      });
      expect(clamped.gain, 2.0);
      expect(clamped.lipSyncDelayMs, 500);
      expect(clamped.micMode, MicProcessingMode.voiceClean);
      expect(cfg.copyWith(clearOutputDevice: true).outputDeviceId, isNull);

      const channel = MethodChannel('phone2screen/windows_studio');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listAudioOutputDevices') {
          return [
            {'id': '0', 'name': 'Speakers', 'isVirtualCable': false},
            {'id': '0', 'name': 'Speakers Duplicate', 'isVirtualCable': false},
            {'id': '1', 'name': 'VB-Audio Virtual Cable', 'isVirtualCable': true},
          ];
        }
        return null;
      });

      final audio = AudioRoutingService(
        windowsStudio: WindowsStudioService(channel: channel, isSupportedOverride: true),
      );
      final list = await audio.listAudioOutputs();
      expect(list.first.id, 'default');
      expect(list.where((d) => d.id == '0').length, 1);
      expect(list.any((d) => d.id == '1' && d.isVirtualCable), isTrue);
      expect(await audio.selectOutputDevice(null), isA<bool>());
      await audio.applyStreamGain(null, muted: true, gain: 1.0);
    });
  });

  group('VoiceMode, StreamConstants, /p2s-info, /obs?delay, & UsbBridgeService', () {
    test('RemoteCameraState voiceClean, StreamConfig voiceCleanAudio, & CameraControlService.voiceMode', () async {
      const cmd = RemoteCameraCommand(command: .voiceMode, enabled: false);
      expect(RemoteCameraCommand.tryFromJson(cmd.toJson()), cmd);

      const state = RemoteCameraState(voiceClean: false);
      expect(RemoteCameraState.tryFromJson(state.toJson()), state);
      expect(RemoteCameraState.tryFromJson({'kind': 'cam_state'})?.voiceClean, isTrue);

      const streamCfg = StreamConfig(voiceCleanAudio: false);
      expect(streamCfg.copyWith(voiceCleanAudio: true).voiceCleanAudio, isTrue);

      final ctrl = CameraControlService();
      final next = await ctrl.applyCommand(
        const RemoteCameraCommand(command: .voiceMode),
        const RemoteCameraState(voiceClean: true),
        stream: null,
        switchCamera: () async => false,
        toggleTorch: (_) async => false,
        setMicMuted: (_) {},
      );
      expect(next.voiceClean, isFalse);
    });

    test('serves /p2s-info & /obs?delay=250 and probes loopback receivers', () async {
      expect(StreamConstants.usbInfoPath, '/p2s-info');
      expect(StreamConstants.defaultObsWsPort, 4455);

      await HttpOverrides.runWithHttpOverrides(() async {
        final server = SignalingServerService();
        final viewerServer = SignalingServerService();
        final httpClient = HttpClient();
        addTearDown(() async {
          httpClient.close(force: true);
          await server.dispose();
          await viewerServer.dispose();
        });

        final port = await server.start(
          preferredPort: 0,
          preferredHttpsPort: null,
          companionMode: .sendToReceiver,
          sessionId: 'usb-rx-1',
          deviceName: 'Desktop Studio',
          pin: '1234',
        );
        final viewerPort = await viewerServer.start(
          preferredPort: 0,
          preferredHttpsPort: null,
          companionMode: .viewSenderStream,
          sessionId: 'web-tx-1',
          deviceName: 'Phone Cam',
        );

        final infoReq = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/p2s-info'));
        final infoResp = await infoReq.close();
        final infoJson = jsonDecode(await utf8.decodeStream(infoResp)) as Map<String, dynamic>;
        expect(infoResp.statusCode, HttpStatus.ok);
        expect(infoJson['magic'], StreamConstants.discoveryMagic);
        expect(infoJson['ip'], '127.0.0.1');
        expect(infoJson['port'], port);
        expect(infoJson['sessionId'], 'usb-rx-1');
        expect(infoJson['requiresPin'], isTrue);

        final obsReq = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/obs?delay=250'));
        final obsResp = await obsReq.close();
        final obsHtml = await utf8.decodeStream(obsResp);
        for (final token in const [
          "q.get('delay')",
          'AudioContext',
          'createMediaStreamSource',
          'DelayNode',
          'delayTime.value = delayMs / 1000',
          'v.muted = true',
        ]) {
          expect(obsHtml, contains(token));
        }

        final bridgeDefault = UsbBridgeService();
        addTearDown(bridgeDefault.dispose);
        expect(await bridgeDefault.probeLoopbackReceivers(ports: [port]), isEmpty);

        final bridge = UsbBridgeService(allowInTestOverride: true);
        addTearDown(bridge.dispose);
        final peers = await bridge.probeLoopbackReceivers(
          ports: [port, viewerPort, 1],
        );
        expect(peers.length, 1);
        expect(peers.single.isUsbLoopback, isTrue);
        expect(
          peers.single.endpoint,
          SignalingData(
            ip: '127.0.0.1',
            port: port,
            sessionId: 'usb-rx-1',
            deviceName: 'Desktop Studio',
            requiresPin: true,
          ),
        );
        expect(
          await bridge.probeLoopbackReceivers(ports: [port], ignoreSessionId: 'usb-rx-1'),
          isEmpty,
        );
      }, _RealHttpOverrides());
    });

    test('UsbBridgeService syncAdbReversePorts parses devices and handles missing adb', () async {
      final calls = <List<String>>[];
      final bridge = UsbBridgeService(
        processRunner: (exe, args) async {
          calls.add([exe, ...args]);
          if (args.length == 1 && args.first == 'devices') {
            return (
              exitCode: 0,
              stdout: 'List of devices attached\nSER123\tdevice\nSER999\tunauthorized\n',
              stderr: '',
            );
          }
          return (exitCode: 0, stdout: '', stderr: '');
        },
      );
      final emitted = <UsbBridgeStatus>[];
      final sub = bridge.statusStream.listen(emitted.add);
      addTearDown(() async {
        await sub.cancel();
        await bridge.dispose();
      });

      final status = await bridge.syncAdbReversePorts([8080, 8081, 8080]);
      await Future<void>.delayed(Duration.zero);
      expect(status.adbAvailable, isTrue);
      expect(status.connectedSerials, ['SER123']);
      expect(status.unauthorizedSerials, ['SER999']);
      expect(status.forwardedPorts, [8080, 8081]);
      expect(status.hasActiveTunnel, isTrue);
      expect(bridge.currentStatus, status);
      expect(emitted.last, status);
      expect(calls, [
        ['adb', 'devices'],
        ['adb', '-s', 'SER123', 'reverse', 'tcp:8080', 'tcp:8080'],
        ['adb', '-s', 'SER123', 'reverse', 'tcp:8081', 'tcp:8081'],
      ]);

      final missingAdb = UsbBridgeService(
        processRunner: (_, _) async => throw const ProcessException('adb', ['devices']),
      );
      addTearDown(missingAdb.dispose);
      final missingStatus = await missingAdb.syncAdbReversePorts([8080]);
      expect(missingStatus.adbAvailable, isFalse);
      expect(missingStatus.hasActiveTunnel, isFalse);

      expect(
        DiscoveredPeer(
          endpoint: const SignalingData(ip: '127.0.0.1', port: 8080, sessionId: 's1'),
          lastSeen: DateTime.utc(2026),
          isUsbLoopback: true,
        ).isUsbLoopback,
        isTrue,
      );
    });
  });
}
