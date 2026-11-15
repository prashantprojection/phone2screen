import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/camera_control_state.dart';
import '../../models/shortcut_config.dart';
import '../../providers/multi_cam_provider.dart';
import '../../providers/platform_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/shortcut_provider.dart';
import '../../providers/viewer_display_provider.dart';
import '../receiver/widgets/remote_camera_panel.dart';
import 'clipboard_sync_sheet.dart';
import 'how_to_use_sheet.dart';

/// Global keyboard shortcut dispatcher wrapping the primary app shell.
class const KeyboardShortcutsScope({
  super.key,
  required final Widget child,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<KeyboardShortcutsScope> createState() =>
      _KeyboardShortcutsScopeState();
}

class _KeyboardShortcutsScopeState
    extends ConsumerState<KeyboardShortcutsScope> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (ref.read(isRecordingShortcutProvider)) return false;

    // Defer to pushed routes, dialogs, and modal sheets so they handle Esc and keys.
    final isHomeTop = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isHomeTop) return false;

    final activeRole = ref.read(activeRoleProvider);
    final display = ref.read(viewerDisplayProvider);
    final displayNotifier = ref.read(viewerDisplayProvider.notifier);

    // Keep Esc active to exit fullscreen even when shortcuts are disabled.
    if (event.logicalKey == .escape &&
        activeRole == .receiver &&
        display.isFullscreen) {
      displayNotifier.setFullscreen(false);
      return true;
    }

    // Never intercept keystrokes while typing inside an editable text field.
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null &&
        focusCtx.mounted &&
        (focusCtx.widget is EditableText ||
            focusCtx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }

    final shortcuts = ref.read(shortcutProvider);
    final hardware = HardwareKeyboard.instance;
    final matched = shortcuts.matchEvent(
      event,
      ctrl: hardware.isControlPressed,
      shift: hardware.isShiftPressed,
      alt: hardware.isAltPressed,
    );
    if (matched == null) return false;

    return _dispatchAction(matched);
  }

  bool _dispatchAction(ShortcutAction action) {
    final activeRole = ref.read(activeRoleProvider);
    final phase = ref.read(sessionProvider).phase;
    final display = ref.read(viewerDisplayProvider);
    final displayNotifier = ref.read(viewerDisplayProvider.notifier);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final hasMultiCam = ref.read(multiCamProvider).secondarySlots.isNotEmpty;
    final isReceiver = activeRole == .receiver;
    final isPrimaryActive =
        phase == .streaming || phase == .connecting || phase == .reconnecting;
    final isSessionActive = isPrimaryActive || (isReceiver && hasMultiCam);

    switch (action) {
      case .toggleFullscreen:
        if (!isReceiver || !isSessionActive) return false;
        displayNotifier.toggleFullscreen();
        return true;
      case .toggleFullscreenHud:
        if (!isReceiver || !display.isFullscreen) return false;
        displayNotifier.toggleFullscreenHud();
        return true;
      case .toggleMute:
        if (isReceiver && isSessionActive) {
          displayNotifier.toggleMute();
          return true;
        }
        if (activeRole == .sender && phase == .streaming) {
          sessionNotifier.toggleMicMute();
          return true;
        }
        return false;
      case .rotateVideo:
        if (!isReceiver || !isSessionActive) return false;
        displayNotifier.rotate90();
        return true;
      case .toggleMirror:
        if (!isReceiver || !isSessionActive) return false;
        displayNotifier.toggleMirror();
        return true;
      case .toggleFit:
        if (!isReceiver || !isSessionActive) return false;
        displayNotifier.toggleFit();
        return true;
      case .toggleStats:
        if (!isReceiver) return false;
        displayNotifier.toggleTelemetry();
        return true;
      case .openClipboard:
        if (phase != .streaming) return false;
        ClipboardSyncSheet.show(context);
        return true;
      case .openGuide:
        HowToUseSheet.show(context);
        return true;
      case .openCameraRig:
        if (!isReceiver || !isSessionActive) return false;
        RemoteCameraPanel.show(context);
        return true;
      case .disconnectStream:
        if (!isSessionActive) return false;
        if (isPrimaryActive || activeRole == .sender) {
          sessionNotifier.disconnect();
        } else {
          ref.read(multiCamProvider.notifier).disconnectAll();
        }
        return true;
      case .toggleVideoPause:
        if (isReceiver && isSessionActive) {
          displayNotifier.toggleVideoPause();
          if (isPrimaryActive) {
            sessionNotifier.sendRemoteCameraCommand(
              RemoteCameraCommand(
                command: .videoPause,
                enabled: !display.isVideoPaused,
              ),
            );
          }
          return true;
        }
        if (activeRole == .sender && phase == .streaming) {
          sessionNotifier.toggleVideoPause();
          return true;
        }
        return false;
      case .cycleBackgroundBlur:
        if (!isReceiver || !isSessionActive) return false;
        displayNotifier.cycleBokehMode();
        return true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
