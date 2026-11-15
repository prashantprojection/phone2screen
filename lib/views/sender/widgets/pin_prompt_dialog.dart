import 'package:material_ui/material_ui.dart';

/// Prompts the user for a Receiver pairing PIN before initiating signaling.
Future<String?> promptReceiverPin(BuildContext context, String deviceName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinPromptDialog(deviceName: deviceName),
  );
}

class const _PinPromptDialog({required final String deviceName})
    extends StatefulWidget {
  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('PIN for ${widget.deviceName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: .number,
        decoration: const InputDecoration(
          labelText: 'Pairing PIN',
          hintText: 'Enter Receiver PIN',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}
