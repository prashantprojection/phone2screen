import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/core/theme/app_colors.dart';
import 'package:phone2screen/core/utils/sha256.dart';
import 'package:phone2screen/models/discovered_peer.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/viewer_display_config.dart';
import 'package:phone2screen/providers/discovery_provider.dart';
import 'package:phone2screen/providers/obs_sync_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/services/obs/obs_websocket_service.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/webrtc/audio_routing_service.dart';
import 'package:phone2screen/services/windowing/windows_studio_service.dart';
import 'package:phone2screen/views/receiver/widgets/obs_virtual_cam_sheet.dart';
import 'package:phone2screen/views/receiver/widgets/remote_camera_panel.dart';
import 'package:phone2screen/views/sender/sender_screen.dart';
import 'package:phone2screen/views/sender/widgets/nearby_devices_list.dart';
import 'package:phone2screen/views/shared/video_stage_widget.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _FakeMediaStream implements MediaStream {
  @override String get id => 'v3-stream';
  @override String get ownerTag => 'local';
  @override List<MediaStreamTrack> getAudioTracks() => const [];
  @override List<MediaStreamTrack> getVideoTracks() => const [];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticSessionNotifier extends SessionNotifier {
  final SessionState initial;
  _StaticSessionNotifier(this.initial);
  @override SessionState build() => initial;
  @override Future<void> startDiscovery() async {}
}

class _StaticUsbPeersNotifier extends UsbLoopbackPeersNotifier {
  final List<DiscoveredPeer> peers;
  _StaticUsbPeersNotifier(this.peers);
  @override List<DiscoveredPeer> build() => peers;
}

class _FakeWinStudio extends WindowsStudioService {
  _FakeWinStudio() : super(isSupportedOverride: true);
  bool _pinned = false;
  @override Future<List<VideoCaptureDeviceInfo>> listVideoCaptureDevices() async => const [
    VideoCaptureDeviceInfo(name: 'OBS Virtual Camera', devicePath: 'obs://0', isVirtualCam: true),
  ];
  @override Future<bool> getAlwaysOnTop() async => _pinned;
  @override Future<bool> setAlwaysOnTop(bool enabled) async => _pinned = enabled;
}

class _FakeAudioRouting extends AudioRoutingService {
  @override Future<List<AudioEndpointDevice>> listAudioOutputs() async => const [
    AudioEndpointDevice(id: 'default', label: 'System Default'),
    AudioEndpointDevice(id: '1', label: 'CABLE Input (VB-Audio)', isVirtualCable: true),
  ];
}

class _FakeMobilePlatform extends PlatformDetectionService {
  @override bool get canHostServer => false;
  @override bool get isDesktop => false;
  @override bool get supportsQrScanner => false;
  @override Future<String> resolveDeviceName() async => 'Pixel 9 Pro';
}

Future<void> _waitForTally(ObsWebSocketService obs, TallyState target) async {
  if (obs.currentState.tallyState == target) return;
  await obs.stateStream
      .firstWhere((s) => s.tallyState == target)
      .timeout(const Duration(seconds: 3));
}

