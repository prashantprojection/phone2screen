import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';
import '../../shared/video_stage_widget.dart';
import 'telemetry_overlay.dart';

/// Immersive fullscreen receiver video stage with toggleable overlay controls.
class const FullscreenStageView({
  super.key,
  required final SessionState session,
  required final ViewerDisplayConfig display,
  required final VoidCallback onExitFullscreen,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<FullscreenStageView> createState() => _FullscreenStageViewState();
}

class _FullscreenStageViewState extends ConsumerState<FullscreenStageView> {
  bool _showEscToast = true;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _showEscToast = true;
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEscToast = false);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingLabel = switch (widget.session.phase) {
      .connecting => 'Connecting live video...',
      .reconnecting => 'Reconnecting to sender...',
      _ => 'Waiting for video stream...',
    };
    final peerName = widget.session.connectedPeerName;
    final compactCollision = context.isCompact &&
        widget.display.fullscreenHudVisible &&
        (widget.display.showTelemetry || peerName != null);

    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: .expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: .opaque,
                onTap: () => ref.read(viewerDisplayProvider.notifier).toggleFullscreenHud(),
                child: VideoStageWidget(
                  stream: widget.session.remoteStream,
                  displayConfig: widget.display,
                  borderRadius: 0,
                  waitingLabel: waitingLabel,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: widget.display.fullscreenHudVisible
                  ? _buildHudOverlay(peerName)
                  : const SizedBox.shrink(key: ValueKey('fullscreen-hud-hidden')),
            ),
            IgnorePointer(
              child: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _showEscToast
                      ? Align(
                          key: const ValueKey('esc-toast-visible'),
                          alignment: Alignment.topCenter,
                          child: Padding(padding: .fromLTRB(16, compactCollision ? 64 : 16, 16, 0), child: _escHintToast()),
                        )
                      : const SizedBox.shrink(key: ValueKey('esc-toast-hidden')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudOverlay(String? peerName) => SafeArea(
    key: const ValueKey('fullscreen-hud-visible'),
    child: Padding(
      padding: const .all(16),
      child: Stack(
        fit: .expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Wrap(
                alignment: .spaceBetween,
                spacing: 8,
                runSpacing: 8,
                children: [
                  widget.display.showTelemetry ? TelemetryOverlay(telemetry: widget.session.telemetry) : const SizedBox.shrink(),
                  if (peerName != null) _peerPill(peerName),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _FullscreenHudPill(display: widget.display, onExitFullscreen: widget.onExitFullscreen),
          ),
        ],
      ),
    ),
  );

  Widget _peerPill(String name) => _frostedPill(
    radius: 999,
    padding: const .symmetric(horizontal: 12, vertical: 6),
    alpha: 0.72,
    child: Row(
      mainAxisSize: .min,
      spacing: 7,
      children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: .circle)),
        const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.primaryLight),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(name, overflow: .ellipsis, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 12, fontWeight: .w600)),
        ),
      ],
    ),
  );

  Widget _escHintToast() => _frostedPill(
    radius: 16,
    padding: const .symmetric(horizontal: 16, vertical: 10),
    alpha: 0.86,
    shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
    child: const Row(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        Icon(Icons.fullscreen_rounded, size: 20, color: AppColors.primaryLight),
        Flexible(
          child: Column(mainAxisSize: .min, crossAxisAlignment: .start, spacing: 2, children: [
            Text('Press Esc to exit fullscreen', style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 13, fontWeight: .w700)),
            Text('Tap anywhere to toggle controls', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 11, fontWeight: .w500)),
          ]),
        ),
      ],
    ),
  );
}

Widget _frostedPill({required double radius, required EdgeInsetsGeometry padding, required double alpha, List<BoxShadow>? shadows, required Widget child}) => ClipRRect(
  borderRadius: .circular(radius),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(color: AppColors.backgroundDark.withValues(alpha: alpha), borderRadius: .circular(radius), border: Border.all(color: Colors.white.withValues(alpha: 0.16)), boxShadow: shadows),
      child: child,
    ),
  ),
);

class const _FullscreenHudPill({required final ViewerDisplayConfig display, required final VoidCallback onExitFullscreen}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);
    final fitTip = shortcuts.tooltipFor(display.coverFit ? 'Fit Screen' : 'Fill Screen', .toggleFit);
    final muteTip = shortcuts.tooltipFor(display.audioMuted ? 'Unmute' : 'Mute', .toggleMute);

    return Material(
      type: .transparency,
      child: _frostedPill(
        radius: 20,
        padding: const .symmetric(horizontal: 10, vertical: 8),
        alpha: 0.80,
        shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 6))],
        child: SingleChildScrollView(
          scrollDirection: .horizontal,
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              _hudBtn(display.coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded, fitTip, notifier.toggleFit, active: display.coverFit),
              _hudBtn(Icons.rotate_right_rounded, shortcuts.tooltipFor('Rotate 90°', .rotateVideo), notifier.rotate90, active: display.quarterTurns % 4 != 0),
              _hudBtn(Icons.flip_rounded, shortcuts.tooltipFor('Mirror', .toggleMirror), notifier.toggleMirror, active: display.mirrored),
              _hudBtn(display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, muteTip, notifier.toggleMute, accent: display.audioMuted ? AppColors.accentOrange : null),
              _hudBtn(Icons.content_paste_go_rounded, shortcuts.tooltipFor('Share Text', .openClipboard), () => ClipboardSyncSheet.show(context)),
              _hudBtn(Icons.speed_rounded, shortcuts.tooltipFor('Live Stats', .toggleStats), notifier.toggleTelemetry, active: display.showTelemetry),
              Container(width: 1, height: 22, margin: const .symmetric(horizontal: 2), color: Colors.white.withValues(alpha: 0.18)),
              _hudPillBtn('Hide Controls', Icons.visibility_off_outlined, shortcuts.tooltipFor('Hide Controls', .toggleFullscreenHud), notifier.toggleFullscreenHud, border: Colors.white.withValues(alpha: 0.24)),
              _hudPillBtn('Exit Fullscreen', Icons.fullscreen_exit_rounded, 'Exit Fullscreen (Esc)', onExitFullscreen, bg: Colors.white.withValues(alpha: 0.16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hudBtn(IconData icon, String tip, VoidCallback onTap, {bool active = false, Color? accent}) {
    final tone = accent ?? (active ? AppColors.primaryLight : null);
    return Tooltip(
      message: tip,
      child: Material(
        color: tone != null ? tone.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: .circular(11), side: BorderSide(color: tone != null ? tone.withValues(alpha: 0.52) : Colors.white.withValues(alpha: 0.14))),
        clipBehavior: .antiAlias,
        child: InkWell(onTap: onTap, child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: tone ?? AppColors.textPrimaryDark))),
      ),
    );
  }

  Widget _hudPillBtn(String label, IconData icon, String tip, VoidCallback onTap, {Color? bg, Color? border}) => Tooltip(
    message: tip,
    child: FilledButton.tonalIcon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: bg ?? Colors.transparent,
        foregroundColor: AppColors.textPrimaryDark,
        side: border != null ? BorderSide(color: border) : null,
        minimumSize: const Size(0, 38),
        padding: const .symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: .circular(12)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}
