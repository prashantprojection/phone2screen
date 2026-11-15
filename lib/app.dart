import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme/app_theme.dart';
import 'providers/platform_provider.dart';
import 'providers/settings_provider.dart';
import 'views/receiver/receiver_screen.dart';
import 'views/sender/sender_screen.dart';
import 'views/settings/settings_screen.dart';
import 'views/shared/app_shell_header.dart';
import 'views/shared/keyboard_shortcuts_scope.dart';

/// Root adaptive Phone2Screen app switching cleanly between Receiver and Sender.
class const Phone2ScreenApp({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final activeRole = ref.watch(activeRoleProvider);
    final viewerDisplay = ref.watch(viewerDisplayProvider);
    final hideHeader = activeRole == .receiver && viewerDisplay.isFullscreen;

    return MaterialApp(
      title: 'Phone2Screen',
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
