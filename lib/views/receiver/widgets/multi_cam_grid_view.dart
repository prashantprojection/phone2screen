import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/camera_feed_slot.dart';
import '../../../models/stream_telemetry.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/platform_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../shared/video_stage_widget.dart';
import 'telemetry_overlay.dart';

/// Multi-camera receiver stage rendering Solo, 2-Up split, or 2x2 studio grid.
class const MultiCamGridView({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiCam = ref.watch(multiCamProvider);
    final notifier = ref.read(multiCamProvider.notifier);
    final platform = ref.watch(platformServiceProvider);
    final isDesktop = !platform.isWeb && platform.isDesktop;
    final feeds = _buildFeedList(session, display, multiCam);

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        _buildToolbar(context, multiCam, feeds, isDesktop, notifier),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => _buildGrid(
              context,
              ref,
              multiCam.layout,
              feeds,
              multiCam.selectedPeerId,
              display.showTelemetry,
              c.maxWidth >= 680 && c.maxWidth >= c.maxHeight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, MultiCamState multiCam, List<_FeedItem> feeds, bool isDesktop, MultiCamNotifier notifier) {
    final colors = Theme.of(context).colorScheme;
    final canOpen = multiCam.childWindows.length < StreamConstants.maxDesktopReceiverPeers - 1;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: .horizontal,
            child: Row(
              spacing: 6,
              children: [
                for (final mode in MultiCamLayout.values)
                  ChoiceChip(label: Text(mode.label), selected: multiCam.layout == mode, showCheckmark: false, visualDensity: .compact, onSelected: (_) => notifier.setLayout(mode)),
                if (multiCam.layout == .solo && feeds.length > 1) ...[
                  Container(width: 1, height: 20, color: colors.outlineVariant),
                  for (final f in feeds)
                    ChoiceChip(label: Text('Cam ${f.slotNumber}'), selected: f.peerId == multiCam.selectedPeerId, showCheckmark: false, visualDensity: .compact, onSelected: (_) => notifier.selectSlot(f.peerId)),
                ],
              ],
            ),
          ),
        ),
        if (isDesktop)
          OutlinedButton.icon(
            onPressed: canOpen ? () => _openWindow(context, notifier) : null,
            style: OutlinedButton.styleFrom(visualDensity: .compact, padding: const .symmetric(horizontal: 12, vertical: 8)),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('+ Cam Window'),
          ),
      ],
    );
  }

  Future<void> _openWindow(BuildContext context, MultiCamNotifier notifier) async {
    final entry = await notifier.openCameraWindow();
    if (entry == null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Maximum camera windows already open.')));
    }
  }

  List<_FeedItem> _buildFeedList(SessionState session, ViewerDisplayConfig primaryDisplay, MultiCamState multiCam) => [
    _FeedItem(peerId: null, slotNumber: 1, label: session.connectedPeerName ?? 'Camera 1', stream: session.remoteStream, telemetry: session.telemetry, micMuted: session.remoteCameraState.micMuted, displayConfig: primaryDisplay),
    ...multiCam.secondarySlots.values.toList().asMap().entries.map((e) {
      final s = e.value;
      return _FeedItem(peerId: s.peerId, slotNumber: e.key + 2, label: s.deviceName, stream: s.stream, telemetry: s.telemetry, micMuted: s.cameraState.micMuted, displayConfig: s.displayConfig.copyWith(audioMuted: primaryDisplay.audioMuted || s.displayConfig.audioMuted));
    }),
  ];

  Widget _buildGrid(BuildContext context, WidgetRef ref, MultiCamLayout layout, List<_FeedItem> feeds, String? selectedPeerId, bool showTelemetry, bool wideSplit) {
    Widget tileFor(int i) => i >= feeds.length
        ? _emptySlot(context, i + 1)
        : _CameraGridTile(
            key: ValueKey('cam-tile-${feeds[i].peerId ?? 'primary'}'),
            item: feeds[i],
            selected: feeds[i].peerId == selectedPeerId,
            showTelemetry: showTelemetry,
            onTap: () => ref.read(multiCamProvider.notifier).selectSlot(feeds[i].peerId),
            onDoubleTap: () {
              ref.read(multiCamProvider.notifier).selectSlot(feeds[i].peerId);
              ref.read(viewerDisplayProvider.notifier).toggleFullscreen();
            },
          );

    if (layout == .solo) {
      final idx = feeds.indexWhere((f) => f.peerId == selectedPeerId);
      return tileFor(idx >= 0 ? idx : 0);
    }
    if (layout == .split2) {
      final sec = selectedPeerId != null ? feeds.indexWhere((f) => f.peerId == selectedPeerId) : 1;
      final children = [Expanded(child: tileFor(0)), Expanded(child: tileFor(sec > 0 ? sec : 1))];
      return wideSplit ? Row(spacing: 10, children: children) : Column(spacing: 10, children: children);
    }
    return Column(
      spacing: 10,
      children: [
        Expanded(child: Row(spacing: 10, children: [Expanded(child: tileFor(0)), Expanded(child: tileFor(1))])),
        Expanded(child: Row(spacing: 10, children: [Expanded(child: tileFor(2)), Expanded(child: tileFor(3))])),
      ],
    );
  }

  Widget _emptySlot(BuildContext context, int slotNumber) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(color: colors.surfaceContainer.withValues(alpha: 0.5), borderRadius: .circular(14), border: Border.all(color: colors.outlineVariant)),
      child: Center(
        child: Column(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Icon(Icons.videocam_outlined, size: 28, color: colors.onSurfaceVariant),
            Text('Camera $slotNumber Slot Ready', style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant, fontWeight: .w600)),
          ],
        ),
      ),
    );
  }
}

class const _FeedItem({
  required final String? peerId,
  required final int slotNumber,
  required final String label,
  required final MediaStream? stream,
  required final StreamTelemetry telemetry,
  required final bool micMuted,
  required final ViewerDisplayConfig displayConfig,
});

class const _CameraGridTile({
  super.key,
  required final _FeedItem item,
  required final bool selected,
  required final bool showTelemetry,
  required final VoidCallback onTap,
  required final VoidCallback onDoubleTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.cyanAccent : Theme.of(context).colorScheme.outlineVariant;
    return GestureDetector(
      behavior: .opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(borderRadius: .circular(14), border: Border.all(color: borderColor, width: selected ? 2.5 : 1)),
        child: Stack(
          fit: .expand,
          children: [
            VideoStageWidget(stream: item.stream, displayConfig: item.displayConfig, borderRadius: 12, waitingLabel: 'Connecting ${item.label}...'),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: IgnorePointer(
                child: Wrap(
                  alignment: .spaceBetween,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const .symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundDark.withValues(alpha: 0.78),
                        borderRadius: .circular(999),
                        border: Border.all(color: selected ? AppColors.cyanAccent.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.16)),
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 6,
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: selected ? AppColors.cyanAccent : AppColors.accentGreen, shape: .circle)),
                          Text('Cam ${item.slotNumber} • ${item.label}', overflow: .ellipsis, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 11, fontWeight: .w600)),
                          if (item.micMuted) const Icon(Icons.mic_off_rounded, size: 12, color: AppColors.accentOrange),
                        ],
                      ),
                    ),
                    if (showTelemetry) TelemetryOverlay(telemetry: item.telemetry),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
