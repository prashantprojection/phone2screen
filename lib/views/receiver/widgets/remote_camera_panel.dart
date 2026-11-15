import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../models/camera_control_state.dart';
import '../../../models/viewer_display_config.dart';
import '../../../providers/multi_cam_provider.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';

/// Studio modal for remote phone camera control, aspect framing, and GPU color.
class const RemoteCameraPanel({super.key}) extends ConsumerStatefulWidget {
  /// Presents the panel as a bottom sheet on phones or centered dialog on wide screens.
  static Future<void> show(BuildContext context) {
    if (context.isCompact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const RemoteCameraPanel(),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 740),
          child: const RemoteCameraPanel(),
        ),
      ),
    );
  }

  @override
  ConsumerState<RemoteCameraPanel> createState() => _RemoteCameraPanelState();
}

class _RemoteCameraPanelState extends ConsumerState<RemoteCameraPanel> {
  double? _pendingZoom;
  double? _pendingExposure;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final primaryDisplay = ref.watch(viewerDisplayProvider);
    final multiCam = ref.watch(multiCamProvider);
    final selectedSlot = multiCam.selectedPeerId != null
        ? multiCam.secondarySlots[multiCam.selectedPeerId]
        : null;
    final camState = selectedSlot?.cameraState ?? session.remoteCameraState;
    final display = selectedSlot?.displayConfig ?? primaryDisplay;
    final targetName =
        selectedSlot?.deviceName ?? (session.connectedPeerName ?? 'Primary Camera');
    final isPrimary = selectedSlot == null;

    void sendCmd(RemoteCameraCommand cmd) => isPrimary
        ? ref.read(sessionProvider.notifier).sendRemoteCameraCommand(cmd)
        : ref.read(multiCamProvider.notifier).sendSecondaryCameraCommand(selectedSlot.peerId, cmd);

    void updateSecondary(ViewerDisplayConfig Function(ViewerDisplayConfig) fn) =>
        ref.read(multiCamProvider.notifier).updateSecondaryDisplay(selectedSlot!.peerId, fn);

