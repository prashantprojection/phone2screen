import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../providers/platform_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../shared/error_banner.dart';
import '../shared/video_stage_widget.dart';
import 'widgets/active_sender_controls.dart';
import 'widgets/manual_connect_sheet.dart';
import 'widgets/nearby_devices_list.dart';
import 'widgets/pin_prompt_dialog.dart';
import 'widgets/qr_scanner_page.dart';
import 'widgets/source_picker_card.dart';

/// Adaptive Sender view for discovering Receivers and broadcasting live video.
class const SenderScreen({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends ConsumerState<SenderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(sessionProvider.notifier).startDiscovery();
      }
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(appSettingsProvider);
    final platform = ref.watch(platformServiceProvider);
    final isLive =
        session.phase == .connecting ||
        session.phase == .streaming ||
        session.phase == .reconnecting;

    if (isLive) {
      return _buildLiveView(context, session, settings);
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: SingleChildScrollView(
          padding: const .all(16),
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (platform.supportsQrScanner)
                    FilledButton.icon(
                      onPressed: _scanQrAndConnect,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan QR Code'),
                    ),
                  if (platform.supportsQrScanner)
                    OutlinedButton.icon(
                      onPressed: () => ManualConnectSheet.show(context),
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Manual IP Connect'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () => ManualConnectSheet.show(context),
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Manual IP Connect'),
                    ),
                ],
              ),
              if (context.isExpanded)
                const Row(
                  crossAxisAlignment: .start,
                  spacing: 16,
                  children: [
                    Expanded(flex: 5, child: SourcePickerCard()),
                    Expanded(flex: 6, child: NearbyDevicesList()),
                  ],
                )
              else
                const Column(
                  crossAxisAlignment: .stretch,
                  spacing: 16,
                  children: [
                    SourcePickerCard(),
                    NearbyDevicesList(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveView(
    BuildContext context,
    SessionState session,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);
    final peerName =
        session.connectedPeerName ?? session.activeEndpoint?.deviceName ?? 'Receiver';
    final telemetry = session.telemetry;
    final showEcoCard = settings.ecoDimPreview && session.phase == .streaming;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Card(
                child: Padding(
                  padding: const .symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    spacing: 10,
                    children: [
                      const Icon(Icons.cast_connected_rounded, color: AppColors.accentGreen, size: 20),
                      Expanded(
                        child: Text(
                          peerName,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700),
                        ),
                      ),
                      Chip(
                        visualDensity: .compact,
                        label: Text(
                          '${telemetry.latencyMs}ms • ${telemetry.bitrateMbps.toStringAsFixed(1)} Mbps',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (session.errorMessage != null)
                ErrorBanner(
                  message: session.errorMessage!,
                  onDismiss: () => ref.read(sessionProvider.notifier).clearError(),
                ),
              Expanded(
                child: showEcoCard
                    ? _EcoDimPreviewCard(
                        onShowPreview: () => ref
                            .read(appSettingsProvider.notifier)
                            .setEcoDimPreview(false),
                      )
                    : VideoStageWidget(
                        stream: session.localStream,
                        waitingLabel: session.phase == .connecting
                            ? 'Connecting to $peerName...'
                            : 'Preparing stream...',
                      ),
              ),
              const ActiveSenderControls(),
            ],
          ),
        ),
      ),
    );
  }
}

class const _EcoDimPreviewCard({required final VoidCallback onShowPreview})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.backgroundDark,
      child: Center(
        child: Padding(
          padding: const .all(24),
          child: Column(
            mainAxisSize: .min,
            spacing: 12,
            children: [
              const Icon(Icons.battery_saver_rounded, size: 48, color: AppColors.accentGreen),
              Text(
                'Eco Dim Preview Active',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimaryDark,
                  fontWeight: .w700,
                ),
              ),
              Text(
                'Local video preview is unmounted during streaming to save battery and GPU on Tier-3 devices.',
                textAlign: .center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShowPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Show Local Preview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
