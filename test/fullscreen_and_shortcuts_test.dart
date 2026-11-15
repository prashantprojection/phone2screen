import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phone2screen/models/device_role.dart';
import 'package:phone2screen/models/shortcut_config.dart';
import 'package:phone2screen/providers/platform_provider.dart';
import 'package:phone2screen/providers/session_provider.dart';
import 'package:phone2screen/providers/settings_provider.dart';
import 'package:phone2screen/providers/shortcut_provider.dart';
import 'package:phone2screen/services/platform_detection_service.dart';
import 'package:phone2screen/views/receiver/widgets/receiver_streaming_stage.dart';
import 'package:phone2screen/views/settings/settings_screen.dart';
import 'package:phone2screen/views/shared/keyboard_shortcuts_scope.dart';
import 'package:phone2screen/views/shared/video_stage_widget.dart';

class const _FakeDesktopPlatform() extends PlatformDetectionService {
  @override
  DeviceRole get defaultRole => .receiver;
  @override
  bool get canHostServer => true;
  @override
  bool get supportsQrScanner => false;
  @override
  bool get supportsDesktopPicker => true;
  @override
  Future<String> resolveDeviceName() async => 'Test Desktop';
}

void main() {
  group('ShortcutConfig & ShortcutNotifier', () {
    test('exposes expected default bindings for all actions', () {
      const expected = <ShortcutAction, String>{
        .toggleFullscreen: 'F',
        .toggleFullscreenHud: 'O',
        .toggleMute: 'M',
        .rotateVideo: 'R',
        .toggleMirror: 'H',
        .toggleFit: 'Z',
        .toggleStats: 'S',
        .openClipboard: 'C',
        .openGuide: 'G',
        .toggleCleanFeed: 'B',
        .openCameraRig: 'V',
        .disconnectStream: 'X',
      };

      expect(defaultShortcutBindings.length, ShortcutAction.values.length);
      for (final entry in expected.entries) {
        expect(defaultShortcutBindings[entry.key]?.displayLabel, entry.value);
      }
    });

    test('updateBinding swaps conflicting action with zero duplicates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(shortcutProvider.notifier);
      notifier.updateBinding(
        .toggleFullscreen,
        ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId, keyLabel: 'M'),
      );

      final config = container.read(shortcutProvider);
      expect(config.bindingFor(.toggleFullscreen).displayLabel, 'M');
      expect(config.bindingFor(.toggleMute).displayLabel, 'F');

      final uniqueBindings = ShortcutAction.values
          .map(config.bindingFor)
          .toSet();
      expect(uniqueBindings.length, ShortcutAction.values.length);
    });

    test('setEnabled(false) disables matching/tooltips and resetDefaults restores', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(shortcutProvider.notifier);
      notifier.updateBinding(
        .toggleFullscreen,
        ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId, keyLabel: 'M'),
      );
      notifier.setEnabled(false);

      const mEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyM,
        logicalKey: LogicalKeyboardKey.keyM,
        timeStamp: .zero,
      );
      const fEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        timeStamp: .zero,
      );

      final disabled = container.read(shortcutProvider);
      expect(disabled.enabled, isFalse);
      expect(
        disabled.matchEvent(mEvent, ctrl: false, shift: false, alt: false),
        isNull,
      );
      expect(
        disabled.matchEvent(fEvent, ctrl: false, shift: false, alt: false),
        isNull,
      );
      expect(
        disabled.tooltipFor('Fullscreen', .toggleFullscreen),
        'Fullscreen',
      );

      notifier.resetDefaults();
      final restored = container.read(shortcutProvider);
      expect(restored.enabled, isTrue);
      expect(restored.bindingFor(.toggleFullscreen).displayLabel, 'F');
      expect(restored.bindingFor(.toggleMute).displayLabel, 'M');
      expect(
        restored.tooltipFor('Fullscreen', .toggleFullscreen),
        'Fullscreen (F)',
      );
      expect(
        restored.matchEvent(fEvent, ctrl: false, shift: false, alt: false),
        ShortcutAction.toggleFullscreen,
      );
    });
  });

  testWidgets('fullscreen HUD toggles, Esc toast auto-hides, and Esc exits fullscreen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(const _FakeDesktopPlatform()),
      ],
    );
    addTearDown(container.dispose);
    container.read(viewerDisplayProvider.notifier).setFullscreen(true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: KeyboardShortcutsScope(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ReceiverStreamingStage(
                  session: const SessionState(phase: .streaming),
                  display: ref.watch(viewerDisplayProvider),
                  onExitFullscreen: () => ref
                      .read(viewerDisplayProvider.notifier)
                      .setFullscreen(false),
                  onDismissError: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Press Esc to exit fullscreen'), findsOneWidget);
    expect(find.text('Exit Fullscreen'), findsOneWidget);
    expect(find.text('Hide Controls'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Press Esc to exit fullscreen'), findsNothing);

    await tester.tap(find.text('Hide Controls'));
    await tester.pumpAndSettle();
    expect(find.text('Exit Fullscreen'), findsNothing);
    expect(container.read(viewerDisplayProvider).fullscreenHudVisible, isFalse);

    await tester.tap(find.byType(VideoStageWidget));
    await tester.pumpAndSettle();
    expect(find.text('Exit Fullscreen'), findsOneWidget);
    expect(container.read(viewerDisplayProvider).fullscreenHudVisible, isTrue);

    await tester.tap(find.text('Hide Controls'));
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).fullscreenHudVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(viewerDisplayProvider).isFullscreen, isFalse);
  });

  testWidgets('Settings screen allows customizing a keyboard shortcut binding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Keyboard Shortcuts'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Fullscreen'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final keycapButton = find.descendant(
      of: find.ancestor(
        of: find.text('Fullscreen'),
        matching: find.byType(Row),
      ).first,
      matching: find.byType(OutlinedButton),
    );
    expect(
      find.descendant(of: keycapButton, matching: find.text('F')),
      findsOneWidget,
    );

    await tester.tap(keycapButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Press any key or shortcut combo'),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'K'), findsOneWidget);
    expect(
      container
          .read(shortcutProvider)
          .bindingFor(.toggleFullscreen)
          .displayLabel,
      'K',
    );
  });
}
