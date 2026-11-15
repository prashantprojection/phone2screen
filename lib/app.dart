import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme/app_theme.dart';
import 'providers/platform_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'views/receiver/receiver_screen.dart';
import 'views/sender/sender_screen.dart';
import 'views/settings/settings_screen.dart';
import 'views/shared/app_shell_header.dart';
import 'views/shared/keyboard_shortcuts_scope.dart';

/// Root adaptive Phone2Screen app switching cleanly between Receiver and Sender.
class const Phone2ScreenApp({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<Phone2ScreenApp> createState() => _Phone2ScreenAppState();
}

class _Phone2ScreenAppState extends ConsumerState<Phone2ScreenApp> {
  @override
  void initState() {
    super.initState();
    final launchArgs = ref.read(windowLaunchArgsProvider);
    if (launchArgs.isSecondaryCameraWindow || launchArgs.cleanFeed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeRoleProvider.notifier).setRole(.receiver);
        if (launchArgs.cleanFeed) {
          ref.read(viewerDisplayProvider.notifier).enterCleanFullscreen();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(preferencesAutoSaveProvider);
    final launchArgs = ref.watch(windowLaunchArgsProvider);
    final settings = ref.watch(appSettingsProvider);
    final activeRole = ref.watch(activeRoleProvider);
    final viewerDisplay = ref.watch(viewerDisplayProvider);
    final sessionPhase = ref.watch(sessionProvider.select((s) => s.phase));
    final hideHeader =
        (activeRole == .receiver && viewerDisplay.isFullscreen) ||
        (activeRole == .sender &&
            settings.ecoDimPreview &&
            sessionPhase == .streaming);

    return MaterialApp(
      title: launchArgs.windowTitle ?? 'Phone2Screen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(
        child: child ?? const SizedBox.shrink(),
      ),
      home: KeyboardShortcutsScope(
        child: Builder(
          builder: (navContext) => Scaffold(
            appBar: hideHeader
                ? null
                : AppShellHeader(
                    onOpenSettings: () => Navigator.of(navContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
            body: switch (activeRole) {
              .receiver => const ReceiverScreen(),
              .sender => const SenderScreen(),
            },
          ),
        ),
      ),
    );
  }
}
