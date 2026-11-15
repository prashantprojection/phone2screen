import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/camera_control_state.dart';
import '../../../models/stream_telemetry.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/shortcut_provider.dart';
import '../../../providers/virtual_cam_provider.dart';
import '../../shared/clipboard_sync_sheet.dart';
import '../../shared/video_stage_widget.dart';
import 'remote_camera_panel.dart';
import 'telemetry_overlay.dart';

/// Immersive fullscreen receiver stage with toggleable HUD controls.
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
    final multiCam = ref.watch(multiCamProvider);
    final slot = multiCam.selectedPeerId != null ? multiCam.secondarySlots[multiCam.selectedPeerId] : null;
    final activeStream = slot?.stream ?? widget.session.remoteStream;
    final activeDisplay = (slot?.displayConfig ?? widget.display).copyWith(
      isFullscreen: true,
      fullscreenHudVisible: widget.display.fullscreenHudVisible,
      audioMuted: widget.display.audioMuted || (slot?.displayConfig.audioMuted ?? false),
    );
    final activeTelemetry = slot?.telemetry ?? widget.session.telemetry;
    final peerName = slot?.deviceName ?? widget.session.connectedPeerName;
    final effectivePaused = slot != null
        ? (slot.displayConfig.isVideoPaused || slot.cameraState.videoPaused)
        : (widget.display.isVideoPaused || widget.session.remoteCameraState.videoPaused);
    final vcamNotifier = ref.watch(nativeVirtualCamProvider.notifier);

    final videoWidget = VideoStageWidget(
      stream: activeStream,
      displayConfig: activeDisplay,
      isPaused: effectivePaused,
      borderRadius: 0,
      waitingLabel: waitingLabel,
    );
    final stage = slot == null
        ? RepaintBoundary(key: vcamNotifier.stageBoundaryKey, child: videoWidget)
        : videoWidget;
    final compactCollision = context.isCompact && widget.display.fullscreenHudVisible && (widget.display.showTelemetry || peerName != null);
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
                child: stage,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: widget.display.fullscreenHudVisible
                  ? _buildHudOverlay(peerName, activeTelemetry)
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

  Widget _buildHudOverlay(String? peerName, StreamTelemetry telemetry) => SafeArea(
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
                  widget.display.showTelemetry ? TelemetryOverlay(telemetry: telemetry) : const SizedBox.shrink(),
                  if (peerName != null) _peerPill(peerName),
                ],
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _FullscreenHudPill(display: widget.display, onExitFullscreen: widget.onExitFullscreen)),
        ],
      ),
    ),
  );

  Widget _peerPill(String name) => _frostedPill(
    radius: 999,
    padding: const .symmetric(horizontal: 12, vertical: 6),
    alpha: 0.78,
    child: Row(
      mainAxisSize: .min,
      spacing: 7,
      children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: .circle)),
        const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.primaryLight),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(name, overflow: .ellipsis, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 12, fontWeight: .w600))),
      ],
    ),
  );

  Widget _escHintToast() => _frostedPill(
    radius: 16,
    padding: const .symmetric(horizontal: 16, vertical: 10),
    alpha: 0.78,
    shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 20, offset: const Offset(0, 6))],
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

Widget _frostedPill({required double radius, required EdgeInsetsGeometry padding, double alpha = 0.78, List<BoxShadow>? shadows, required Widget child}) {
  final glass = ClipRRect(
    borderRadius: .circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF121418).withValues(alpha: alpha),
          borderRadius: .circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: child,
      ),
    ),
  );
  if (shadows == null) return glass;
  return DecoratedBox(
    decoration: BoxDecoration(borderRadius: .circular(radius), boxShadow: shadows),
    child: glass,
  );
}

class const _FullscreenHudPill({required final ViewerDisplayConfig display, required final VoidCallback onExitFullscreen}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(viewerDisplayProvider.notifier);
    final shortcuts = ref.watch(shortcutProvider);
    final isPaused = display.isVideoPaused || ref.watch(sessionProvider.select((s) => s.remoteCameraState.videoPaused));
    return Material(
      type: .transparency,
      child: _frostedPill(
        radius: 999,
        padding: const .symmetric(horizontal: 10, vertical: 6),
        alpha: 0.78,
        shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 24, offset: const Offset(0, 8))],
        child: SingleChildScrollView(
          scrollDirection: .horizontal,
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              _hudBtn(display.coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded, shortcuts.tooltipFor(display.coverFit ? 'Fit Screen' : 'Fill Screen', .toggleFit), notifier.toggleFit, active: display.coverFit),
              _hudBtn(Icons.rotate_right_rounded, shortcuts.tooltipFor('Rotate 90°', .rotateVideo), notifier.rotate90, active: display.quarterTurns % 4 != 0),
              _hudBtn(Icons.flip_rounded, shortcuts.tooltipFor('Mirror', .toggleMirror), notifier.toggleMirror, active: display.mirrored),
              _hudBtn(isPaused ? Icons.videocam_off_rounded : Icons.pause_circle_outline_rounded, shortcuts.tooltipFor(isPaused ? 'Resume Camera' : 'Pause Camera', .toggleVideoPause), () {
                final next = !isPaused;
                notifier.setVideoPaused(next);
                ref.read(sessionProvider.notifier).sendRemoteCameraCommand(RemoteCameraCommand(command: .videoPause, enabled: next));
              }, active: isPaused, accent: isPaused ? AppColors.accentOrange : null),
              _hudBtn(Icons.tune_rounded, shortcuts.tooltipFor('Camera Rig & Color', .openCameraRig), () => RemoteCameraPanel.show(context), active: display.hasColorAdjustments || display.hasFramingAdjustments),
              _hudBtn(display.audioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, shortcuts.tooltipFor(display.audioMuted ? 'Unmute' : 'Mute', .toggleMute), notifier.toggleMute, accent: display.audioMuted ? AppColors.accentOrange : null),
              _hudBtn(Icons.content_paste_go_rounded, shortcuts.tooltipFor('Share Text', .openClipboard), () => ClipboardSyncSheet.show(context)),
              _hudBtn(Icons.speed_rounded, shortcuts.tooltipFor('Live Stats', .toggleStats), notifier.toggleTelemetry, active: display.showTelemetry),
              Container(width: 1, height: 22, margin: const .symmetric(horizontal: 2), color: Colors.white.withValues(alpha: 0.16)),
              _hudPillBtn('Hide Controls', Icons.visibility_off_outlined, shortcuts.tooltipFor('Hide Controls', .toggleFullscreenHud), notifier.toggleFullscreenHud, border: Colors.white.withValues(alpha: 0.22)),
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
        color: tone != null ? tone.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: .circular(999), side: BorderSide(color: tone != null ? tone.withValues(alpha: 0.50) : Colors.white.withValues(alpha: 0.12))),
        clipBehavior: .antiAlias,
        child: InkWell(onTap: onTap, child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: tone ?? AppColors.textPrimaryDark))),
      ),
    );
  }

  Widget _hudPillBtn(String label, IconData icon, String tip, VoidCallback onTap, {Color? bg, Color? border}) => Tooltip(
    message: tip,
    child: FilledButton.tonalIcon(
      onPressed: onTap,
      style: FilledButton.styleFrom(backgroundColor: bg ?? Colors.transparent, foregroundColor: AppColors.textPrimaryDark, side: border != null ? BorderSide(color: border) : null, minimumSize: const Size(0, 38), padding: const .symmetric(horizontal: 14), shape: const StadiumBorder()),
      icon: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}
