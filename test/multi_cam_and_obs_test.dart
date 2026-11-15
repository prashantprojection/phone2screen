import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/models/camera_control_state.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/signaling_data.dart';
import 'package:phone2screen/models/stream_config.dart';
import 'package:phone2screen/models/stream_telemetry.dart';
import 'package:phone2screen/models/viewer_display_config.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/services/signaling/signaling_server_service.dart';
import 'package:phone2screen/services/webrtc/data_channel_helper.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_controls_bar.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_streaming_stage.dart';
import 'package:phone2screen/views/receiver/widgets/remote_camera_panel.dart';
import 'package:phone2screen/views/sender/widgets/oled_tally_view.dart';
import 'package:phone2screen/views/sender/widgets/source_picker_card.dart';
import 'package:phone2screen/views/sender/widgets/web_broadcast_card.dart';
import 'package:phone2screen/views/shared/keyboard_shortcuts_scope.dart';
import 'package:phone2screen/views/shared/video_stage_widget.dart';

class _FakeDataChannel implements RTCDataChannel {
  RTCDataChannelState _state = .RTCDataChannelConnecting;
  final List<String> sent = [];
  @override RTCDataChannelState? get state => _state;
  @override void Function(RTCDataChannelState state)? onDataChannelState;
  @override void Function(RTCDataChannelMessage data)? onMessage;
  @override Future<void> send(RTCDataChannelMessage message) async => sent.add(message.text);
  @override Future<void> close() async => _setState(.RTCDataChannelClosed);
  void open() => _setState(.RTCDataChannelOpen);
  void _setState(RTCDataChannelState s) {
    _state = s;
    onDataChannelState?.call(_state);
  }
  void emitJson(Map<String, dynamic> json) =>
      onMessage?.call(RTCDataChannelMessage(jsonEncode(json)));
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class const _FakeDesktopPlatform() extends PlatformDetectionService {
  @override DeviceRole get defaultRole => .receiver;
  @override bool get canHostServer => true;
  @override bool get isDesktop => true;
  @override bool get isWeb => false;
  @override bool get supportsQrScanner => false;
  @override bool get supportsDesktopPicker => true;
  @override Future<String> resolveDeviceName() async => 'Studio PC';
}

class _RecordingSessionNotifier extends SessionNotifier {
  final List<RemoteCameraCommand> sentCommands = [];

  @override
  SessionState build() =>
      const SessionState(phase: .streaming, connectedPeerName: 'Pixel 8');

