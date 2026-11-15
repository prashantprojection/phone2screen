import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/core/theme/app_theme.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/shortcut_config.dart';
import 'package:phone2screen/models/viewer_display_config.dart';
import 'package:phone2screen/providers/obs_sync_provider.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/services/network/network_address_io.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/webrtc/audio_routing_service.dart';
import 'package:phone2screen/services/windowing/windows_studio_service.dart';
import 'package:phone2screen/views/receiver/widgets/creator_stage_fx_section.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_controls_bar.dart';
import 'package:phone2screen/views/receiver/widgets/remote_camera_panel.dart';
import 'package:phone2screen/views/receiver/widgets/simple_webcam_card.dart';
import 'package:phone2screen/views/sender/sender_screen.dart';
import 'package:phone2screen/views/sender/widgets/selfie_ring_light_overlay.dart';
import 'package:phone2screen/views/shared/keyboard_shortcuts_scope.dart';
import 'package:phone2screen/views/shared/video_stage_fx.dart';
import 'package:phone2screen/views/shared/video_stage_widget.dart';

class const _FakePlatform({final bool desktop = true}) extends PlatformDetectionService {
  @override DeviceRole get defaultRole => desktop ? .receiver : .sender;
  @override bool get canHostServer => desktop;
  @override bool get isDesktop => desktop;
  @override bool get isMobile => !desktop;
  @override bool get supportsQrScanner => false;
  @override Future<String> resolveDeviceName() async => desktop ? 'Studio PC' : 'iPhone 16';
}

class _FakeWinStudio extends WindowsStudioService {
  _FakeWinStudio() : super(isSupportedOverride: true);
  @override Future<NativeVirtualCamStatus> getVirtualCamStatus() async =>
      const NativeVirtualCamStatus(isSupported: true, dllFound: true);
}

class _FakeAudioRouting extends AudioRoutingService {
  @override Future<List<AudioEndpointDevice>> listAudioOutputs() async =>
      const [AudioEndpointDevice(id: 'default', label: 'System Default')];
}

class _StaticSessionNotifier extends SessionNotifier {
  final SessionState initial;
  _StaticSessionNotifier(this.initial);
  @override SessionState build() => initial;
  @override Future<void> startDiscovery() async {}
}

class _FakeMediaStream implements MediaStream {
  @override String get id => 'v5-fx-stream';
  @override String get ownerTag => 'remote';
  @override List<MediaStreamTrack> getAudioTracks() => const [];
  @override List<MediaStreamTrack> getVideoTracks() => const [];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _mockWebRtcRenderer(WidgetTester tester) {
  const ch = MethodChannel('FlutterWebRTC.Method');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(ch, (c) async => c.method == 'createVideoRenderer' ? {'textureId': 1} : null);
  addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.binding.setSurfaceSize(size);
}

ProviderContainer _makeContainer({bool desktop = true, SessionState session = const SessionState()}) => ProviderContainer(
  overrides: [
    platformServiceProvider.overrideWithValue(_FakePlatform(desktop: desktop)),
    windowsStudioServiceProvider.overrideWithValue(_FakeWinStudio()),
    audioRoutingServiceProvider.overrideWithValue(_FakeAudioRouting()),
    sessionProvider.overrideWith(() => _StaticSessionNotifier(session)),
  ],
);

Widget _wrapApp(ProviderContainer container, Widget child) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    // ignore: deprecated_member_use
    builder: (context, inner) => MaterialUiCompatibilityBridge(child: inner ?? const SizedBox.shrink()),
    home: Scaffold(body: child),
  ),
);

