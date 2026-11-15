import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/stream_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/stream_config.dart';
import '../../providers/settings_provider.dart';
import '../shared/how_to_use_sheet.dart';

/// Application settings screen for theme, video & audio, security, and help.
class const SettingsScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final config = ref.watch(streamConfigProvider);
    final configNotifier = ref.read(streamConfigProvider.notifier);
    final theme = Theme.of(context);
    final sliderValue = config.videoBitrate.toDouble().clamp(
      StreamConstants.minVideoBitrate.toDouble(),
      StreamConstants.maxVideoBitrate.toDouble(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.isExpanded ? 840 : context.contentMaxWidth,
          ),
          child: ListView(
            padding: const .all(16),
            children: [
              _sectionHeader(theme, Icons.palette_outlined, 'Appearance'),
              Card(
                child: Padding(
                  padding: const .all(16),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 10,
                    children: [
                      Text('Theme Mode', style: theme.textTheme.bodyLarge),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: .dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                          ButtonSegment(value: .light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                          ButtonSegment(value: .system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) => settingsNotifier.setThemeMode(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader(theme, Icons.high_quality_rounded, 'Video & Audio'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Resolution'),
                      subtitle: Text(config.resolution.label),
                      trailing: DropdownButton<StreamResolution>(
                        value: config.resolution,
                        underline: const SizedBox.shrink(),
                        onChanged: (value) {
                          if (value == null) return;
                          configNotifier.setResolution(value);
                          configNotifier.setBitrate(value.recommendedBitrate);
                        },
                        items: const [
                          DropdownMenuItem(value: .p720, child: Text('720p HD')),
                          DropdownMenuItem(value: .p1080, child: Text('1080p FHD')),
                          DropdownMenuItem(value: .p4k, child: Text('4K UHD')),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Smooth 60 FPS'),
                      subtitle: const Text('Smoother motion (uses 30 FPS when turned off)'),
                      value: config.frameRate == 60,
                      onChanged: (enabled) => configNotifier.setFrameRate(enabled ? 60 : 30),
                    ),
                    SwitchListTile(
                      title: const Text('Capture Microphone Audio'),
                      value: config.enableAudio,
                      onChanged: configNotifier.setEnableAudio,
                    ),
                    SwitchListTile(
                      title: const Text('Battery Saver Preview'),
                      subtitle: const Text('Pause preview on sender screen while streaming to save battery'),
                      value: settings.ecoDimPreview,
                      onChanged: settingsNotifier.setEcoDimPreview,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: .antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: false,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primaryLight),
                  title: const Text('Advanced & Security'),
                  subtitle: const Text('4-digit PIN, shared text, bitrate & port'),
                  children: [
                    ListTile(
                      title: const Text('4-Digit Pairing PIN'),
                      subtitle: Text(settings.pin.isEmpty ? 'Off (open Wi-Fi pairing)' : 'Enabled (4-digit PIN)'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editPin(context, settings.pin, settingsNotifier),
                    ),
                    SwitchListTile(
                      title: const Text('Auto-Copy Shared Text'),
                      subtitle: const Text('Copy text received from connected screen automatically'),
                      value: settings.autoCopyClipboard,
                      onChanged: settingsNotifier.setAutoCopyClipboard,
                    ),
                    Padding(
                      padding: const .fromLTRB(16, 8, 16, 4),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            'Target Bitrate: ${(sliderValue / 1_000_000).toStringAsFixed(1)} Mbps',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Slider(
                            value: sliderValue,
                            min: StreamConstants.minVideoBitrate.toDouble(),
                            max: StreamConstants.maxVideoBitrate.toDouble(),
                            divisions: 29,
                            onChanged: (v) => configNotifier.setBitrate(v.round()),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      title: const Text('Network Port'),
                      subtitle: Text('Local port (${settings.preferredPort})'),
                      trailing: DropdownButton<int>(
                        value: settings.preferredPort.clamp(
                          StreamConstants.defaultSignalingPort,
                          StreamConstants.maxSignalingPort,
                        ),
                        underline: const SizedBox.shrink(),
                        onChanged: (port) {
                          if (port != null) settingsNotifier.setPreferredPort(port);
                        },
                        items: [
                          for (var p = StreamConstants.defaultSignalingPort; p <= StreamConstants.maxSignalingPort; p++)
                            DropdownMenuItem(value: p, child: Text('$p')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader(theme, Icons.help_outline_rounded, 'Help & About'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.menu_book_rounded, color: AppColors.primaryLight),
                      title: const Text('How to Use Phone2Screen'),
                      subtitle: const Text('Quick 3-step guide for Phone, PC & Browser'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => HowToUseSheet.show(context),
                    ),
                    const ListTile(
                      title: Text('Phone2Screen'),
                      subtitle: Text('Version 0.1.0 • Private Local Wi-Fi Casting'),
                    ),
                    ListTile(
                      title: const Text('Open-Source Licenses'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Phone2Screen',
                        applicationVersion: '0.1.0',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, IconData icon, String title) {
    return Padding(
      padding: const .only(left: 4, bottom: 8),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryLight),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
        ],
      ),
    );
  }

  Future<void> _editPin(BuildContext context, String currentPin, AppSettingsNotifier notifier) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _PinConfigDialog(initialPin: currentPin),
    );
    if (updated != null) notifier.setPin(updated);
  }
}

class const _PinConfigDialog({required final String initialPin})
    extends StatefulWidget {
  @override
  State<_PinConfigDialog> createState() => _PinConfigDialogState();
}

class _PinConfigDialogState extends State<_PinConfigDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialPin);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _controller.text.trim();
    if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'Enter 4 digits or leave empty to disable');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receiver Pairing PIN'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 4,
        keyboardType: .number,
        decoration: InputDecoration(
          labelText: '4-Digit PIN',
          hintText: 'Leave empty to disable',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Disable')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
