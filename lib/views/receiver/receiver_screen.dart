import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/session_phase.dart';
import '../../../models/window_launch_args.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/preferences_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../shared/error_banner.dart';
import 'widgets/network_details_card.dart';
import 'widgets/qr_pairing_card.dart';
import 'widgets/receiver_streaming_stage.dart';

/// Receiver landing lobby and live WebRTC video viewing screen.
class const ReceiverScreen({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends ConsumerState<ReceiverScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(platformServiceProvider).canHostServer) {
        ref.read(sessionProvider.notifier).startHosting();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(platformServiceProvider);
    if (!platform.canHostServer) {
      return _WebUnsupportedNotice(
        onSwitchToSender: () => ref.read(activeRoleProvider.notifier).setRole(.sender),
      );
    }

    final session = ref.watch(sessionProvider);
    final display = ref.watch(viewerDisplayProvider);
    final multiCam = ref.watch(multiCamProvider);
    final hasActiveStage = session.phase == .streaming ||
        session.phase == .connecting ||
        session.phase == .reconnecting ||
        multiCam.secondarySlots.isNotEmpty;
    if (hasActiveStage) {
      return ReceiverStreamingStage(
        session: session,
        display: display,
        onExitFullscreen: () => ref.read(viewerDisplayProvider.notifier).setFullscreen(false),
        onDismissError: () => ref.read(sessionProvider.notifier).clearError(),
      );
    }

    final theme = Theme.of(context);
    final endpoint = session.activeEndpoint;
    final launchArgs = ref.watch(windowLaunchArgsProvider);
    final isDesktop = !platform.isWeb && platform.isDesktop;
    final heading = endpoint != null ? 'Ready on ${endpoint.deviceName}' : 'Ready to Receive';
    final subtitle = endpoint != null || session.phase == .hosting
        ? 'Open Phone2Screen on your phone and tap this screen — or scan the QR code.'
        : (session.phase == .failed
              ? 'Could not start receiving on Wi-Fi. Tap Retry below.'
              : 'Preparing your Wi-Fi connection...');

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: SingleChildScrollView(
          padding: const .all(20),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              if (session.errorMessage != null)
                ErrorBanner(
                  message: session.errorMessage!,
                  onRetry: () => ref.read(sessionProvider.notifier).restartHosting(),
                  onDismiss: () => ref.read(sessionProvider.notifier).clearError(),
                ),
              Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(heading, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .w700)),
                  Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              if (isDesktop) _MultiCamWindowsBar(launchArgs: launchArgs, multiCam: multiCam),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = context.isExpanded || constraints.maxWidth >= 860;
                  final pairingWidget = endpoint != null
                      ? QrPairingCard(endpoint: endpoint)
                      : _StartingHostCard(
                          phase: session.phase,
                          onRetry: () => ref.read(sessionProvider.notifier).restartHosting(),
                        );
                  final detailsWidget = NetworkDetailsCard(endpoint: endpoint);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: .start,
                      spacing: 20,
                      children: [
                        Expanded(flex: 5, child: pairingWidget),
                        Expanded(flex: 6, child: detailsWidget),
                      ],
                    );
                  }
                  return Column(crossAxisAlignment: .stretch, spacing: 16, children: [pairingWidget, detailsWidget]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _MultiCamWindowsBar({
  required final WindowLaunchArgs launchArgs,
  required final MultiCamState multiCam,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final notifier = ref.read(multiCamProvider.notifier);
    final canOpen = multiCam.childWindows.length < StreamConstants.maxDesktopReceiverPeers - 1;

    return Card(
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          alignment: .spaceBetween,
          crossAxisAlignment: .center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: .center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Icon(Icons.grid_view_rounded, size: 18, color: AppColors.cyanAccent),
                Text('Multi-Camera & OBS Windows', style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
                if (launchArgs.isSecondaryCameraWindow)
                  Chip(
                    visualDensity: .compact,
                    backgroundColor: AppColors.cyanAccent.withValues(alpha: 0.16),
                    label: Text('Camera Slot ${launchArgs.cameraSlot}', style: const TextStyle(color: AppColors.cyanAccent, fontWeight: .w700)),
                  ),
                for (final win in multiCam.childWindows)
                  InputChip(
                    visualDensity: .compact,
                    label: Text('Cam ${win.slot} (:${win.port})'),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () => notifier.closeCameraWindow(win.slot),
                  ),
              ],
            ),
            if (!launchArgs.isSecondaryCameraWindow)
              FilledButton.tonalIcon(
                onPressed: canOpen ? () => notifier.openCameraWindow() : null,
                style: FilledButton.styleFrom(visualDensity: .compact),
                icon: Icon(Icons.open_in_new_rounded, size: 17, color: colors.primary),
                label: const Text('+ Open Camera Window'),
              ),
          ],
        ),
      ),
    );
  }
}

class const _WebUnsupportedNotice({required final VoidCallback onSwitchToSender})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const .all(24),
          child: Card(
            child: Padding(
              padding: const .all(24),
              child: Column(
                mainAxisSize: .min,
                spacing: 14,
                children: [
                  const Icon(Icons.public_off_rounded, size: 44, color: AppColors.primaryLight),
                  Text('Browser Cannot Receive Directly', textAlign: .center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w700)),
                  Text(
                    'Web browsers cannot host a Wi-Fi receiving screen. Switch to the Send tab to cast from here, or open Phone2Screen on Windows or Android to receive.',
                    textAlign: .center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  FilledButton.icon(onPressed: onSwitchToSender, icon: const Icon(Icons.smartphone_rounded), label: const Text('Switch to Send')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _StartingHostCard({required final SessionPhase phase, required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const .all(28),
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            const Icon(Icons.wifi_tethering_rounded, size: 40, color: AppColors.primaryBlue),
            Text(
              phase == .failed ? 'Could not start Wi-Fi receiver' : 'Preparing Wi-Fi receiver...',
              textAlign: .center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: .w600),
            ),
            if (phase == .failed)
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
