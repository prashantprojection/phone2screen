import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/network_interface_info.dart';
import '../../../models/signaling_data.dart';
import '../../../providers/discovery_provider.dart';
import '../../../providers/session_provider.dart';

/// Displays Phone Browser shortcut card, USB badge, and Advanced Network Details.
class const NetworkDetailsCard({
  super.key,
  required final SignalingData? endpoint,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final interfacesAsync = ref.watch(networkInterfacesProvider);
    final selectedIp = ref.watch(selectedIpProvider);
    final ep = endpoint;
    final phoneBrowserUrl = ep?.httpsBrowserUrl ?? ep?.browserUrl;
    final interfaces = interfacesAsync.asData?.value ?? const <NetworkInterfaceInfo>[];
    final activeNic = _resolveActiveInterface(interfaces, selectedIp, ep?.ip);

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        if (activeNic?.isUsbTethered == true) _UsbLowLatencyBanner(interfaceName: activeNic!.name),
        Card(
          child: Padding(
            padding: const .all(20),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 10,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.language_rounded, size: 20, color: colors.primary),
                    Expanded(
                      child: Text(
                        'No Phone App? Use Phone Browser',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700),
                      ),
                    ),
                  ],
                ),
                _CopyableRow(
                  label: ep?.httpsBrowserUrl != null ? 'Secure Browser Link' : 'Browser Link',
                  value: phoneBrowserUrl,
                  onCopy: (v) => _copy(context, 'browser link', v),
                ),
                Text(
                  'Open on your phone browser to stream its camera; tap Advanced -> Proceed once.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Card(
          clipBehavior: .antiAlias,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const .symmetric(horizontal: 20, vertical: 6),
              childrenPadding: const .fromLTRB(20, 0, 20, 16),
              leading: Icon(Icons.tune_rounded, size: 20, color: colors.primary),
              title: Text('Advanced Network Details', style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
              subtitle: ep != null
                  ? Text('${ep.ip} • Port ${ep.port}', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
                  : null,
              children: [
                Column(
                  crossAxisAlignment: .stretch,
                  spacing: 10,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: _buildAdapterPicker(context, interfacesAsync, selectedIp, (ip) {
                            ref.read(selectedIpProvider.notifier).selectIp(ip);
                            ref.read(sessionProvider.notifier).restartHosting();
                          }),
                        ),
                        IconButton(
                          onPressed: () => ref.invalidate(networkInterfacesProvider),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Refresh interfaces',
                        ),
                      ],
                    ),
                    _CopyableRow(label: 'IP Address', value: ep?.ip, onCopy: (v) => _copy(context, 'IP address', v)),
                    _CopyableRow(label: 'Web Companion URL', value: ep?.browserUrl, onCopy: (v) => _copy(context, 'Web Companion URL', v)),
                    _CopyableRow(label: 'Port', value: ep != null ? '${ep.port}' : null, onCopy: (v) => _copy(context, 'port', v)),
                    _CopyableRow(label: 'Session ID', value: ep?.sessionId, onCopy: (v) => _copy(context, 'session ID', v)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  NetworkInterfaceInfo? _resolveActiveInterface(List<NetworkInterfaceInfo> list, String? selectedIp, String? endpointIp) {
    if (list.isEmpty) return null;
    for (final target in [selectedIp, endpointIp]) {
      if (target != null && target.isNotEmpty) {
        final hit = list.where((i) => i.address == target).firstOrNull;
        if (hit != null) return hit;
      }
    }
    return list.where((i) => i.isPreferred).firstOrNull ?? list.first;
  }

  Widget _buildAdapterPicker(
    BuildContext context,
    AsyncValue<List<NetworkInterfaceInfo>> interfacesAsync,
    String? selectedIp,
    ValueChanged<String> onSelect,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return interfacesAsync.when(
      loading: () => Text('Scanning network interfaces...', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      error: (_, _) => Text('Unable to list network adapters.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accentRed)),
      data: (interfaces) {
        if (interfaces.isEmpty) {
          return Text('No active IPv4 adapters found.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant));
        }
        final activeIp = interfaces.any((i) => i.address == selectedIp)
            ? selectedIp!
            : (interfaces.where((i) => i.isPreferred).firstOrNull ?? interfaces.first).address;
        return InputDecorator(
          decoration: const InputDecoration(labelText: 'Network Adapter', contentPadding: .symmetric(horizontal: 12, vertical: 6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: activeIp,
              items: [
                for (final item in interfaces)
                  DropdownMenuItem<String>(
                    value: item.address,
                    child: Text(
                      item.isUsbTethered
                          ? '${item.name} (${item.address}) • USB Wired'
                          : (item.isPreferred ? '${item.name} (${item.address}) • Recommended' : '${item.name} (${item.address})'),
                      overflow: .ellipsis,
                    ),
                  ),
              ],
              onChanged: (nextIp) {
                if (nextIp != null && nextIp != activeIp) onSelect(nextIp);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $label')));
  }
}

class const _UsbLowLatencyBanner({required final String interfaceName}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.14),
        borderRadius: .circular(14),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.45)),
      ),
      child: Row(
        spacing: 8,
        children: [
          const Icon(Icons.usb_rounded, size: 18, color: AppColors.accentGreen),
          Expanded(
            child: Text(
              'USB Wired • Ultra-Low Latency ($interfaceName)',
              overflow: .ellipsis,
              style: const TextStyle(color: AppColors.accentGreen, fontSize: 13, fontWeight: .w700),
            ),
          ),
        ],
      ),
    );
  }
}

class const _CopyableRow({
  required final String label,
  required final String? value,
  required final ValueChanged<String> onCopy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = value;
    final enabled = text != null && text.isNotEmpty;

    return InkWell(
      onTap: enabled ? () => onCopy(text) : null,
      borderRadius: .circular(12),
      child: Container(
        padding: const .symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: colors.surfaceContainer.withValues(alpha: 0.65),
          borderRadius: .circular(12),
        ),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  Text(text ?? '--', overflow: .ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: .w600)),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 18, color: enabled ? colors.primary : colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
