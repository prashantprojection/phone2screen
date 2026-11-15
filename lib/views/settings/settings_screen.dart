import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/stream_constants.dart';
import '../../models/stream_config.dart';
import '../../providers/settings_provider.dart';
import '../shared/how_to_use_sheet.dart';
import '../shared/workspace_mode_pill.dart';
import 'widgets/rig_preset_settings_card.dart';
import 'widgets/shortcut_settings_card.dart';

/// Application settings screen for theme, video & audio, presets, shortcuts, and help.
class const SettingsScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final config = ref.watch(streamConfigProvider);
    final configNotifier = ref.read(streamConfigProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = colors.primary;
    final sliderValue = config.videoBitrate.toDouble().clamp(
      StreamConstants.minVideoBitrate.toDouble(),
      StreamConstants.maxVideoBitrate.toDouble(),
    );
    final mbps = (sliderValue / 1_000_000).toStringAsFixed(1);
    final port = settings.preferredPort.clamp(StreamConstants.defaultSignalingPort, StreamConstants.maxSignalingPort);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const .fromLTRB(16, 10, 16, 24),
            children: [
              _sectionHeader(theme, Icons.palette_outlined, 'Appearance'),
              Card(
                child: _dividedColumn([
                  _segmentedRow<ThemeMode>(
                    theme, Icons.palette_outlined, 'Theme', 'Dark, light, or system', settings.themeMode,
                    settingsNotifier.setThemeMode,
                    const [
                      ButtonSegment(value: .dark, label: Text('Dark')),
                      ButtonSegment(value: .light, label: Text('Light')),
                      ButtonSegment(value: .system, label: Text('System')),
                    ],
                  ),
                  _labeledControlRow(
                    theme, Icons.dashboard_customize_outlined, 'Workspace Mode',
                    settings.workspaceMode == .simple
                        ? 'Simple webcam • 1-click PC setup'
                        : 'Studio • multi-cam, OBS & stats',
                    const Row(mainAxisSize: .min, children: [WorkspaceModePill()]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              _sectionHeader(theme, Icons.high_quality_rounded, 'Video & Audio'),
              Card(
                child: _dividedColumn([
                  _segmentedRow<StreamResolution>(
                    theme, Icons.hd_outlined, 'Resolution', config.resolution.label, config.resolution,
                    (v) => configNotifier..setResolution(v)..setBitrate(v.recommendedBitrate),
                    const [
                      ButtonSegment(value: .p720, label: Text('720p')),
                      ButtonSegment(value: .p1080, label: Text('1080p')),
                      ButtonSegment(value: .p4k, label: Text('4K')),
                    ],
                  ),
                  _switchTile(primary, Icons.speed_rounded, 'Smooth 60 FPS',
                      'Smoother motion (30 FPS saves battery)', config.frameRate == 60, (on) => configNotifier.setFrameRate(on ? 60 : 30)),
                  _switchTile(primary, Icons.mic_none_rounded, 'Capture Microphone Audio',
                      'Include voice or room audio when sending', config.enableAudio, configNotifier.setEnableAudio),
                  _switchTile(primary, Icons.battery_saver_rounded, 'Battery Saver Preview',
                      'Pause sender preview while streaming to stay cool', settings.ecoDimPreview, settingsNotifier.setEcoDimPreview),
                ]),
              ),
              const SizedBox(height: 12),
              _sectionHeader(theme, Icons.camera_enhance_outlined, 'Streamer Presets'),
              const RigPresetSettingsCard(),
              const SizedBox(height: 12),
              _sectionHeader(theme, Icons.keyboard_alt_outlined, 'Keyboard Shortcuts'),
              const ShortcutSettingsCard(),
              const SizedBox(height: 12),
              Card(
                clipBehavior: .antiAlias,
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const .symmetric(horizontal: 16, vertical: 4),
                    leading: _iconBadge(primary, Icons.admin_panel_settings_outlined),
                    title: const Text('Advanced & Security'),
                    subtitle: const Text('4-digit PIN, shared text, bitrate & port'),
                    children: [
                      const Divider(height: 1, indent: 62),
                      _dividedColumn([
                        _tile(primary, Icons.pin_outlined, '4-Digit Pairing PIN',
                            subtitle: settings.pin.isEmpty ? 'Off (open Wi-Fi pairing)' : 'Enabled (4-digit PIN)',
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _editPin(context, settings.pin, settingsNotifier)),
                        _switchTile(primary, Icons.content_paste_go_rounded, 'Auto-Copy Shared Text',
                            'Copy text received from connected screen automatically', settings.autoCopyClipboard, settingsNotifier.setAutoCopyClipboard),
                        _bitrateSection(theme, colors, mbps, sliderValue, configNotifier.setBitrate),
                        _portTile(theme, colors, port, settingsNotifier.setPreferredPort),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader(theme, Icons.help_outline_rounded, 'Help & About'),
              Card(
                child: _dividedColumn([
                  _tile(primary, Icons.menu_book_rounded, 'How to Use Phone2Screen',
                      subtitle: 'Quick guide for Phone, OBS Studio & Browser',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => HowToUseSheet.show(context)),
                  _tile(primary, Icons.cast_connected_rounded, 'Phone2Screen',
                      subtitle: 'Version 0.4.0 • Streamer Webcam Studio'),
                  _tile(primary, Icons.description_outlined, 'Open-Source Licenses',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showLicensePage(context: context, applicationName: 'Phone2Screen', applicationVersion: '0.4.0')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dividedColumn(List<Widget> items) =>
      Column(children: [for (var i = 0; i < items.length; i++) ...[if (i > 0) const Divider(height: 1, indent: 62), items[i]]]);

  Widget _iconBadge(Color primary, IconData icon) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(color: primary.withValues(alpha: 0.11), borderRadius: .circular(10)),
    child: Icon(icon, size: 18, color: primary),
  );

  Widget _sectionHeader(ThemeData theme, IconData icon, String title) => Padding(
    padding: const .only(left: 6, bottom: 8),
    child: Row(
      spacing: 8,
      children: [
        Icon(icon, size: 17, color: theme.colorScheme.primary),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: .w700,
            letterSpacing: 0.25,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _tile(Color primary, IconData icon, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) =>
      ListTile(leading: _iconBadge(primary, icon), title: Text(title), subtitle: subtitle != null ? Text(subtitle) : null, trailing: trailing, onTap: onTap);

  Widget _switchTile(Color primary, IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(secondary: _iconBadge(primary, icon), title: Text(title), subtitle: Text(subtitle), value: value, onChanged: onChanged);

  Widget _bitrateSection(ThemeData theme, ColorScheme colors, String mbps, double value, ValueChanged<int> onChanged) => Padding(
    padding: const .fromLTRB(16, 12, 16, 6),
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          spacing: 12,
          children: [
            _iconBadge(colors.primary, Icons.tune_rounded),
            Expanded(child: Text('Target Bitrate', style: theme.textTheme.bodyLarge)),
            Container(
              padding: const .symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.11), borderRadius: .circular(999)),
              child: Text('$mbps Mbps', style: theme.textTheme.labelMedium?.copyWith(color: colors.primary, fontWeight: .w700)),
            ),
          ],
        ),
        Builder(
          builder: (context) => SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: StreamConstants.minVideoBitrate.toDouble(),
              max: StreamConstants.maxVideoBitrate.toDouble(),
              divisions: 49,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _portTile(ThemeData theme, ColorScheme colors, int port, ValueChanged<int> onChanged) {
    Widget step(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(visualDensity: .compact, tooltip: tip, icon: Icon(icon, size: 18), onPressed: onTap);
    return ListTile(
      leading: _iconBadge(colors.primary, Icons.lan_outlined),
      title: const Text('Network Port'),
      subtitle: const Text('Local port (${StreamConstants.defaultSignalingPort}–${StreamConstants.maxSignalingPort})'),
      trailing: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: .circular(999),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.48)),
        ),
        child: Row(
          mainAxisSize: .min,
          children: [
            step(Icons.remove_rounded, 'Decrease port', port > StreamConstants.defaultSignalingPort ? () => onChanged(port - 1) : null),
            SizedBox(width: 44, child: Text('$port', textAlign: .center, style: theme.textTheme.labelLarge?.copyWith(fontWeight: .w700))),
            step(Icons.add_rounded, 'Increase port', port < StreamConstants.maxSignalingPort ? () => onChanged(port + 1) : null),
          ],
        ),
      ),
    );
  }

  Widget _segmentedRow<T>(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
    T selected,
    ValueChanged<T> onChanged,
    List<ButtonSegment<T>> segments,
  ) => _labeledControlRow(
    theme,
    icon,
    title,
    subtitle,
    SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: .compact, tapTargetSize: .shrinkWrap, padding: WidgetStatePropertyAll(.symmetric(horizontal: 10))),
      segments: segments,
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );

  Widget _labeledControlRow(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
    Widget control,
  ) {
    final colors = theme.colorScheme;
    final label = Row(
      spacing: 12,
      children: [
        _iconBadge(colors.primary, icon),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (_, c) => c.maxWidth < 500
            ? Column(crossAxisAlignment: .stretch, spacing: 10, children: [label, control])
            : Row(spacing: 12, children: [Expanded(child: label), control]),
      ),
    );
  }

  Future<void> _editPin(BuildContext context, String currentPin, AppSettingsNotifier notifier) async {
    final updated = await showDialog<String>(context: context, builder: (_) => _PinConfigDialog(initialPin: currentPin));
    if (updated != null) notifier.setPin(updated);
  }
}

class const _PinConfigDialog({required final String initialPin}) extends StatefulWidget {
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receiver Pairing PIN'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 4,
      keyboardType: .number,
      decoration: InputDecoration(labelText: '4-Digit PIN', hintText: 'Leave empty to disable', errorText: _error),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Disable')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
