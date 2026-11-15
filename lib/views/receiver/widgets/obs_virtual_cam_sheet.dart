import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/obs_sync_provider.dart';
import 'studio_look_audio_section.dart';

/// Studio inspector drawer/sheet for Virtual Camera, Always-On-Top, and OBS WebSocket v5 sync.
class const ObsVirtualCamSheet({super.key}) extends ConsumerStatefulWidget {
  /// Opens as a modal bottom sheet on phones or a right-hand drawer on wider screens.
  static Future<void> show(BuildContext context) {
    if (context.isCompact) {
      return showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true,
        builder: (_) => const ObsVirtualCamSheet(),
      );
    }
    return showGeneralDialog<void>(
      context: context, barrierDismissible: true, barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const .all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Material(
                color: Theme.of(dialogCtx).colorScheme.surface, elevation: 16,
                shadowColor: Colors.black.withValues(alpha: 0.42),
                shape: RoundedRectangleBorder(
                  borderRadius: .circular(22),
                  side: BorderSide(color: Theme.of(dialogCtx).colorScheme.outlineVariant.withValues(alpha: 0.8)),
                ),
                clipBehavior: .antiAlias,
                child: const ObsVirtualCamSheet(),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  ConsumerState<ObsVirtualCamSheet> createState() => _ObsVirtualCamSheetState();
}

class _ObsVirtualCamSheetState extends ConsumerState<ObsVirtualCamSheet> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _passwordCtrl;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(obsConfigProvider);
    _hostCtrl = TextEditingController(text: cfg.host);
    _portCtrl = TextEditingController(text: cfg.port.toString());
    _passwordCtrl = TextEditingController(text: cfg.password);
    Future.microtask(() { if (mounted) unawaited(ref.read(alwaysOnTopProvider.notifier).refresh()); });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveObsConfig() async {
    final port = int.tryParse(_portCtrl.text.trim()) ?? StreamConstants.defaultObsWsPort;
    final current = ref.read(obsConfigProvider);
    await ref.read(obsConfigProvider.notifier).updateConfig(current.copyWith(
      host: _hostCtrl.text.trim().isEmpty ? '127.0.0.1' : _hostCtrl.text.trim(),
      port: port.clamp(1, 65535),
      password: _passwordCtrl.text,
    ));
  }

  Future<void> _provisionCleanFeed(ObsSyncNotifier notifier) async {
    final ok = await notifier.provisionCleanFeed();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok ? 'Clean Feed Browser Source synced to active OBS scene.' : 'Could not update OBS scene. Check OBS connection.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final camsAsync = ref.watch(videoCaptureDevicesProvider);
    final alwaysOnTop = ref.watch(alwaysOnTopProvider);
    final windowsSupported = ref.watch(windowsStudioServiceProvider).isSupported;
    final obsSync = ref.watch(obsSyncProvider);
    final obsNotifier = ref.read(obsSyncProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: .only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .fromLTRB(16, 10, 10, 8),
              child: Row(
                spacing: 10,
                children: [
                  const Icon(Icons.videocam_rounded, color: AppColors.primaryLight),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text('Virtual Cam & OBS', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                        Text('OBS Virtual Camera bridge, pin preview & live tally', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const .fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: .stretch,
                  spacing: 12,
                  children: [
                    _buildVirtualCamCard(theme, colors, camsAsync, obsSync, obsNotifier, alwaysOnTop, windowsSupported),
                    _buildObsTallyCard(theme, colors, obsSync, obsNotifier),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVirtualCamCard(
    ThemeData theme, ColorScheme colors, AsyncValue<List<VideoCaptureDeviceInfo>> camsAsync,
    ObsSyncState obsSync, ObsSyncNotifier obsNotifier, bool alwaysOnTop, bool windowsSupported,
  ) => StudioSectionBox(
    colors: colors,
    children: [
      StudioSectionTitle(
        title: 'Virtual Webcam & 1-Click OBS Bridge',
        subtitle: 'Route your phone feed into OBS Virtual Camera & Discord/Zoom',
        trailing: IconButton(
          tooltip: 'Refresh cameras', visualDensity: .compact,
          onPressed: () => ref.invalidate(videoCaptureDevicesProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ),
      camsAsync.when(
        loading: () => Text('Scanning DirectShow cameras...', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        error: (_, _) => Text('Unable to query DirectShow cameras.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accentRed)),
        data: (devices) {
          final virtualCams = devices.where((d) => d.isVirtualCam).toList();
          if (virtualCams.isEmpty) {
            return _banner(
              Icons.info_outline_rounded, colors.onSurfaceVariant, colors.surfaceContainerHigh.withValues(alpha: 0.65),
              'No Virtual Camera detected yet. Open OBS Studio 28+ on PC (includes OBS Virtual Camera) and connect below.',
            );
          }
          return Wrap(spacing: 6, runSpacing: 6, children: [for (final cam in virtualCams) _statusPill(Icons.check_circle_rounded, cam.name, AppColors.accentGreen)]);
        },
      ),
      FilledButton.icon(
        onPressed: obsSync.connected ? () => unawaited(obsNotifier.toggleVirtualCam()) : null,
        style: obsSync.virtualCamActive ? FilledButton.styleFrom(backgroundColor: AppColors.accentRed, foregroundColor: Colors.white) : null,
        icon: Icon(obsSync.virtualCamActive ? Icons.videocam_off_rounded : Icons.videocam_rounded),
        label: Text(obsSync.virtualCamActive ? 'Stop Virtual Camera' : 'Start Virtual Camera'),
      ),
      OutlinedButton.icon(
        onPressed: obsSync.connected ? () => unawaited(_provisionCleanFeed(obsNotifier)) : null,
        icon: const Icon(Icons.add_to_queue_rounded),
        label: const Text('Send Clean Feed to OBS Scene'),
      ),
      SwitchListTile(
        contentPadding: .zero,
        secondary: const Icon(Icons.push_pin_rounded, size: 20),
        title: const Text('Always on Top'),
        subtitle: Text(windowsSupported ? 'Pin camera preview over borderless games' : 'Pin preview over borderless games (Windows desktop)'),
        value: alwaysOnTop,
        onChanged: (_) => unawaited(ref.read(alwaysOnTopProvider.notifier).toggle()),
      ),
    ],
  );

  Widget _buildObsTallyCard(ThemeData theme, ColorScheme colors, ObsSyncState obsSync, ObsSyncNotifier obsNotifier) {
    final statusLabel = obsSync.connected
        ? 'Connected${obsSync.obsVersion != null ? ' • v${obsSync.obsVersion}' : ''}'
        : (obsSync.connecting ? 'Connecting...' : 'Disconnected');
    final statusColor = obsSync.connected ? AppColors.accentGreen : (obsSync.connecting ? AppColors.accentOrange : colors.onSurfaceVariant);
    final (tallyText, tallyColor) = switch (obsSync.tallyState) {
      .program => ('PROGRAM', AppColors.accentRed),
      .preview => ('PREVIEW', AppColors.accentGreen),
      .standby => ('STANDBY', AppColors.cyanAccent),
      .off => ('OFF', colors.onSurfaceVariant),
    };

    return StudioSectionBox(
      colors: colors,
      children: [
        const StudioSectionTitle(
          title: 'OBS WebSocket v5 Live Tally',
          subtitle: 'Syncs live PROGRAM / PREVIEW status & scenes with your phone',
        ),
        Wrap(
          spacing: 6, runSpacing: 6, crossAxisAlignment: .center,
          children: [
            _statusPill(obsSync.connected ? Icons.link_rounded : Icons.link_off_rounded, statusLabel, statusColor),
            if (obsSync.connected || obsSync.tallyState != .off) _statusPill(Icons.circle, tallyText, tallyColor),
          ],
        ),
        if (obsSync.connected)
          Wrap(
            spacing: 12, runSpacing: 4,
            children: [
              Text('Program: ${obsSync.programScene ?? '--'}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: .w600)),
              if (obsSync.previewScene case final preview? when preview.isNotEmpty)
                Text('Preview: $preview', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        Row(
          spacing: 8,
          children: [
            Expanded(flex: 3, child: TextField(controller: _hostCtrl, decoration: const InputDecoration(labelText: 'OBS Host', hintText: '127.0.0.1', isDense: true), onChanged: (_) => unawaited(_saveObsConfig()))),
            Expanded(flex: 2, child: TextField(controller: _portCtrl, keyboardType: .number, decoration: const InputDecoration(labelText: 'Port', hintText: '4455', isDense: true), onChanged: (_) => unawaited(_saveObsConfig()))),
          ],
        ),
        TextField(
          controller: _passwordCtrl, obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'WebSocket Password', hintText: 'Leave blank if auth is off', isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onChanged: (_) => unawaited(_saveObsConfig()),
        ),
        if (obsSync.errorMessage case final err? when err.isNotEmpty)
          _banner(Icons.warning_amber_rounded, AppColors.accentOrange, AppColors.accentOrange.withValues(alpha: 0.12), '$err\nIn OBS Studio: open Tools -> WebSocket Server Settings and enable WebSocket Server (port 4455).'),
        FilledButton.icon(
          onPressed: obsSync.connecting ? null : () async {
            if (obsSync.connected) {
              await obsNotifier.disconnect();
            } else {
              await _saveObsConfig();
              await obsNotifier.connect();
            }
          },
          style: obsSync.connected ? FilledButton.styleFrom(backgroundColor: colors.surfaceContainerHigh, foregroundColor: colors.onSurface) : null,
          icon: Icon(obsSync.connected ? Icons.link_off_rounded : Icons.link_rounded),
          label: Text(obsSync.connecting ? 'Connecting...' : (obsSync.connected ? 'Disconnect' : 'Connect to OBS')),
        ),
      ],
    );
  }

  Widget _statusPill(IconData icon, String label, Color color) => Container(
    padding: const .symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: .circular(999), border: Border.all(color: color.withValues(alpha: 0.42))),
    child: Row(
      mainAxisSize: .min, spacing: 6,
      children: [Icon(icon, size: 13, color: color), Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: .w700))],
    ),
  );

  Widget _banner(IconData icon, Color color, Color bgColor, String text) => Container(
    padding: const .all(10),
    decoration: BoxDecoration(color: bgColor, borderRadius: .circular(12), border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(
      crossAxisAlignment: .start, spacing: 8,
      children: [Padding(padding: const .only(top: 1), child: Icon(icon, size: 16, color: color)), Expanded(child: Text(text, style: const TextStyle(fontSize: 12)))],
    ),
  );
}