    final primaryNotifier = ref.read(viewerDisplayProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canHw = camState.controlsSupported;
    final canZoom = canHw && camState.maxZoom > camState.minZoom;
    final maxZoom = canZoom ? camState.maxZoom : camState.minZoom + 1.0;
    final zoomVal = (_pendingZoom ?? camState.zoom).clamp(camState.minZoom, maxZoom);
    final evVal = (_pendingExposure ?? camState.exposureOffset).clamp(-2.0, 2.0);

    final framingSliders = [
      ('Digital Zoom', '${display.digitalZoom.toStringAsFixed(2)}x', display.digitalZoom.clamp(1.0, 3.0), 1.0, 3.0, (double v) => isPrimary ? primaryNotifier.setDigitalZoom(v) : updateSecondary((c) => c.copyWith(digitalZoom: v))),
      ('Pan X', display.panX.toStringAsFixed(2), display.panX.clamp(-1.0, 1.0), -1.0, 1.0, (double v) => isPrimary ? primaryNotifier.setPan(v, display.panY) : updateSecondary((c) => c.copyWith(panX: v))),
      ('Pan Y', display.panY.toStringAsFixed(2), display.panY.clamp(-1.0, 1.0), -1.0, 1.0, (double v) => isPrimary ? primaryNotifier.setPan(display.panX, v) : updateSecondary((c) => c.copyWith(panY: v))),
      ('Brightness', display.brightness.toStringAsFixed(2), display.brightness.clamp(-0.5, 0.5), -0.5, 0.5, (double v) => isPrimary ? primaryNotifier.setBrightness(v) : updateSecondary((c) => c.copyWith(brightness: v))),
      ('Contrast', display.contrast.toStringAsFixed(2), display.contrast.clamp(0.5, 1.5), 0.5, 1.5, (double v) => isPrimary ? primaryNotifier.setContrast(v) : updateSecondary((c) => c.copyWith(contrast: v))),
      ('Saturation', display.saturation.toStringAsFixed(2), display.saturation.clamp(0.0, 2.0), 0.0, 2.0, (double v) => isPrimary ? primaryNotifier.setSaturation(v) : updateSecondary((c) => c.copyWith(saturation: v))),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          _buildHeader(theme, isPrimary, targetName),
          if (multiCam.secondarySlots.isNotEmpty)
            _buildTargetBar(session.connectedPeerName ?? 'Primary Camera', multiCam),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const .fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 12,
                children: [
                  _sectionTitle(theme, 'Remote Phone Camera Rig', canHw ? 'Controls phone lens, torch, zoom, and exposure live' : 'Hardware lens controls unavailable for screen/browser source'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _rigChip(colors, Icons.cameraswitch_rounded, 'Flip Lens', false, canHw, () => sendCmd(const RemoteCameraCommand(command: .flip))),
                      _rigChip(colors, Icons.flashlight_on_rounded, 'Torch', camState.torchOn, canHw, () => sendCmd(RemoteCameraCommand(command: .torch, enabled: !camState.torchOn))),
                      _rigChip(colors, camState.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded, 'Mic Mute', camState.micMuted, true, () => sendCmd(RemoteCameraCommand(command: .micMute, enabled: !camState.micMuted)), accent: AppColors.accentOrange),
                      _rigChip(colors, Icons.center_focus_strong_rounded, 'AF Lock', camState.focusLocked, canHw, () => sendCmd(RemoteCameraCommand(command: .focusLock, enabled: !camState.focusLocked))),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: .center,
                    children: [
                      Text('Zoom Presets', style: theme.textTheme.labelMedium),
                      for (final p in const [1.0, 2.0, 3.0])
                        ActionChip(
                          label: Text('${p.toInt()}x'),
                          backgroundColor: (zoomVal - p).abs() < 0.12 ? colors.primary.withValues(alpha: 0.18) : null,
                          onPressed: canZoom && p <= camState.maxZoom
                              ? () {
                                  setState(() => _pendingZoom = p);
                                  sendCmd(RemoteCameraCommand(command: .zoom, value: p));
                                }
                              : null,
                        ),
                    ],
                  ),
                  _slider(theme, 'Zoom', '${zoomVal.toStringAsFixed(1)}x', zoomVal, camState.minZoom, maxZoom,
                    onChanged: canZoom
                        ? (v) {
                            setState(() => _pendingZoom = v);
                            sendCmd(RemoteCameraCommand(command: .zoom, value: v));
                          }
                        : null,
                    onEnd: (_) => setState(() => _pendingZoom = null),
                  ),
                  _slider(theme, 'Exposure (EV)', '${evVal >= 0 ? '+' : ''}${evVal.toStringAsFixed(1)} EV', evVal, -2.0, 2.0,
                    divisions: 16,
                    onChanged: canHw
                        ? (v) {
                            setState(() => _pendingExposure = v);
                            sendCmd(RemoteCameraCommand(command: .exposure, value: v));
                          }
                        : null,
                    onEnd: (_) => setState(() => _pendingExposure = null),
                  ),
                  const Divider(height: 4),
                  Row(
                    mainAxisAlignment: .spaceBetween,
                    children: [
                      Expanded(child: _sectionTitle(theme, 'Studio Framing & GPU Color', 'Aspect crop, Rule-of-Thirds grid, pan & look')),
                      TextButton.icon(
                        onPressed: () => isPrimary
                            ? primaryNotifier.resetFramingAndColor()
                            : updateSecondary((c) => c.copyWith(aspectPreset: .free, digitalZoom: 1.0, panX: 0.0, panY: 0.0, brightness: 0.0, contrast: 1.0, saturation: 1.0)),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset Studio Look'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in AspectPreset.values)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: display.aspectPreset == preset,
                          showCheckmark: false,
                          onSelected: (_) => isPrimary
                              ? primaryNotifier.setAspectPreset(preset)
                              : updateSecondary((c) => c.copyWith(aspectPreset: preset)),
                        ),
                      FilterChip(
                        avatar: const Icon(Icons.grid_3x3_rounded, size: 16),
                        label: const Text('3x3 Grid'),
                        selected: display.showGrid,
                        onSelected: (v) => isPrimary
                            ? primaryNotifier.toggleGrid()
                            : updateSecondary((c) => c.copyWith(showGrid: v)),
                      ),
                    ],
                  ),
                  for (final s in framingSliders)
                    _slider(theme, s.$1, s.$2, s.$3, s.$4, s.$5, onChanged: s.$6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isPrimary, String targetName) => Padding(
    padding: const .fromLTRB(20, 14, 12, 8),
    child: Row(
      spacing: 10,
      children: [
        const Icon(Icons.tune_rounded, color: AppColors.cyanAccent),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text('Camera Rig & Studio Look', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
              Text('Target: ${isPrimary ? 'Primary Camera ($targetName)' : targetName}', overflow: .ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.cyanAccent, fontWeight: .w600)),
            ],
          ),
        ),
        IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
      ],
    ),
  );

  Widget _buildTargetBar(String primaryLabel, MultiCamState multiCam) {
    final slots = multiCam.secondarySlots.values.toList();
    return SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: const .fromLTRB(20, 4, 20, 10),
      child: Row(
        spacing: 8,
        children: [
          ChoiceChip(label: Text('Cam 1 • $primaryLabel'), selected: multiCam.selectedPeerId == null, onSelected: (_) => _selectTarget(null)),
          for (var i = 0; i < slots.length; i++)
            ChoiceChip(label: Text('Cam ${i + 2} • ${slots[i].deviceName}'), selected: multiCam.selectedPeerId == slots[i].peerId, onSelected: (_) => _selectTarget(slots[i].peerId)),
        ],
      ),
    );
  }

  void _selectTarget(String? id) {
    setState(() {
      _pendingZoom = null;
      _pendingExposure = null;
    });
    ref.read(multiCamProvider.notifier).selectSlot(id);
  }

  Widget _sectionTitle(ThemeData theme, String title, String subtitle) => Column(
    crossAxisAlignment: .start,
    spacing: 2,
    children: [
      Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w700)),
      Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ],
  );

  Widget _rigChip(ColorScheme colors, IconData icon, String label, bool active, bool enabled, VoidCallback onTap, {Color? accent}) {
    final tone = active ? (accent ?? colors.primary) : null;
    return FilterChip(
      avatar: Icon(icon, size: 17, color: tone),
      label: Text(label),
      selected: active,
      showCheckmark: false,
      selectedColor: tone?.withValues(alpha: 0.2),
      onSelected: enabled ? (_) => onTap() : null,
    );
  }

  Widget _slider(ThemeData theme, String label, String text, double value, double min, double max, {int? divisions, ValueChanged<double>? onChanged, ValueChanged<double>? onEnd}) => Column(
    mainAxisSize: .min,
    children: [
      Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: .w600)),
          Text(text, style: theme.textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
      Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onEnd),
    ],
  );
}