  @override
  bool sendRemoteCameraCommand(RemoteCameraCommand cmd) {
    sentCommands.add(cmd);
    return true;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  test('serves GET /obs Clean Feed HTML and handles ?pin, ?fit, ?mirror params', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = SignalingServerService();
      final httpClient = HttpClient();
      addTearDown(() async {
        httpClient.close(force: true);
        await server.dispose();
      });

      final port = await server.start(
        preferredPort: 0,
        preferredHttpsPort: null,
        companionMode: .viewSenderStream,
        sessionId: 'obs-1',
        deviceName: 'PhoneCam',
        pin: '4321',
      );

      final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/obs'));
      final resp = await req.close();
      final html = await utf8.decodeStream(resp);
      expect(resp.statusCode, HttpStatus.ok);
      expect(resp.headers.contentType?.mimeType, 'text/html');
      for (final token in const [
        'cursor:none', '<video id="v"', 'preferH264', 'earlyIce', "'pong'", '1500',
        "q.get('pin')", "q.get('fit') === 'cover'", "q.get('mirror') === '1'",
        "q.get('bg') === 'black'", '"requiresPin":true',
      ]) {
        expect(html, contains(token));
      }

      final pReq = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/obs?pin=4321&fit=cover&mirror=1&bg=black'),
      );
      final pResp = await pReq.close();
      await pResp.drain<void>();
      expect(pResp.statusCode, HttpStatus.ok);
      expect(pResp.headers.contentType?.mimeType, 'text/html');
    }, _RealHttpOverrides());
  });

  test('RemoteCameraCommand, RemoteCameraState & DataChannelHelper integration', () async {
    const cmd = RemoteCameraCommand(command: .zoom, value: 2.5, enabled: true);
    expect(RemoteCameraCommand.tryFromJson(cmd.toJson()), cmd);
    expect(RemoteCameraCommand.tryFromJson({'kind': 'ping', 'cmd': 'zoom'}), isNull);
    expect(RemoteCameraCommand.tryFromJson({'kind': 'cam_ctrl', 'cmd': 'iso'}), isNull);
    expect(
      RemoteCameraCommand.tryFromJson(
        {'kind': 'cam_ctrl', 'cmd': 'exposure', 'value': 'NaN', 'enabled': 'bad'},
      ),
      const RemoteCameraCommand(command: .exposure),
    );

    const camState = RemoteCameraState(
      lens: .front, torchOn: true, micMuted: true, zoom: 2.5,
      minZoom: 1.0, maxZoom: 6.0, exposureOffset: -1.5, focusLocked: true,
      controlsSupported: false,
    );
    expect(RemoteCameraState.tryFromJson(camState.toJson()), camState);
    expect(RemoteCameraState.tryFromJson({'kind': 'cam_ctrl'}), isNull);
    final clamped = RemoteCameraState.tryFromJson(
      {'kind': 'cam_state', 'zoom': 99.0, 'minZoom': 0.2, 'maxZoom': 4.0, 'exposureOffset': -9.0},
    );
    expect(clamped?.minZoom, 1.0);
    expect(clamped?.zoom, 4.0);
    expect(clamped?.exposureOffset, -4.0);

    final helper = DataChannelHelper();
    final channel = _FakeDataChannel();
    final opened = <void>[];
    final cmds = <RemoteCameraCommand>[];
    final states = <RemoteCameraState>[];
    final subs = [
      helper.onChannelOpen.listen(opened.add),
      helper.incomingCameraCommands.listen(cmds.add),
      helper.incomingCameraStates.listen(states.add),
    ];
    addTearDown(() => Future.wait([...subs.map((s) => s.cancel()), helper.dispose()]));

    helper.attach(channel);
    expect(helper.isOpen, isFalse);
    channel.open();
    await Future<void>.delayed(Duration.zero);
    expect(helper.isOpen, isTrue);
    expect(opened.length, 1);

    channel.emitJson(cmd.toJson());
    channel.emitJson(camState.toJson());
    await Future<void>.delayed(Duration.zero);
    expect(cmds, [cmd]);
    expect(states, [camState]);
    expect(helper.sendCameraCommand(cmd), isTrue);
    expect(helper.sendCameraState(camState), isTrue);
    expect(channel.sent.length, 2);
  });

  testWidgets('WebBroadcastLobbyView shows /obs Clean Feed & Web Viewer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const ep = SignalingData(ip: '192.168.1.9', port: 8080, sessionId: 'WEB1');
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: WebBroadcastLobbyView(
            session: SessionState(phase: .hosting, activeEndpoint: ep, isWebBroadcast: true),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('OBS Browser Source (Clean Feed)'), findsOneWidget);
    expect(find.text('http://192.168.1.9:8080/obs'), findsOneWidget);
    expect(find.text('Interactive Web Viewer'), findsOneWidget);
  });

  testWidgets('OledTallyView renders pure black ON AIR tally and disposes timers', (tester) async {
    var woken = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OledTallyView(
          targetName: 'Studio PC',
          phase: .streaming,
          telemetry: const StreamTelemetry(connectedDuration: Duration(minutes: 1, seconds: 5)),
          streamConfig: const StreamConfig(),
          onShowPreview: () => woken = true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Material && w.color == Colors.black), findsOneWidget);
    expect(find.text('ON AIR'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    await tester.tap(find.text('Wake Preview'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(woken, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('RigPresetsStrip USB Ultra updates streamConfigProvider to 20 Mbps 60 FPS', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SourcePickerCard())),
      ),
    ));
    await tester.pump();
    final usbChip = find.text('USB Ultra');
    await tester.ensureVisible(usbChip);
    await tester.tap(usbChip);
    await tester.pumpAndSettle();

    final cfg = container.read(streamConfigProvider);
    expect(cfg.videoBitrate, 20_000_000);
    expect(cfg.frameRate, 60);
  });

  testWidgets('Clean View (B / Esc) and RemoteCameraPanel update ViewerDisplayConfig', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sessionNotifier = _RecordingSessionNotifier();
    final container = ProviderContainer(overrides: [
      platformServiceProvider.overrideWithValue(const _FakeDesktopPlatform()),
      sessionProvider.overrideWith(() => sessionNotifier),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: KeyboardShortcutsScope(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ReceiverStreamingStage(
                session: ref.watch(sessionProvider),
                display: ref.watch(viewerDisplayProvider),
                onExitFullscreen: () =>
                    ref.read(viewerDisplayProvider.notifier).setFullscreen(false),
                onDismissError: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ReceiverControlsBar), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).cleanFeedMode, isTrue);
    expect(find.byType(ReceiverControlsBar), findsNothing);
    expect(find.byType(VideoStageWidget), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).cleanFeedMode, isFalse);
    expect(find.byType(ReceiverControlsBar), findsOneWidget);

    await tester.tap(find.text('Camera Rig'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteCameraPanel), findsOneWidget);

    await tester.tap(find.text('16:9'));
    await tester.tap(find.text('3x3 Grid'));
    await tester.tap(find.text('Flip Lens'));
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).aspectPreset, AspectPreset.widescreen16x9);
    expect(container.read(viewerDisplayProvider).showGrid, isTrue);
    expect(sessionNotifier.sentCommands, const [RemoteCameraCommand(command: .flip)]);

    await tester.ensureVisible(find.text('Reset Studio Look'));
    await tester.tap(find.text('Reset Studio Look'));
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).aspectPreset, AspectPreset.free);
  });
}
