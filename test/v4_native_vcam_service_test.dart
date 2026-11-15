import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/providers/obs_sync_provider.dart';
import 'package:phone2screen/providers/virtual_cam_provider.dart';
import 'package:phone2screen/services/windowing/windows_studio_service.dart';

class _FakeVcamChannel {
  bool registered = false;
  int camState = 0;
  int listCalls = 0;
  final List<int> recordedStates = [];
  Map<Object?, Object?>? lastFrame;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'listVideoCaptureDevices':
        listCalls++;
        return [
          if (registered)
            {
              'name': 'Phone2Screen Camera',
              'devicePath': 'p2s://virtual-camera/0',
              'isVirtualCam': true,
            },
        ];
      case 'getVirtualCamStatus':
        return {
          'registered': registered,
          'dllFound': true,
          'dllPath': r'D:\bin\p2s_vcam.dll',
          'state': camState,
          'deviceName': 'Phone2Screen Camera',
        };
      case 'registerVirtualCam':
        registered = true;
        camState = 0;
        return true;
      case 'unregisterVirtualCam':
        registered = false;
        camState = 0;
        return true;
      case 'setVirtualCamState':
        camState = (call.arguments as Map)['state'] as int;
        recordedStates.add(camState);
        return true;
      case 'pushVirtualCamFrame':
        lastFrame = call.arguments as Map<Object?, Object?>;
        camState = 1;
        return true;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phone2screen/windows_studio');

  group('WindowsStudioService Virtual Camera', () {
    test('detects Phone2Screen Camera and models NativeVirtualCamStatus', () {
      expect(
        VideoCaptureDeviceInfo.detectVirtualCamName('Phone2Screen Camera'),
        isTrue,
      );
      expect(
        VideoCaptureDeviceInfo.detectVirtualCamName('Logitech C920'),
        isFalse,
      );
      const base = NativeVirtualCamStatus(
        isSupported: true,
        isRegistered: true,
        dllFound: true,
        dllPath: r'C:\app\p2s_vcam.dll',
        activeState: 1,
      );
      expect(base.isStreaming, isTrue);
      expect(base.isPaused, isFalse);
      expect(base.copyWith(activeState: 2).isPaused, isTrue);
      expect(base, base.copyWith());
      expect(base.hashCode, base.copyWith().hashCode);
    });

    test('handles virtual cam MethodChannel calls and validation', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final fake = _FakeVcamChannel();
      messenger.setMockMethodCallHandler(channel, fake.handle);

      final service = WindowsStudioService(
        channel: channel,
        isSupportedOverride: true,
      );
      final initial = await service.getVirtualCamStatus();
      expect(initial.isSupported, isTrue);
      expect(initial.isRegistered, isFalse);
      expect(initial.dllFound, isTrue);
      expect(initial.dllPath, r'D:\bin\p2s_vcam.dll');

      expect(await service.registerVirtualCam(), isTrue);
      expect((await service.getVirtualCamStatus()).isRegistered, isTrue);

      expect(await service.setVirtualCamState(99), isTrue);
      expect(fake.camState, 2);
      expect(await service.setVirtualCamState(-4), isTrue);
      expect(fake.camState, 0);

      expect(
        await service.pushVirtualCamFrame(
          rgbaBytes: Uint8List(8),
          width: 4,
          height: 4,
        ),
        isFalse,
      );
      expect(
        await service.pushVirtualCamFrame(
          rgbaBytes: Uint8List(4 * 2 * 4),
          width: 4,
          height: 2,
        ),
        isTrue,
      );
      expect(fake.lastFrame?['width'], 4);
      expect(fake.lastFrame?['height'], 2);

      expect(await service.unregisterVirtualCam(), isTrue);
      expect((await service.getVirtualCamStatus()).isRegistered, isFalse);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'ERR'),
      );
      expect((await service.getVirtualCamStatus()).isRegistered, isFalse);

      final unsupported = WindowsStudioService(
        channel: channel,
        isSupportedOverride: false,
      );
      expect((await unsupported.getVirtualCamStatus()).isSupported, isFalse);
      expect(await unsupported.registerVirtualCam(), isFalse);
    });
  });

  group('NativeVirtualCamNotifier', () {
    test('enable/disable invalidates device list and syncs states', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final fake = _FakeVcamChannel();
      messenger.setMockMethodCallHandler(channel, fake.handle);

      final container = ProviderContainer(
        overrides: [
          windowsStudioServiceProvider.overrideWithValue(
            WindowsStudioService(channel: channel, isSupportedOverride: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(videoCaptureDevicesProvider.future);
      expect(fake.listCalls, 1);

      final notifier = container.read(nativeVirtualCamProvider.notifier);
      expect(await notifier.enable(), isTrue);
      expect(container.read(nativeVirtualCamProvider).isRegistered, isTrue);

      final devices = await container.read(videoCaptureDevicesProvider.future);
      expect(fake.listCalls, 2);
      expect(devices.single.name, 'Phone2Screen Camera');

      await notifier.syncStreamState(isStreaming: true, isPaused: false);
      expect(container.read(nativeVirtualCamProvider).isStreaming, isTrue);
      await notifier.syncStreamState(isStreaming: true, isPaused: true);
      expect(container.read(nativeVirtualCamProvider).isPaused, isTrue);
      await notifier.syncStreamState(isStreaming: false, isPaused: false);
      expect(container.read(nativeVirtualCamProvider).activeState, 0);
      expect(fake.recordedStates, [1, 2, 0]);

      expect(await notifier.disable(), isTrue);
      expect(container.read(nativeVirtualCamProvider).isRegistered, isFalse);
      expect(await container.read(videoCaptureDevicesProvider.future), isEmpty);
    });

    testWidgets('captureStageFrameOnce captures RepaintBoundary RGBA pixels', (
      tester,
    ) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final fake = _FakeVcamChannel()
        ..registered = true
        ..camState = 1;
      messenger.setMockMethodCallHandler(channel, fake.handle);

      late NativeVirtualCamNotifier notifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            windowsStudioServiceProvider.overrideWithValue(
              WindowsStudioService(channel: channel, isSupportedOverride: true),
            ),
          ],
          child: MaterialApp(
            home: Center(
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(nativeVirtualCamProvider);
                  notifier = ref.read(nativeVirtualCamProvider.notifier);
                  return RepaintBoundary(
                    key: notifier.stageBoundaryKey,
                    child: const SizedBox(
                      width: 400,
                      height: 225,
                      child: ColoredBox(color: Color(0xFF1E88E5)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => notifier.refresh());

      expect(await tester.runAsync(notifier.captureStageFrameOnce), isTrue);
      final pushedWidth = fake.lastFrame?['width'] as int;
      final pushedHeight = fake.lastFrame?['height'] as int;
      final pushedBytes = fake.lastFrame?['bytes'] as Uint8List;
      expect(pushedWidth, inInclusiveRange(640, 960));
      expect(pushedHeight, 450);
      expect(pushedBytes.length, pushedWidth * pushedHeight * 4);

      await notifier.syncStreamState(isStreaming: true, isPaused: true);
      expect(await tester.runAsync(notifier.captureStageFrameOnce), isFalse);
    });
  });
}