void main() {
  test('ViewerDisplayConfig & ViewerDisplayNotifier FX, keystone, reset, and equality', () {
    expect(PortraitBokehMode.off.next, PortraitBokehMode.soft);
    expect(PortraitBokehMode.soft.next, PortraitBokehMode.strong);
    expect(PortraitBokehMode.strong.next, PortraitBokehMode.off);
    expect(PortraitBokehMode.values.map((m) => (m.label, m.sigma)).toList(), [
      ('Off', 0.0), ('Soft Bokeh', 7.0), ('Strong Blur', 15.0),
    ]);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(viewerDisplayProvider.notifier);

    notifier.cycleBokehMode();
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.soft);
    notifier.cycleBokehMode();
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.strong);
    notifier.cycleBokehMode();
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.off);

    notifier.setFaceFillLight(-0.4);
    expect(container.read(viewerDisplayProvider).faceFillLight, 0.0);
    notifier.setFaceFillLight(2.4);
    expect(container.read(viewerDisplayProvider).faceFillLight, 1.0);
    notifier.setFaceFillLight(0.65);
    expect(container.read(viewerDisplayProvider).faceFillLight, 0.65);
    expect(container.read(viewerDisplayProvider).hasColorAdjustments, isTrue);

    notifier.toggleDeskCamMode();
    expect(container.read(viewerDisplayProvider).deskCamMode, isTrue);
    notifier.toggleDeskCamMode();
    expect(container.read(viewerDisplayProvider).deskCamMode, isFalse);

    notifier.setKeystoneVertical(-0.9);
    expect(container.read(viewerDisplayProvider).keystoneVertical, -0.35);
    notifier.setKeystoneVertical(0.9);
    expect(container.read(viewerDisplayProvider).keystoneVertical, 0.35);
    notifier.setKeystoneHorizontal(-0.9);
    expect(container.read(viewerDisplayProvider).keystoneHorizontal, -0.35);
    notifier.setKeystoneHorizontal(0.9);
    expect(container.read(viewerDisplayProvider).keystoneHorizontal, 0.35);
    expect(container.read(viewerDisplayProvider).hasFramingAdjustments, isTrue);

    notifier..toggleMute()..setBokehMode(.soft)..setDeskCamMode(true)..setDigitalZoom(1.8)..resetFramingAndColor();
    final reset = container.read(viewerDisplayProvider);
    expect(reset.bokehMode, PortraitBokehMode.off);
    expect(reset.faceFillLight, 0.0);
    expect(reset.deskCamMode, isFalse);
    expect(reset.keystoneVertical, 0.0);
    expect(reset.keystoneHorizontal, 0.0);
    expect(reset.digitalZoom, 1.0);
    expect(reset.hasColorAdjustments, isFalse);
    expect(reset.hasFramingAdjustments, isFalse);
    expect(reset.audioMuted, isTrue);

    const base = ViewerDisplayConfig();
    expect(base == const ViewerDisplayConfig(), isTrue);
    expect(base.hashCode, const ViewerDisplayConfig().hashCode);
    final mutated = <ViewerDisplayConfig>[
      base.copyWith(coverFit: true), base.copyWith(mirrored: true), base.copyWith(quarterTurns: 1),
      base.copyWith(audioMuted: true), base.copyWith(isFullscreen: true), base.copyWith(fullscreenHudVisible: false),
      base.copyWith(showTelemetry: true), base.copyWith(showGrid: true), base.copyWith(aspectPreset: .widescreen16x9),
      base.copyWith(digitalZoom: 1.5), base.copyWith(panX: 0.2), base.copyWith(panY: -0.2),
      base.copyWith(brightness: 0.1), base.copyWith(contrast: 1.2), base.copyWith(saturation: 1.3),
      base.copyWith(lookPreset: .streamPunch), base.copyWith(vignette: true), base.copyWith(audioGain: 1.4),
      base.copyWith(audioDelayMs: 120), base.copyWith(isVideoPaused: true), base.copyWith(bokehMode: .soft),
      base.copyWith(faceFillLight: 0.5), base.copyWith(deskCamMode: true),
      base.copyWith(keystoneVertical: 0.2), base.copyWith(keystoneHorizontal: -0.15),
    ];
    for (final item in mutated) {
      expect(item == base, isFalse);
      expect(item.hashCode, isNot(equals(base.hashCode)));
    }
  });

  testWidgets('ShortcutAction.cycleBackgroundBlur defaults to B and dispatches on active receiver', (tester) async {
    final binding = defaultShortcutBindings[ShortcutAction.cycleBackgroundBlur]!;
    expect(binding.keyId, 0x00000062);
    expect(binding.displayLabel, 'B');
    const bEvent = KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyB, logicalKey: LogicalKeyboardKey.keyB, timeStamp: .zero);
    expect(const ShortcutConfig().matchEvent(bEvent, ctrl: false, shift: false, alt: false), ShortcutAction.cycleBackgroundBlur);

    final container = _makeContainer(session: const SessionState(phase: .streaming));
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrapApp(container, const KeyboardShortcutsScope(child: SizedBox())));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.soft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.strong);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.off);
  });

  testWidgets('VideoStageWidget renders FX & desk keystone and handles stream null fallback', (tester) async {
    _mockWebRtcRenderer(tester);
    const fx = ViewerDisplayConfig(bokehMode: .soft, faceFillLight: 0.65, deskCamMode: true, keystoneVertical: 0.2, keystoneHorizontal: -0.15);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VideoStageWidget(stream: null, displayConfig: fx))));
    await tester.pump();
    expect(find.text('Waiting for video stream...'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoStageWidget(stream: _FakeMediaStream(), displayConfig: fx))));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(FaceFillLightOverlay), findsOneWidget);
    expect(find.byType(Transform), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoStageWidget(stream: _FakeMediaStream(), displayConfig: fx.copyWith(bokehMode: .strong)))));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CreatorStageFxSection inside RemoteCameraPanel updates bokehMode & deskCamMode', (tester) async {
    await _setSize(tester, const Size(1200, 800));
    addTearDown(() async { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); await tester.binding.setSurfaceSize(null); });
    final container = _makeContainer(session: const SessionState(phase: .streaming, connectedPeerName: 'Pixel 9'));
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrapApp(container, const RemoteCameraPanel()));
    await tester.pumpAndSettle();
    expect(find.byType(CreatorStageFxSection), findsOneWidget);

    final scroll = find.descendant(of: find.byType(RemoteCameraPanel), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Soft Bokeh'), 220, scrollable: scroll);
    await tester.tap(find.text('Soft Bokeh'));
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.soft);

    await tester.scrollUntilVisible(find.text('Desk Cam 180°'), 220, scrollable: scroll);
    await tester.tap(find.text('Desk Cam 180°'));
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).deskCamMode, isTrue);
    expect(find.text('Reset Keystone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SimpleWebcamCard Blur chip & ReceiverControlsBar Blur dock cycle at 390x844 and 1200x800', (tester) async {
    addTearDown(() async { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); await tester.binding.setSurfaceSize(null); });
    for (final size in const [Size(390, 844), Size(1200, 800)]) {
      await _setSize(tester, size);
      final cardContainer = _makeContainer();
      addTearDown(cardContainer.dispose);
      await tester.pumpWidget(_wrapApp(cardContainer, const SimpleWebcamCard()));
      await tester.pumpAndSettle();
      expect(find.text('Blur: Off'), findsOneWidget);
      await tester.tap(find.text('Blur: Off'));
      await tester.pumpAndSettle();
      expect(find.text('Blur: Soft Bokeh'), findsOneWidget);
      expect(cardContainer.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.soft);
      expect(tester.takeException(), isNull);

      final barContainer = _makeContainer(session: const SessionState(phase: .streaming));
      addTearDown(barContainer.dispose);
      await tester.pumpWidget(_wrapApp(barContainer, const Align(alignment: Alignment.bottomCenter, child: ReceiverControlsBar())));
      await tester.pumpAndSettle();
      await tester.tap(size.width < 640 ? find.byIcon(Icons.blur_on_rounded) : find.text('Blur'));
      await tester.pumpAndSettle();
      expect(barContainer.read(viewerDisplayProvider).bokehMode, PortraitBokehMode.soft);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('SelfieRingLightOverlay & RingLightPill cycle off -> warm -> daylight -> off', (tester) async {
    _mockWebRtcRenderer(tester);
    await _setSize(tester, const Size(390, 844));
    addTearDown(() async { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); await tester.binding.setSurfaceSize(null); });

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SelfieRingLightOverlay(mode: .off))));
    expect(find.descendant(of: find.byType(SelfieRingLightOverlay), matching: find.byType(SizedBox)), findsOneWidget);
    expect(find.descendant(of: find.byType(SelfieRingLightOverlay), matching: find.byType(IgnorePointer)), findsNothing);

    final container = _makeContainer(desktop: false, session: const SessionState(phase: .streaming, connectedPeerName: 'Studio PC'));
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrapApp(container, const SenderScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(RingLightPill), findsOneWidget);
    expect(find.text('Ring Light'), findsOneWidget);
    expect(find.byType(SelfieRingLightOverlay), findsNothing);

    await tester.tap(find.byType(RingLightPill));
    await tester.pumpAndSettle();
    expect(find.text('Warm Ring'), findsOneWidget);
    expect(tester.widget<SelfieRingLightOverlay>(find.byType(SelfieRingLightOverlay)).mode, SelfieRingLightMode.warm);
    expect(find.descendant(of: find.byType(SelfieRingLightOverlay), matching: find.byType(DecoratedBox)), findsNWidgets(2));

    await tester.tap(find.byType(RingLightPill));
    await tester.pumpAndSettle();
    expect(find.text('Daylight'), findsOneWidget);
    expect(tester.widget<SelfieRingLightOverlay>(find.byType(SelfieRingLightOverlay)).mode, SelfieRingLightMode.daylight);
    expect(find.descendant(of: find.byType(SelfieRingLightOverlay), matching: find.byType(DecoratedBox)), findsNWidgets(2));

    await tester.tap(find.byType(RingLightPill));
    await tester.pumpAndSettle();
    expect(find.text('Ring Light'), findsOneWidget);
    expect(find.byType(SelfieRingLightOverlay), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('iPhone USB Personal Hotspot ranks above Wi-Fi in network_address_io', () {
    expect(isUsbTetherInterface('Ethernet 4', '172.20.10.2'), isTrue);
    expect(isUsbTetherInterface('Apple Mobile Device Ethernet', '172.20.10.3'), isTrue);
    final iphoneScore = scoreNetworkInterface(name: 'Ethernet 4', address: '172.20.10.2', wifiIp: '192.168.1.24');
    final appleNicScore = scoreNetworkInterface(name: 'Apple Mobile Device Ethernet', address: '172.20.10.3', wifiIp: '192.168.1.24');
    final wifiScore = scoreNetworkInterface(name: 'Wi-Fi', address: '192.168.1.24', wifiIp: '192.168.1.24');
    expect(iphoneScore, greaterThan(wifiScore));
    expect(appleNicScore, greaterThan(wifiScore));
  });
}
