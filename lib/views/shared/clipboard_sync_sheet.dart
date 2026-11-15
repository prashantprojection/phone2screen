import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../models/clipboard_item.dart';
import '../../providers/session_provider.dart';

/// Modal bottom sheet to share text live between connected screens.
class const ClipboardSyncSheet({super.key}) extends ConsumerStatefulWidget {
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const ClipboardSyncSheet(),
  );

  @override
  ConsumerState<ClipboardSyncSheet> createState() => _ClipboardSyncSheetState();
}

class _ClipboardSyncSheetState extends ConsumerState<ClipboardSyncSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromSystem() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) return;
    _controller
      ..text = text
      ..selection = .collapsed(offset: text.length);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(sessionProvider.notifier).sendClipboardText(text);
    _controller.clear();
  }

  Future<void> _copyItem(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(sessionProvider.select((s) => s.clipboardHistory));
    final phase = ref.watch(sessionProvider.select((s) => s.phase));
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: .fromLTRB(16, 16, 16, 16 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Column(
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    const Icon(Icons.content_paste_go_rounded, size: 20),
                    Expanded(
                      child: Text(
                        'Share Text (Clipboard)',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  'Send links, notes, or passwords instantly between connected screens.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: .end,
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: .send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Type or paste text to share...'),
                  ),
                ),
                IconButton(onPressed: _pasteFromSystem, icon: const Icon(Icons.content_paste_rounded), tooltip: 'Paste'),
                FilledButton.icon(
                  onPressed: phase == .streaming ? _send : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send'),
                ),
              ],
            ),
            if (history.isEmpty)
              Padding(
                padding: const .symmetric(vertical: 20),
                child: Text(
                  phase == .streaming
                      ? 'No shared text yet. Type or paste above to send.'
                      : 'Connect a screen first to share text live.',
                  textAlign: .center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildRow(context, history[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, ClipboardItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final badge = item.fromRemote ? AppColors.cyanAccent : AppColors.primaryBlue;
    final hh = item.timestamp.hour.toString().padLeft(2, '0');
    final mm = item.timestamp.minute.toString().padLeft(2, '0');
    return InkWell(
      onTap: () => _copyItem(item.text),
      borderRadius: .circular(12),
      child: Container(
        padding: const .all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: .circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(item.fromRemote ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: badge),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text('${item.fromRemote ? 'Remote' : 'Sent'} • $hh:$mm', style: theme.textTheme.labelSmall?.copyWith(color: badge, fontWeight: .w600)),
                  Text(item.text, maxLines: 3, overflow: .ellipsis),
                ],
              ),
            ),
            IconButton(onPressed: () => _copyItem(item.text), icon: const Icon(Icons.copy_rounded, size: 18)),
          ],
        ),
      ),
    );
  }
}
