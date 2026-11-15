import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone2screen/core/constants/stream_constants.dart';
import 'package:phone2screen/models/camera_rig_preset.dart';
import 'package:phone2screen/models/network_interface_info.dart';
import 'package:phone2screen/models/shortcut_config.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/signaling_message.dart';
import 'package:phone2screen/models/stream_config.dart';
import 'package:phone2screen/models/viewer_display_config.dart';
import 'package:phone2screen/models/window_launch_args.dart';
import 'package:phone2screen/providers/preferences_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/providers/shortcut_provider.dart';
import 'package:phone2screen/services/network/network_address_io.dart';
import 'package:phone2screen/services/signaling/signaling_client_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/services/storage/local_preferences_service.dart';
import 'package:phone2screen/services/windowing/desktop_window_service.dart';

class _FakeWindowHandle implements DesktopWindowHandle {
  final _exitCompleter = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill() {
    killed = true;
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    return true;
  }
}

void main() {
  group('Constants, Presets, Display & Serialization', () {
    test('StreamConstants exposes v0.2 bitrate and multi-peer limits', () {
      expect(StreamConstants.maxActivePeers, 1);
      expect(StreamConstants.maxDesktopReceiverPeers, 4);
      expect(StreamConstants.obsCleanFeedPath, '/obs');
      expect(StreamConstants.maxVideoBitrate, 25_000_000);
    });

    test('builtInRigPresets exposes 5 presets and USB Ultra stays unclamped', () {
      expect(builtInRigPresets.length, 5);
      final usbUltra = builtInRigPresets.firstWhere((p) => p.id == 'usb_ultra');
      expect(usbUltra.videoBitrate, 20_000_000);
      final applied = usbUltra.applyTo(const StreamConfig());
      expect(applied.videoBitrate, 20_000_000);
      expect(applied.frameRate, 60);

      final roundTrip = CameraRigPreset.tryFromJson(usbUltra.toJson());
      expect(roundTrip, usbUltra);
      expect(CameraRigPreset.tryFromJson({'id': ''}), isNull);
    });

    test('ViewerDisplayConfig colorMatrix and ViewerDisplayNotifier clamping', () {
      const defaults = ViewerDisplayConfig();
      expect(defaults.hasColorAdjustments, isFalse);
      expect(defaults.hasFramingAdjustments, isFalse);
      expect(defaults.colorMatrix, <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(viewerDisplayProvider.notifier);
      notifier
        ..toggleFit()
        ..toggleCleanFeed()
        ..toggleGrid()
        ..setAspectPreset(.widescreen16x9)
        ..setDigitalZoom(9.0)
        ..setPan(-2.5, 2.5)
        ..setBrightness(1.0)
        ..setContrast(0.1)
        ..setSaturation(5.0);

      final state = container.read(viewerDisplayProvider);
      expect(state.cleanFeedMode, isTrue);
      expect(state.showGrid, isTrue);
      expect(state.aspectPreset.aspectRatio, closeTo(16 / 9, 1e-6));
      expect(state.digitalZoom, 3.0);
      expect(state.panX, -1.0);
      expect(state.panY, 1.0);
      expect(state.brightness, 0.5);
      expect(state.contrast, 0.5);
      expect(state.saturation, 2.0);
      expect(state.hasColorAdjustments, isTrue);
      expect(state.hasFramingAdjustments, isTrue);

      notifier.resetFramingAndColor();
      final reset = container.read(viewerDisplayProvider);
      expect(reset.coverFit, isTrue);
      expect(reset.hasColorAdjustments, isFalse);
      expect(reset.hasFramingAdjustments, isFalse);
    });

    test('AppSettings, StreamConfig, and ShortcutConfig JSON round-trip', () {
      const app = AppSettings(
        themeMode: .light,
        preferredPort: 8090,
        pin: '1234',
        autoCopyClipboard: false,
        ecoDimPreview: true,
      );
      expect(AppSettings.fromJson(app.toJson()), app);

      const stream = StreamConfig(
        resolution: .p4k,
        frameRate: 60,
        videoBitrate: 20_000_000,
        enableAudio: false,
        cameraLens: .front,
        sourceType: .screen,
        desktopSourceId: 'screen:0',
      );
      expect(streamConfigFromJson(streamConfigToJson(stream)), stream);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(shortcutProvider.notifier).updateBinding(
        .toggleCleanFeed,
        const ShortcutBinding(keyId: 0x00000070, keyLabel: 'P', control: true),
      );
      final shortcuts = container.read(shortcutProvider);
      expect(ShortcutConfig.fromJson(shortcuts.toJson()), shortcuts);
    });
  });

  group('USB NIC Priority, Window Args & Multi-Window Registry', () {
    test('USB tethering outranks Wi-Fi, Ethernet, and virtual adapters', () {
      expect(
        isUsbTetherInterface('Remote NDIS based Internet Sharing Device', '192.168.42.129'),
        isTrue,
      );
      expect(isUsbTetherInterface('vEthernet (WSL USB)', '172.20.10.1'), isFalse);

      final usbScore = scoreNetworkInterface(
        name: 'Apple Mobile Device Ethernet',
        address: '172.20.10.2',
        wifiIp: '192.168.1.50',
      );
      final wifiScore = scoreNetworkInterface(
        name: 'Wi-Fi',
        address: '192.168.1.50',
        wifiIp: '192.168.1.50',
      );
      final ethScore = scoreNetworkInterface(
        name: 'Ethernet',
        address: '192.168.1.60',
        wifiIp: '192.168.1.50',
      );
      final wslScore = scoreNetworkInterface(
        name: 'vEthernet (WSL)',
        address: '172.24.0.1',
        wifiIp: '192.168.1.50',
      );
      expect(usbScore, greaterThan(wifiScore));
      expect(wifiScore, greaterThan(ethScore));
      expect(wslScore, lessThan(0));

      const info = NetworkInterfaceInfo(
        name: 'usb0',
        address: '192.168.42.2',
        isPreferred: true,
        isUsbTethered: true,
      );
      expect(info.isUsbTethered, isTrue);
    });

    test('WindowLaunchArgs.parse and DesktopWindowService manage slots', () async {
      final parsed = WindowLaunchArgs.parse([
        '--camera-slot=2',
        '--port=8081',
        '--window-title=Camera 2',
        '--window-offset=36',
        '--clean-feed',
      ]);
      expect(parsed.isSecondaryCameraWindow, isTrue);
      expect(parsed.cameraSlot, 2);
      expect(parsed.preferredPortOverride, 8081);
      expect(parsed.windowTitle, 'Camera 2');
      expect(parsed.windowOffset, 36);
      expect(parsed.cleanFeed, isTrue);

      final spawnedArgs = <List<String>>[];
      final handles = <_FakeWindowHandle>[];
      final service = DesktopWindowService(
        isSupportedOverride: true,
        launcher: (exe, args) async {
          spawnedArgs.add(args);
          final h = _FakeWindowHandle();
          handles.add(h);
          return h;
        },
      );
      addTearDown(service.dispose);

      final e2 = await service.openCameraWindow(cleanFeed: true);
      final e3 = await service.openCameraWindow();
      final e4 = await service.openCameraWindow();
      final overflow = await service.openCameraWindow();
      expect(e2?.slot, 2);
      expect(e2?.port, 8081);
      expect(e2?.cleanFeed, isTrue);
      expect(e3?.slot, 3);
      expect(e4?.slot, 4);
      expect(overflow, isNull);
      expect(spawnedArgs.first, contains('--clean-feed'));
      expect(service.activeWindows.length, 3);

      expect(await service.closeWindow(2), isTrue);
      expect(handles.first.killed, isTrue);
      expect(service.activeWindows.map((e) => e.slot), [3, 4]);
    });
  });

  group('LocalPreferencesService & Multi-Peer SignalingServerService', () {
    test('LocalPreferencesService persists JSON file and Riverpod state', () async {
      final dir = Directory('${Directory.current.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}test_prefs_${DateTime.now().microsecondsSinceEpoch}');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final path = '${dir.path}${Platform.pathSeparator}prefs.json';

      final service = LocalPreferencesService.fromFilePath(path);
      const endpoint = SignalingData(ip: '192.168.42.5', port: 8080, sessionId: 'USB1');
      final container = ProviderContainer(
        overrides: [localPreferencesServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(lastEndpointProvider.notifier).setLastEndpoint(endpoint);
      await container.read(customRigPresetsProvider.notifier).savePreset(
        const CameraRigPreset(
          id: 'custom_1',
          name: 'My Studio',
          subtitle: 'Custom rig',
          resolution: .p1080,
          frameRate: 60,
          videoBitrate: 15_000_000,
        ),
      );

      final reloaded = LocalPreferencesService.fromFilePath(path);
      await reloaded.load();
      expect(reloaded.snapshot.lastEndpoint, endpoint);
      expect(reloaded.snapshot.customPresets.single.isCustom, isTrue);
      expect(reloaded.snapshot.customPresets.single.id, 'custom_1');
    });

    test('SignalingServerService routes multi-peer streams and rejects excess', () async {
      final server = SignalingServerService();
      final c1 = SignalingClientService();
      final c2 = SignalingClientService();
      final c3 = SignalingClientService();
      final peerMsgs = <PeerSignalingEvent>[];
      final peerConns = <PeerConnectionEvent>[];
      final primaryMsgs = <SignalingMessage>[];
      final c1Msgs = <SignalingMessage>[];
      final c2Msgs = <SignalingMessage>[];

      final subs = [
        server.peerMessages.listen(peerMsgs.add),
        server.peerConnectionEvents.listen(peerConns.add),
        server.messages.listen(primaryMsgs.add),
        c1.messages.listen(c1Msgs.add),
        c2.messages.listen(c2Msgs.add),
      ];
      addTearDown(() async {
        for (final s in subs) {
          await s.cancel();
        }
        await c1.dispose();
        await c2.dispose();
        await c3.dispose();
        await server.dispose();
      });

      final port = await server.start(
        preferredPort: 0,
        preferredHttpsPort: null,
        sessionId: 'multi-1',
        deviceName: 'StudioHost',
        maxPeers: 2,
      );
      const base = SignalingData(ip: '127.0.0.1', port: 0, sessionId: 'multi-1');
      final target = SignalingData(ip: base.ip, port: port, sessionId: base.sessionId);

      await c1.connect(target: target, clientDeviceName: 'Phone1');
      await c2.connect(target: target, clientDeviceName: 'Phone2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(peerConns.where((e) => e.connected).length, 2);
      final p1 = peerConns.firstWhere((e) => e.deviceName == 'Phone1');
      final p2 = peerConns.firstWhere((e) => e.deviceName == 'Phone2');
      expect(p1.isPrimary, isTrue);
      expect(p2.isPrimary, isFalse);

      // Targeted send to p2 must not leak to c1, and default send goes to p1.
      server.send(
        const SignalingMessage(type: .answer, sessionId: 'multi-1', payload: {'to': 'p2'}),
        peerId: p2.peerId,
      );
      server.send(
        const SignalingMessage(type: .answer, sessionId: 'multi-1', payload: {'to': 'p1'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c2Msgs.any((m) => m.payload['to'] == 'p2'), isTrue);
      expect(c1Msgs.any((m) => m.payload['to'] == 'p2'), isFalse);
      expect(c1Msgs.any((m) => m.payload['to'] == 'p1'), isTrue);
      expect(c2Msgs.any((m) => m.payload['to'] == 'p1'), isFalse);
      expect(primaryMsgs.every((m) => m.type == .hello), isTrue);

      await expectLater(
        c3.connect(target: target, clientDeviceName: 'Phone3'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
