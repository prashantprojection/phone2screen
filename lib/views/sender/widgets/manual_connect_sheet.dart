import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../models/signaling_data.dart';
import '../../../providers/session_provider.dart';

/// Modal bottom sheet for connecting directly via host IP/hostname, port, and PIN.
class const ManualConnectSheet({super.key}) extends ConsumerStatefulWidget {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ManualConnectSheet(),
    );
  }

  @override
  ConsumerState<ManualConnectSheet> createState() => _ManualConnectSheetState();
}

class _ManualConnectSheetState extends ConsumerState<ManualConnectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '${StreamConstants.defaultSignalingPort}');
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    final pin = _pinController.text.trim();
    final target = SignalingData(
      ip: host,
      port: port,
      sessionId: 'manual-${DateTime.now().millisecondsSinceEpoch}',
      deviceName: host,
      requiresPin: pin.isNotEmpty,
    );
    Navigator.of(context).pop();
    ref.read(sessionProvider.notifier).connectAndStream(target, pin: pin.isEmpty ? null : pin);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: .fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Text('Enter IP Manually', style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w700)),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Text(
                'Only needed if your Wi-Fi blocks automatic screen discovery.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextFormField(
                controller: _hostController,
                autofocus: true,
                textInputAction: .next,
                decoration: const InputDecoration(
                  labelText: 'Receiver IP or Hostname',
                  hintText: '192.168.1.42',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an IP address or hostname' : null,
              ),
              Row(
                crossAxisAlignment: .start,
                spacing: 12,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _portController,
                      keyboardType: .number,
                      textInputAction: .next,
                      decoration: const InputDecoration(labelText: 'Port', hintText: '8080'),
                      validator: (v) {
                        final port = int.tryParse((v ?? '').trim());
                        return (port == null || port < 1 || port > 65535) ? '1..65535' : null;
                      },
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _pinController,
                      keyboardType: .number,
                      obscureText: true,
                      textInputAction: .done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'PIN (Optional)', hintText: '1234'),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.cast_connected_rounded),
                label: const Text('Connect & Start Casting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
