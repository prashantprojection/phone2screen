import 'dart:async';
import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/windowing/windows_studio_service.dart';
import 'obs_sync_provider.dart';

export '../services/windowing/windows_studio_service.dart'
    show NativeVirtualCamStatus;

/// Provider managing the zero-OBS native Windows DirectShow Virtual Camera.
final nativeVirtualCamProvider =
    NotifierProvider<NativeVirtualCamNotifier, NativeVirtualCamStatus>(
      NativeVirtualCamNotifier.new,
    );

/// Coordinates per-user DirectShow virtual cam registration, standby/privacy
/// slates, and 20 fps stage boundary frame pushes into `p2s_vcam.dll`.
class NativeVirtualCamNotifier extends Notifier<NativeVirtualCamStatus> {
  /// Attach to the active receiver stage `RepaintBoundary` to stream frames.
  final GlobalKey stageBoundaryKey = GlobalKey();

  Timer? _captureTimer;
  bool _captureInFlight = false;
  int _opEpoch = 0;

  bool get _isFlutterTest {
    if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
    try {
      return WidgetsBinding.instance is! WidgetsFlutterBinding;
    } catch (_) {
      return true;
    }
  }

  @override
  NativeVirtualCamStatus build() {
    final service = ref.watch(windowsStudioServiceProvider);
    ref.onDispose(_stopCaptureTimer);
    if (service.isSupported) {
      Future.microtask(refresh);
    }
    return NativeVirtualCamStatus(isSupported: service.isSupported);
  }

  /// Refreshes native DLL presence, HKCU registration, and shared-memory state.
  Future<NativeVirtualCamStatus> refresh() async {
    final epoch = ++_opEpoch;
    final service = ref.read(windowsStudioServiceProvider);
    if (!service.isSupported) {
      state = const NativeVirtualCamStatus();
      return state;
    }
    final status = await service.getVirtualCamStatus();
    if (ref.mounted && epoch == _opEpoch) {
      state = status;
    }
    return status;
  }

  /// Registers `p2s_vcam.dll` under HKCU and refreshes DirectShow device list.
  Future<bool> enable() async {
    ++_opEpoch;
    final service = ref.read(windowsStudioServiceProvider);
    if (!service.isSupported) return false;
    final ok = await service.registerVirtualCam();
    if (!ref.mounted) return ok;
    await refresh();
    if (ref.mounted) ref.invalidate(videoCaptureDevicesProvider);
    return ok;
  }

  /// Unregisters `p2s_vcam.dll` from HKCU and stops periodic frame pushing.
  Future<bool> disable() async {
    ++_opEpoch;
    _stopCaptureTimer();
    final service = ref.read(windowsStudioServiceProvider);
    if (!service.isSupported) return false;
    final ok = await service.unregisterVirtualCam();
    if (!ref.mounted) return ok;
    await refresh();
    if (ref.mounted) ref.invalidate(videoCaptureDevicesProvider);
    return ok;
  }

  /// Syncs virtual cam state (`0`=Standby, `1`=Streaming, `2`=Privacy Paused)
  /// and manages the 20 fps stage capture loop when registered.
  Future<void> syncStreamState({
    required bool isStreaming,
    required bool isPaused,
  }) async {
    ++_opEpoch;
    final service = ref.read(windowsStudioServiceProvider);
    final targetState = !isStreaming ? 0 : (isPaused ? 2 : 1);
    if (!service.isSupported || !state.isRegistered) {
      _stopCaptureTimer();
      return;
    }
    if (state.activeState != targetState) {
      state = state.copyWith(activeState: targetState);
    }
    if (targetState == 1) {
      await service.setVirtualCamState(1);
      if (!ref.mounted || state.activeState != 1) return;
      _startCaptureTimer();
      if (stageBoundaryKey.currentContext != null) {
        unawaited(captureStageFrameOnce());
      }
    } else {
      _stopCaptureTimer();
      await service.setVirtualCamState(targetState);
    }
  }

  /// Captures a single frame from [stageBoundaryKey] at ~640..960 px width and
  /// pushes raw RGBA8888 pixels to `StudioBridge` for bottom-up BGR24 output.
  Future<bool> captureStageFrameOnce() async {
    if (_captureInFlight) return false;
    final service = ref.read(windowsStudioServiceProvider);
    if (!service.isSupported || !state.isRegistered || state.isPaused) {
      return false;
    }
    final renderObject = stageBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return false;
    final size = renderObject.size;
    if (size.isEmpty || size.longestSide <= 0) return false;

    final pixelRatio = (800.0 / size.longestSide).clamp(0.25, 2.5);
    _captureInFlight = true;
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || !ref.mounted) return false;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return await service.pushVirtualCamFrame(
        rgbaBytes: bytes,
        width: image.width,
        height: image.height,
      );
    } finally {
      image?.dispose();
      _captureInFlight = false;
    }
  }

  void _startCaptureTimer() {
    if (_isFlutterTest) return;
    _captureTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => unawaited(captureStageFrameOnce()),
    );
  }

  void _stopCaptureTimer() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }
}
