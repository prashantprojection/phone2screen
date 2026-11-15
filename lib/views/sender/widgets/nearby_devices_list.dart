import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/signaling_data.dart';
import '../../../providers/discovery_provider.dart';
import '../../../providers/preferences_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import 'manual_connect_sheet.dart';
import 'pin_prompt_dialog.dart';

/// Step 2 card listing nearby Receivers, last-endpoint quick reconnect, and USB/ADB.
class const NearbyDevicesList({
  super.key,
  final VoidCallback? onScanQr,
}) extends ConsumerWidget {
  Future<void> _connectToEndpoint(BuildContext context, WidgetRef ref, SignalingData endpoint) async {
    String? pin;
    if (endpoint.requiresPin) {
      pin = await promptReceiverPin(context, endpoint.deviceName);
      if (pin == null || pin.isEmpty || !context.mounted) return;
    }
    await ref.read(sessionProvider.notifier).connectAndStream(endpoint, pin: pin);
  }

  Future<void> _connectViaUsbAdb(WidgetRef ref) async {
    final port = ref.read(appSettingsProvider).preferredPort;
    final effectivePort = port > 0 ? port : StreamConstants.defaultSignalingPort;
    final target = SignalingData(
      ip: '127.0.0.1',
      port: effectivePort,
      sessionId: 'usb-${DateTime.now().millisecondsSinceEpoch}',
      deviceName: 'USB PC (127.0.0.1)',
    );
    await ref.read(sessionProvider.notifier).connectAndStream(target);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(discoveredPeersProvider).value ?? const [];
    final lastEndpoint = ref.watch(lastEndpointProvider);
    final showReconnect =
        lastEndpoint != null &&
        !peers.any((p) => p.endpoint.ip == lastEndpoint.ip && p.endpoint.port == lastEndpoint.port);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const .all(18),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 10,
              children: [
                const _StepBadge(step: '2'),
                Expanded(child: Text('Nearby Screens', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700))),
                IconButton(
                  tooltip: 'Refresh nearby screens',
                  onPressed: () => ref.read(sessionProvider.notifier).startDiscovery(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (showReconnect)
              _ReconnectTile(
                endpoint: lastEndpoint,
                onConnect: () => _connectToEndpoint(context, ref, lastEndpoint),
                onClear: () => ref.read(lastEndpointProvider.notifier).clear(),
              ),
            if (peers.isEmpty)
              const _RadarEmptyState()
            else
              Column(
                crossAxisAlignment: .stretch,
                spacing: 8,
                children: [
                  for (final peer in peers)
                    ListTile(
                      contentPadding: const .symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: .circular(14),
                        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.42)),
                      ),
                      tileColor: colors.surfaceContainer,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                        child: const Icon(Icons.desktop_windows_rounded, color: AppColors.primaryLight, size: 20),
                      ),
                      title: Text(peer.endpoint.deviceName, maxLines: 1, overflow: .ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w600)),
                      subtitle: Text('${peer.endpoint.ip}:${peer.endpoint.port}', maxLines: 1, overflow: .ellipsis),
                      trailing: Row(
                        mainAxisSize: .min,
                        spacing: 8,
                        children: [
                          if (peer.endpoint.requiresPin)
                            const Tooltip(message: 'PIN required', child: Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.accentOrange)),
                          FilledButton(
                            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const .symmetric(horizontal: 16, vertical: 10)),
                            onPressed: () => _connectToEndpoint(context, ref, peer.endpoint),
                            child: const Text('Connect'),
                          ),
                        ],
                      ),
                      onTap: () => _connectToEndpoint(context, ref, peer.endpoint),
                    ),
                ],
              ),
            const Divider(height: 1),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onScanQr != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    onPressed: onScanQr,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan QR Code'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  onPressed: () => ManualConnectSheet.show(context),
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: const Text('Enter IP Manually'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  onPressed: () => _connectViaUsbAdb(ref),
                  icon: const Icon(Icons.usb_rounded, size: 18),
                  label: const Text('USB / ADB'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _ReconnectTile({
  required final SignalingData endpoint,
  required final VoidCallback onConnect,
  required final VoidCallback onClear,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: .circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const .fromLTRB(12, 2, 6, 2),
        leading: Icon(Icons.history_rounded, color: colors.primary, size: 20),
        title: Text('Reconnect to ${endpoint.deviceName}', maxLines: 1, overflow: .ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
        subtitle: Text('${endpoint.ip}:${endpoint.port}', maxLines: 1, overflow: .ellipsis),
        trailing: Row(
          mainAxisSize: .min,
          spacing: 2,
          children: [
            FilledButton.tonal(
              style: FilledButton.styleFrom(shape: const StadiumBorder(), visualDensity: .compact, padding: const .symmetric(horizontal: 14, vertical: 8)),
              onPressed: onConnect,
              child: const Text('Connect'),
            ),
            IconButton(visualDensity: .compact, tooltip: 'Forget saved screen', icon: const Icon(Icons.close_rounded, size: 17), onPressed: onClear),
          ],
        ),
        onTap: onConnect,
      ),
    );
  }
}

class const _StepBadge({required final String step}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.12), shape: .circle),
      child: Text(step, style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: .w800)),
    );
  }
}

class const _RadarEmptyState() extends StatefulWidget {
  @override
  State<_RadarEmptyState> createState() => _RadarEmptyStateState();
}

class _RadarEmptyStateState extends State<_RadarEmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .symmetric(vertical: 18, horizontal: 12),
      child: Column(
        spacing: 10,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: .circle, color: AppColors.primaryBlue.withValues(alpha: 0.12), border: Border.all(color: AppColors.cyanAccent.withValues(alpha: 0.30))),
              child: const Icon(Icons.wifi_tethering_rounded, color: AppColors.cyanAccent, size: 26),
            ),
          ),
          Text('Looking for screens on your Wi-Fi...', textAlign: .center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w600)),
          Text('Open Phone2Screen in Receive mode on your PC or TV.', textAlign: .center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
