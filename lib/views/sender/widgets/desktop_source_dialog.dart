import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/session_provider.dart';

/// Modal picker loading desktop screens and windows for Screen Share capture.
class const DesktopSourceDialog({super.key}) extends ConsumerStatefulWidget {
  static Future<DesktopSourceItem?> show(BuildContext context) =>
      showDialog<DesktopSourceItem>(context: context, builder: (_) => const DesktopSourceDialog());

  @override
  ConsumerState<DesktopSourceDialog> createState() => _DesktopSourceDialogState();
}

class _DesktopSourceDialogState extends ConsumerState<DesktopSourceDialog> {
  late Future<List<DesktopSourceItem>> _sourcesFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = ref.read(sessionProvider.notifier).loadDesktopSources();
  }

  void _reload() => setState(() {
        _sourcesFuture = ref.read(sessionProvider.notifier).loadDesktopSources();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 540),
        child: Padding(
          padding: const .all(20),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Select Screen or Window', style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w700))),
                  IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Expanded(
                child: FutureBuilder<List<DesktopSourceItem>>(
                  future: _sourcesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == .waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to list desktop sources', style: TextStyle(color: theme.colorScheme.error)));
                    }
                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) return const Center(child: Text('No screens or windows available.'));
                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.25),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) => _buildTile(ctx, items[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, DesktopSourceItem item) {
    final colors = Theme.of(context).colorScheme;
    final thumb = item.thumbnail;
    return InkWell(
      borderRadius: .circular(12),
      onTap: () => Navigator.of(context).pop(item),
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: .circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const .vertical(top: .circular(11)),
                child: thumb != null && thumb.isNotEmpty
                    ? Image.memory(thumb, fit: .cover)
                    : ColoredBox(
                        color: AppColors.backgroundDark,
                        child: Icon(
                          item.isWindow ? Icons.web_asset_rounded : Icons.desktop_windows_rounded,
                          size: 36,
                          color: AppColors.primaryLight,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const .symmetric(horizontal: 10, vertical: 8),
              child: Row(
                spacing: 6,
                children: [
                  Icon(item.isWindow ? Icons.web_asset_rounded : Icons.monitor_rounded, size: 14, color: colors.primary),
                  Expanded(child: Text(item.name, maxLines: 1, overflow: .ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
