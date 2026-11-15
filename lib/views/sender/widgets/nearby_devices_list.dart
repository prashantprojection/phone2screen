import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/discovered_peer.dart';
import '../../../providers/discovery_provider.dart';
import '../../../providers/session_provider.dart';
import 'pin_prompt_dialog.dart';

/// Discovered LAN Receivers list with radar empty state and PIN prompt.
class const NearbyDevicesList({super.key}) extends ConsumerWidget {
  Future<void> _connectToPeer(
    BuildContext context,
    WidgetRef ref,
    DiscoveredPeer peer,
  ) async {
    String? pin;
    if (peer.endpoint.requiresPin) {
      pin = await promptReceiverPin(context, peer.endpoint.deviceName);
      if (pin == null || pin.isEmpty || !context.mounted) return;
    }
    await ref.read(sessionProvider.notifier).connectAndStream(peer.endpoint, pin: pin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(discoveredPeersProvider).value ?? const [];
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const .all(18),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              children: [
                const Icon(Icons.radar_rounded, color: AppColors.cyanAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nearby Receivers',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh LAN scan',
                  onPressed: () => ref.read(sessionProvider.notifier).startDiscovery(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (peers.isEmpty)
              const _RadarEmptyState()
            else
              for (final peer in peers)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: .circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.14),
                    child: const Icon(Icons.desktop_windows_rounded, color: AppColors.primaryLight),
                  ),
                  title: Text(peer.endpoint.deviceName),
                  subtitle: Text('${peer.endpoint.ip}:${peer.endpoint.port}'),
                  trailing: Row(
                    mainAxisSize: .min,
                    spacing: 8,
                    children: [
                      if (peer.endpoint.requiresPin)
                        const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.accentOrange),
                      FilledButton.tonal(
                        onPressed: () => _connectToPeer(context, ref, peer),
                        child: const Text('Cast'),
                      ),
                    ],
                  ),
                  onTap: () => _connectToPeer(context, ref, peer),
                ),
          ],
        ),
      ),
    );
  }
}

class const _RadarEmptyState() extends StatefulWidget {
  @override
  State<_RadarEmptyState> createState() => _RadarEmptyStateState();
}

class _RadarEmptyStateState extends State<_RadarEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .symmetric(vertical: 20, horizontal: 12),
      child: Column(
        spacing: 10,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: .circle,
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.cyanAccent.withValues(alpha: 0.45)),
              ),
              child: const Icon(Icons.wifi_tethering_rounded, color: AppColors.cyanAccent, size: 26),
            ),
          ),
          Text('Scanning LAN (UDP 41234)...', textAlign: .center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w600)),
          Text(
            'Open Phone2Screen Receiver on a PC, or use QR / Manual IP.',
            textAlign: .center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