void main() {
  test('sha256Hex NIST vectors, OBS v5 auth vector, and LiveTallyMessage', () {
    expect(sha256Hex(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
      computeObsWebSocketAuth(password: 'supersecretpassword', salt: 'somesalt', challenge: 'somechallenge'),
      'ffzHOjVUrJvgdsE0p1Whg7xevzrqw7JNvejosFenyZA=',
    );
    const msg = LiveTallyMessage(state: .preview, sceneName: 'Scene 1');
    expect(LiveTallyMessage.tryFromJson(msg.toJson()), msg);
    expect(LiveTallyMessage.tryFromJson({'kind': 'tally', 'state': 'invalid'}), isNull);
  });

  test('ObsWebSocketService authenticates, toggles virtual cam, provisions Clean Feed, syncs delay & tally', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      const challenge = 'chal-123';
      const salt = 'salt-456';
      const password = 'obs-pass';
      final expectedAuth = computeObsWebSocketAuth(password: password, salt: salt, challenge: challenge);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peerWs;
      final reqTypes = <String>[];
      String? identifiedAuth;
      int? syncOffsetNs;
      String? createdInputKind;
      var virtualCam = false;
      var programScene = 'Scene 1';
      var previewScene = 'Scene 2';
      final inputs = <Map<String, dynamic>>[];
      final sceneItems = <String, List<Map<String, dynamic>>>{
        'Scene 1': [{'sourceName': 'Phone2Screen Clean Feed', 'sceneItemEnabled': true}],
        'Scene 2': [{'sourceName': 'Phone2Screen Clean Feed', 'sceneItemEnabled': true}],
        'Scene 3': [{'sourceName': 'Game Capture', 'sceneItemEnabled': true}],
      };

      final serverSub = server.listen((httpReq) async {
        final ws = await WebSocketTransformer.upgrade(httpReq);
        peerWs = ws;
        ws.add(jsonEncode({
          'op': 0,
          'd': {'obsWebSocketVersion': '5.4.2', 'rpcVersion': 1, 'authentication': {'challenge': challenge, 'salt': salt}},
        }));
        ws.listen((raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          final d = frame['d'] as Map<String, dynamic>;
          if (frame['op'] == 1) {
            identifiedAuth = d['authentication'] as String?;
            ws.add(jsonEncode({'op': 2, 'd': {'negotiatedRpcVersion': 1}}));
            return;
          }
          if (frame['op'] != 6) return;
          final type = d['requestType'] as String;
          final id = d['requestId'] as String;
          final rd = (d['requestData'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          reqTypes.add(type);
          Map<String, dynamic> body = const {};
          switch (type) {
            case 'GetVersion': body = {'obsVersion': '30.2.0'};
            case 'GetVirtualCamStatus': body = {'outputActive': virtualCam};
            case 'GetStudioModeEnabled': body = {'studioModeEnabled': true};
            case 'GetSceneList': body = {'currentProgramSceneName': programScene, 'currentPreviewSceneName': previewScene};
            case 'GetSceneItemList': body = {'sceneItems': sceneItems[rd['sceneName']] ?? const []};
            case 'ToggleVirtualCam':
              virtualCam = !virtualCam;
              body = {'outputActive': virtualCam};
            case 'GetInputList': body = {'inputs': inputs};
            case 'CreateInput':
              createdInputKind = rd['inputKind'] as String?;
              inputs.add({'inputName': rd['inputName']});
            case 'SetInputAudioSyncOffset': syncOffsetNs = rd['inputAudioSyncOffset'] as int?;
          }
          ws.add(jsonEncode({
            'op': 7,
            'd': {'requestType': type, 'requestId': id, 'requestStatus': {'result': true, 'code': 100}, 'responseData': body},
          }));
        });
      });

      final obs = ObsWebSocketService();
      addTearDown(() async {
        await obs.dispose();
        await peerWs?.close();
        await serverSub.cancel();
        await server.close(force: true);
      });

      final ok = await obs.connect(ObsConnectionConfig(host: '127.0.0.1', port: server.port, password: password));
      expect(ok, isTrue);
      expect(identifiedAuth, expectedAuth);
      await _waitForTally(obs, .program);
      expect(obs.currentState.obsVersion, '30.2.0');

      programScene = 'Scene 3';
      peerWs!.add(jsonEncode({'op': 5, 'd': {'eventType': 'CurrentProgramSceneChanged', 'eventData': {'sceneName': 'Scene 3'}}}));
      await _waitForTally(obs, .preview);

      previewScene = 'Scene 3';
      peerWs!.add(jsonEncode({'op': 5, 'd': {'eventType': 'CurrentPreviewSceneChanged', 'eventData': {'sceneName': 'Scene 3'}}}));
      await _waitForTally(obs, .standby);

      expect(await obs.toggleVirtualCam(), isTrue);
      expect(obs.currentState.virtualCamActive, isTrue);
      expect(await obs.ensureBrowserSource(cleanFeedUrl: 'http://127.0.0.1:8080/obs', audioDelayMs: 120), isTrue);
      expect(createdInputKind, 'browser_source');
      expect(syncOffsetNs, 120_000_000);
      expect(await obs.setAudioSyncOffset(delayMs: 120), isTrue);
      expect(syncOffsetNs, 120_000_000);
      expect(reqTypes, containsAll([
        'GetVersion', 'GetVirtualCamStatus', 'GetStudioModeEnabled', 'GetSceneList',
        'GetSceneItemList', 'ToggleVirtualCam', 'GetInputList', 'CreateInput', 'SetInputAudioSyncOffset',
      ]));
    }, _RealHttpOverrides());
  });

  testWidgets('StudioLookPreset matrix composition & VideoStageWidget radial vignette', (tester) async {
    const nat = ViewerDisplayConfig();
    const punch = ViewerDisplayConfig(lookPreset: .streamPunch);
    const noir = ViewerDisplayConfig(lookPreset: .noirBw, brightness: 0.1, contrast: 1.2);
    const vig = ViewerDisplayConfig(vignette: true);
    expect(nat.hasColorAdjustments, isFalse);
    expect(punch.hasColorAdjustments, isTrue);
    expect(punch.colorMatrix, StudioLookPreset.streamPunch.matrix);
    expect(punch.colorMatrix, isNot(equals(nat.colorMatrix)));
    expect(noir.colorMatrix, isNot(equals(StudioLookPreset.noirBw.matrix)));
    expect(noir.colorMatrix[0], closeTo(noir.colorMatrix[5], 1e-6));
    expect(noir.colorMatrix[1], closeTo(noir.colorMatrix[6], 1e-6));
    expect(vig.hasColorAdjustments, isTrue);

    const ch = MethodChannel('FlutterWebRTC.Method');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
    messenger.setMockMethodCallHandler(ch, (c) async => c.method == 'createVideoRenderer' ? {'textureId': 1} : null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 320, height: 180, child: VideoStageWidget(stream: _FakeMediaStream(), displayConfig: vig))),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient is RadialGradient),
      findsOneWidget,
    );
  });

  testWidgets('SenderScreen/OledTallyView live tally pills & NearbyDevicesList USB wired peer', (tester) async {
    Future<void> pumpSender(LiveTallyMessage tally, {bool ecoDim = false}) => tester.pumpWidget(ProviderScope(
      key: ValueKey('${tally.state.name}-$ecoDim'),
      overrides: [
        platformServiceProvider.overrideWithValue(_FakeMobilePlatform()),
        appSettingsProvider.overrideWith(() => _StaticSettingsNotifier(AppSettings(ecoDimPreview: ecoDim))),
        sessionProvider.overrideWith(() => _StaticSessionNotifier(SessionState(phase: .streaming, connectedPeerName: 'Studio PC', liveTally: tally))),
      ],
      child: const MaterialApp(home: Scaffold(body: SenderScreen())),
    ));

    await pumpSender(const LiveTallyMessage(state: .preview, sceneName: 'Scene 1'), ecoDim: true);
    await tester.pump();
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('OBS • Scene 1'), findsOneWidget);
    expect(find.text('Preview • Studio PC'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.accentGreen), findsOneWidget);

    await pumpSender(const LiveTallyMessage(state: .standby, sceneName: 'Scene 1'), ecoDim: true);
    await tester.pump();
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.text('Standby • Studio PC'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.cyanAccent), findsOneWidget);

    await pumpSender(const LiveTallyMessage(state: .program, sceneName: 'Scene 1'), ecoDim: true);
    await tester.pump();
    expect(find.text('ON AIR'), findsOneWidget);
    expect(find.text('ON AIR • Studio PC'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.accentRed), findsOneWidget);

    final usbPeer = DiscoveredPeer(endpoint: const SignalingData(ip: '127.0.0.1', port: 8080, sessionId: 'usb1', deviceName: 'OBS Studio PC'), lastSeen: DateTime.utc(2026), isUsbLoopback: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        usbLoopbackPeersProvider.overrideWith(() => _StaticUsbPeersNotifier([usbPeer])),
        discoveredPeersProvider.overrideWith((_) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: Scaffold(body: NearbyDevicesList())),
    ));
    await tester.pump();
    expect(find.text('OBS Studio PC'), findsOneWidget);
    expect(find.textContaining('USB Wired • Zero-Latency'), findsOneWidget);
    expect(find.byIcon(Icons.usb_rounded), findsAtLeastNWidgets(1));
  });

  testWidgets('ObsVirtualCamSheet & RemoteCameraPanel StudioLookAudioSection at 1200x800 and 390x844', (tester) async {
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });

    Future<void> pumpLauncher(Size size, Widget child) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(ProviderScope(
        key: ValueKey('${size.width}-${child.runtimeType}'),
        overrides: [
          windowsStudioServiceProvider.overrideWithValue(_FakeWinStudio()),
          audioRoutingServiceProvider.overrideWithValue(_FakeAudioRouting()),
          sessionProvider.overrideWith(() => _StaticSessionNotifier(const SessionState(phase: .streaming, connectedPeerName: 'Pixel 9'))),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ));
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(1200, 800), Size(390, 844)]) {
      final compact = size.width < 640;
      await pumpLauncher(size, Builder(builder: (c) => FilledButton(onPressed: () => ObsVirtualCamSheet.show(c), child: const Text('Open OBS'))));
      await tester.tap(find.text('Open OBS'));
      await tester.pumpAndSettle();
      expect(find.text('Virtual Cam & OBS'), findsOneWidget);
      expect(find.byType(BottomSheet), compact ? findsOneWidget : findsNothing);
      if (!compact) {
        expect(tester.widget<Align>(find.ancestor(of: find.byType(ObsVirtualCamSheet), matching: find.byType(Align)).first).alignment, Alignment.centerRight);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await pumpLauncher(size, Builder(builder: (c) => FilledButton(onPressed: () => RemoteCameraPanel.show(c), child: const Text('Open Rig'))));
      await tester.tap(find.text('Open Rig'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), compact ? findsOneWidget : findsNothing);
      final scrollable = find.descendant(of: find.byType(RemoteCameraPanel), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Lip-Sync Offset'), 220, scrollable: scrollable);
      expect(find.textContaining('Studio Look Presets'), findsOneWidget);
      expect(find.text('Mic Mode'), findsOneWidget);
      expect(find.text('Audio Boost'), findsOneWidget);
      expect(find.text('Lip-Sync Offset'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
  });
}

class _StaticSettingsNotifier extends AppSettingsNotifier {
  final AppSettings initial;
  _StaticSettingsNotifier(this.initial);
  @override AppSettings build() => initial;
}
