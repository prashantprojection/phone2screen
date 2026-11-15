import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'models/shortcut_config.dart';
import 'models/stream_config.dart';
import 'models/window_launch_args.dart';
import 'providers/preferences_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/shortcut_provider.dart';
import 'services/storage/local_preferences_service.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchArgs = WindowLaunchArgs.parse(args);
  late final LocalPreferencesService prefs;
  try {
    prefs = await LocalPreferencesService.loadDefault();
  } catch (_) {
    prefs = LocalPreferencesService.inMemory();
  }

  runApp(
    ProviderScope(
      overrides: [
        windowLaunchArgsProvider.overrideWithValue(launchArgs),
        localPreferencesServiceProvider.overrideWithValue(prefs),
        appSettingsProvider.overrideWith(
          () => _HydratedAppSettingsNotifier(prefs.snapshot.appSettings),
        ),
        streamConfigProvider.overrideWith(
          () => _HydratedStreamConfigNotifier(prefs.snapshot.streamConfig),
        ),
        shortcutProvider.overrideWith(
          () => _HydratedShortcutNotifier(prefs.snapshot.shortcutConfig),
        ),
      ],
      child: const Phone2ScreenApp(),
    ),
  );
}

class _HydratedAppSettingsNotifier extends AppSettingsNotifier {
  final AppSettings _initial;
  _HydratedAppSettingsNotifier(this._initial);

  @override
  AppSettings build() => _initial;
}

class _HydratedStreamConfigNotifier extends StreamConfigNotifier {
  final StreamConfig _initial;
  _HydratedStreamConfigNotifier(this._initial);

  @override
  StreamConfig build() => _initial;
}

class _HydratedShortcutNotifier extends ShortcutNotifier {
  final ShortcutConfig _initial;
  _HydratedShortcutNotifier(this._initial);

  @override
  ShortcutConfig build() => _initial;
}
