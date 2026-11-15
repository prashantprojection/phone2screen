import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/network_interface_info.dart';
import '../../../models/signaling_data.dart';
import '../../../providers/discovery_provider.dart';
import '../../../providers/session_provider.dart';

/// Displays LAN adapter selector and 1-tap copyable receiver endpoint fields.
class const NetworkDetailsCard({super.key, required final SignalingData? endpoint})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final interfacesAsync = ref.watch(networkInterfacesProvider);
    final selectedIp = ref.watch(selectedIpProvider);
    final ep = endpoint;

    return Card(
      child: Padding(
        padding: const .all(20),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 8,
              children: [
                Icon(Icons.lan_rounded, size: 20, color: colors.primary),
                Expanded(
                  child: Text('Network & Connection', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                ),
                IconButton(
                  onPressed: () => ref.invalidate(networkInterfacesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh interfaces',
                ),
              ],
            ),
            _buildAdapterPicker(context, interfacesAsync, selectedIp, (ip) {
              ref.read(selectedIpProvider.notifier).selectIp(ip);
              ref.read(sessionProvider.notifier).restartHosting();
            }),
            const Divider(height: 4),
            _CopyableRow(label: 'IP Address', value: ep?.ip, onCopy: (v) => _copy(context, 'IP address', v)),
            _CopyableRow(
              label: 'Signaling Port',
              value: ep != null ? '${ep.port}' : null,
              onCopy: (v) => _copy(context, 'port', v),
            ),
            _CopyableRow(label: 'Session ID', value: ep?.sessionId, onCopy: (v) => _copy(context, 'session ID', v)),
            _CopyableRow(
              label: 'Web Companion URL',
              value: ep?.browserUrl,
              onCopy: (v) => _copy(context, 'Web Companion URL', v),
            ),
          ],
        ),
      ),
    );
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
      error: (_, _) => Text('Unable to enumerate network adapters.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accentRed)),
      data: (interfaces) {
        if (interfaces.isEmpty) {
          return Text('No active IPv4 adapters found.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant));
        }
        final activeIp = interfaces.any((i) => i.address == selectedIp)
            ? selectedIp!
            : (interfaces.where((i) => i.isPreferred).firstOrNull ?? interfaces.first).address;
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Network Adapter',
            contentPadding: .symmetric(horizontal: 12, vertical: 6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: activeIp,
              items: [
                for (final item in interfaces)
                  DropdownMenuItem<String>(
                    value: item.address,
                    child: Text(
                      item.isPreferred ? '${item.name} (${item.address}) • Recommended' : '${item.name} (${item.address})',
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
      borderRadius: .circular(10),
      child: Container(
        padding: const .symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: .circular(10),
          border: Border.all(color: colors.outlineVariant),
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
