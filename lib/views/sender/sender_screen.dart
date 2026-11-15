import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/stream_config.dart';
import '../../providers/platform_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../shared/error_banner.dart';
import '../shared/video_stage_widget.dart';
import 'widgets/active_sender_controls.dart';
import 'widgets/desktop_source_dialog.dart';
import 'widgets/nearby_devices_list.dart';
import 'widgets/oled_tally_view.dart';
import 'widgets/pin_prompt_dialog.dart';
import 'widgets/qr_scanner_page.dart';
import 'widgets/source_picker_card.dart';
import 'widgets/web_broadcast_card.dart';

/// Adaptive Sender view for guided 1 -> 2 casting and live streaming HUD.
class const SenderScreen({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends ConsumerState<SenderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sessionProvider.notifier).startDiscovery();
    });
  }

  Future<void> _scanQrAndConnect() async {
    final target = await QrScannerPage.scan(context);
    if (target == null || !mounted) return;
    String? pin;
    if (target.requiresPin) {
      pin = await promptReceiverPin(context, target.deviceName);
      if (pin == null || pin.isEmpty || !mounted) return;
    }
    await ref.read(sessionProvider.notifier).connectAndStream(target, pin: pin);
  }

  Future<void> _startWebBroadcast() async {
    final config = ref.read(streamConfigProvider);
    final platform = ref.read(platformServiceProvider);
    if (config.sourceType == .screen && platform.supportsDesktopPicker && config.desktopSourceId == null) {
      final picked = await DesktopSourceDialog.show(context);
      if (picked == null || !mounted) return;
      ref.read(streamConfigProvider.notifier).setDesktopSourceId(picked.id);
    }
    if (mounted) await ref.read(sessionProvider.notifier).startWebBroadcast();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(appSettingsProvider);
    final config = ref.watch(streamConfigProvider);
    final platform = ref.watch(platformServiceProvider);
    final isLive = session.phase == .connecting || session.phase == .streaming || session.phase == .reconnecting;

    if (session.isWebBroadcast && session.phase == .hosting) return WebBroadcastLobbyView(session: session);
    if (isLive) return _buildLiveView(context, session, settings, config);

    final theme = Theme.of(context);
    final nearbyList = NearbyDevicesList(onScanQr: platform.supportsQrScanner ? _scanQrAndConnect : null);
    final browserCard = platform.canHostServer ? _BrowserCastCard(onStart: _startWebBroadcast) : null;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: SingleChildScrollView(
          padding: .all(context.isCompact ? 16 : 20),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              if (session.errorMessage != null)
                ErrorBanner(
                  message: session.errorMessage!,
                  onRetry: () => ref.read(sessionProvider.notifier).startDiscovery(),
                  onDismiss: () => ref.read(sessionProvider.notifier).clearError(),
                ),
              Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text('Share Camera or Screen', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .w700)),
                  Text(
                    'Choose what to share first, then tap a nearby screen or cast to any web browser.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (context.isExpanded)
                Row(
                  crossAxisAlignment: .start,
                  spacing: 20,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(crossAxisAlignment: .stretch, spacing: 16, children: [const SourcePickerCard(), ?browserCard]),
                    ),
                    Expanded(flex: 6, child: nearbyList),
                  ],
                )
              else
                Column(crossAxisAlignment: .stretch, spacing: 16, children: [const SourcePickerCard(), nearbyList, ?browserCard]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveView(BuildContext context, SessionState session, AppSettings settings, StreamConfig config) {
    final peerName = session.connectedPeerName ?? session.activeEndpoint?.deviceName ?? 'Receiver';
    final showOledTally = settings.ecoDimPreview && session.phase == .streaming;
    final (statusColor, statusPrefix) = session.phase != .streaming
        ? (
            AppColors.accentOrange,
            session.phase == .reconnecting ? 'Reconnecting' : 'Connecting',
          )
        : (session.isVideoPaused
              ? (AppColors.accentOrange, 'PAUSED')
              : switch (session.liveTally.state) {
                  .preview => (AppColors.accentGreen, 'Preview'),
                  .standby => (AppColors.cyanAccent, 'Standby'),
                  .program || .off => (AppColors.accentRed, 'ON AIR'),
                });
    final statusLabel = '$statusPrefix • $peerName';

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: .expand,
        children: [
          Positioned.fill(
            child: showOledTally
                ? OledTallyView(
                    targetName: peerName,
                    phase: session.phase,
                    telemetry: session.telemetry,
                    streamConfig: config,
                    tallyState: session.liveTally.state,
                    tallyScene: session.liveTally.sceneName,
                    onShowPreview: () => ref.read(appSettingsProvider.notifier).setEcoDimPreview(false),
                  )
                : VideoStageWidget(
                    stream: session.localStream,
                    isPaused: session.isVideoPaused,
                    borderRadius: 0,
                    waitingLabel: session.phase == .connecting ? 'Connecting to $peerName...' : 'Preparing stream...',
                  ),
          ),
          if (!showOledTally)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.56), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: 8,
                children: [
                  if (session.errorMessage != null)
                    ErrorBanner(
                      message: session.errorMessage!,
                      onDismiss: () => ref.read(sessionProvider.notifier).clearError(),
                    ),
                  Row(
                    mainAxisAlignment: .spaceBetween,
                    spacing: 8,
                    children: [
                      Flexible(child: _LiveStatusPill(label: statusLabel, color: statusColor)),
                      _BatterySaverPill(
                        active: settings.ecoDimPreview,
                        onToggle: () => ref.read(appSettingsProvider.notifier).setEcoDimPreview(!settings.ecoDimPreview),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(top: false, child: ActiveSenderControls()),
          ),
        ],
      ),
    );
  }
}

class const _BrowserCastCard({required final VoidCallback onStart}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const .all(18),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Row(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.12), borderRadius: .circular(12)),
                  child: Icon(Icons.public_rounded, color: colors.primary, size: 22),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 3,
                    children: [
                      Text('Watch in Any Browser', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                      Text(
                        'Stream directly into OBS Studio Browser Source (/obs) or watch in any browser.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: onStart,
              icon: const Icon(Icons.public_rounded, size: 18),
              label: const Text('Cast to Web Browser'),
            ),
          ],
        ),
      ),
    );
  }
}

class const _LiveStatusPill({required final String label, required final Color color}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const .symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF14161A).withValues(alpha: 0.80),
      borderRadius: .circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Row(
      mainAxisSize: .min,
      spacing: 7,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: .circle)),
        Flexible(
          child: Text(label, maxLines: 1, overflow: .ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: .w600)),
        ),
      ],
    ),
  );
}

class const _BatterySaverPill({required final bool active, required final VoidCallback onToggle}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.accentGreen : Colors.white;
    return Material(
      color: const Color(0xFF14161A).withValues(alpha: active ? 0.88 : 0.80),
      shape: StadiumBorder(
        side: BorderSide(color: active ? AppColors.accentGreen.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.14)),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Icon(Icons.battery_saver_rounded, size: 15, color: fg),
              Text('Battery Saver', style: TextStyle(color: fg, fontSize: 12, fontWeight: .w600)),
            ],
          ),
        ),
      ),
    );
  }
}
