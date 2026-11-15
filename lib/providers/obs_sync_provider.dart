import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/stream_constants.dart';
import '../models/audio_routing_config.dart';
import '../models/camera_control_state.dart';
import '../models/obs_sync_state.dart';
import '../services/obs/obs_websocket_service.dart';
import '../services/webrtc/audio_routing_service.dart';
import '../services/windowing/windows_studio_service.dart';
import 'multi_cam_provider.dart';
import 'preferences_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

export '../models/audio_routing_config.dart';
export '../models/obs_sync_state.dart';
export '../services/windowing/windows_studio_service.dart' show VideoCaptureDeviceInfo;

/// Injectable Windows native DirectShow, WaveOut, and Always-On-Top bridge.
final windowsStudioServiceProvider = Provider<WindowsStudioService>((_) => WindowsStudioService());

/// Injectable OBS WebSocket v5 (`rpcVersion: 1`) client service.
final obsWebSocketServiceProvider = Provider<ObsWebSocketService>((ref) {
  final service = ObsWebSocketService();
  ref.onDispose(service.dispose);
  return service;
});

/// Injectable audio endpoint enumerator, output router, and stream gain helper.
final audioRoutingServiceProvider = Provider<AudioRoutingService>(
  (ref) => AudioRoutingService(windowsStudio: ref.watch(windowsStudioServiceProvider)),
);

/// Discovered DirectShow video capture devices (tagging virtual cameras).
final videoCaptureDevicesProvider = FutureProvider<List<VideoCaptureDeviceInfo>>(
  (ref) => ref.watch(windowsStudioServiceProvider).listVideoCaptureDevices(),
);

/// Discovered audio output endpoints (speakers, headsets, virtual cables).
final audioOutputsProvider = FutureProvider<List<AudioEndpointDevice>>(
  (ref) => ref.watch(audioRoutingServiceProvider).listAudioOutputs(),
);

/// Native Win32 Always-On-Top pin state for the desktop receiver window.
final alwaysOnTopProvider = NotifierProvider<AlwaysOnTopNotifier, bool>(AlwaysOnTopNotifier.new);

/// Queries and toggles native Win32 `WS_EX_TOPMOST` window pinning.
class AlwaysOnTopNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Refreshes pinned state from the native Windows window handle.
  Future<void> refresh() async {
    final active = await ref.read(windowsStudioServiceProvider).getAlwaysOnTop();
    if (ref.mounted) state = active;
  }

  /// Toggles Always-On-Top and updates state only when the native call succeeds.
  Future<void> toggle() async {
    final target = !state;
    final ok = await ref.read(windowsStudioServiceProvider).setAlwaysOnTop(target);
    if (ref.mounted && ok) state = target;
  }
}

/// Persistent studio audio routing, gain, lip-sync offset, and mic DSP state.
final audioStudioProvider = NotifierProvider<AudioStudioNotifier, AudioStudioConfig>(
  AudioStudioNotifier.new,
);

/// Manages audio output routing, gain, lip-sync delay, and Voice Clean mode.
class AudioStudioNotifier extends Notifier<AudioStudioConfig> {
  static const String _prefKey = 'audioStudio';

  @override
  AudioStudioConfig build() {
    final saved = ref.watch(localPreferencesServiceProvider).loadJsonSection(_prefKey);
    return saved == null ? const AudioStudioConfig() : AudioStudioConfig.fromJson(saved);
  }

  /// Selects an output endpoint ID (or system default when `null`/empty).
  Future<void> setOutputDevice(String? deviceId) async {
    final clean = (deviceId == null || deviceId.trim().isEmpty) ? null : deviceId.trim();
    state = state.copyWith(outputDeviceId: clean, clearOutputDevice: clean == null);
    await _persist();
    if (ref.mounted) await ref.read(audioRoutingServiceProvider).selectOutputDevice(clean);
  }

  /// Updates studio playback gain (`0.0..2.0`) and pushes to viewer & stream.
  Future<void> setGain(double gain) async {
    state = state.copyWith(gain: gain);
    ref.read(viewerDisplayProvider.notifier).setAudioGain(state.gain);
    await _persist();
    if (!ref.mounted) return;
    await ref.read(audioRoutingServiceProvider).applyStreamGain(
          ref.read(sessionProvider).remoteStream,
          muted: ref.read(viewerDisplayProvider).audioMuted,
          gain: state.gain,
        );
  }

  /// Updates lip-sync delay (`0..500` ms) and syncs to viewer & connected OBS.
  Future<void> setLipSyncDelayMs(int delayMs) async {
    state = state.copyWith(lipSyncDelayMs: delayMs);
    ref.read(viewerDisplayProvider.notifier).setAudioDelayMs(state.lipSyncDelayMs);
    await _persist();
    if (ref.mounted && ref.read(obsSyncProvider).connected) {
      await ref.read(obsSyncProvider.notifier).syncAudioDelay(state.lipSyncDelayMs);
    }
  }

  /// Switches mic DSP preset (`voiceClean` vs `studioRaw`) and syncs live peer.
  Future<void> setMicMode(MicProcessingMode mode) async {
    state = state.copyWith(micMode: mode);
    final voiceClean = mode == .voiceClean;
    ref.read(streamConfigProvider.notifier).setVoiceCleanAudio(voiceClean);
    await _persist();
    if (!ref.mounted) return;
    final session = ref.read(sessionProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    if (session.phase != .streaming && session.phase != .connecting) return;
    final cmd = RemoteCameraCommand(command: .voiceMode, enabled: voiceClean);
    if (sessionNotifier.isHosting && !session.isWebBroadcast) {
      final peerId = ref.read(multiCamProvider).selectedPeerId;
      if (peerId != null) {
        ref.read(multiCamProvider.notifier).sendSecondaryCameraCommand(peerId, cmd);
      } else {
        sessionNotifier.sendRemoteCameraCommand(cmd);
      }
    } else {
      await sessionNotifier.applyLocalCameraCommand(cmd);
    }
  }

  Future<void> _persist() =>
      ref.read(localPreferencesServiceProvider).saveJsonSection(_prefKey, state.toJson());
}

/// Persisted OBS Studio WebSocket v5 connection configuration provider.
final obsConfigProvider = NotifierProvider<ObsConfigNotifier, ObsConnectionConfig>(
  ObsConfigNotifier.new,
);

/// Manages and persists [ObsConnectionConfig] settings.
class ObsConfigNotifier extends Notifier<ObsConnectionConfig> {
  @override
  ObsConnectionConfig build() => ref.watch(localPreferencesServiceProvider).loadObsConfig();

  /// Replaces and persists the normalized [ObsConnectionConfig].
  Future<void> updateConfig(ObsConnectionConfig config) async {
    final trimmedHost = config.host.trim();
    final normalized = config.copyWith(
      host: trimmedHost.isEmpty ? '127.0.0.1' : trimmedHost,
      port: config.port.clamp(1, 65535),
      sourceFilter: config.sourceFilter.trim(),
    );
    state = normalized;
    await ref.read(localPreferencesServiceProvider).saveObsConfig(normalized);
  }

  Future<void> setHost(String host) => updateConfig(state.copyWith(host: host));
  Future<void> setPort(int port) => updateConfig(state.copyWith(port: port));
  Future<void> setPassword(String password) => updateConfig(state.copyWith(password: password));
  Future<void> setAutoConnect(bool autoConnect) => updateConfig(state.copyWith(autoConnect: autoConnect));
  Future<void> setSourceFilter(String filter) => updateConfig(state.copyWith(sourceFilter: filter));
}

/// Live OBS Studio connection, Virtual Camera, scene, and tally state provider.
final obsSyncProvider = NotifierProvider<ObsSyncNotifier, ObsSyncState>(ObsSyncNotifier.new);

/// Bridges [ObsWebSocketService] state updates into Live Tally DataChannel sync
/// and exposes Virtual Camera, Clean Feed provisioning, and audio delay RPCs.
class ObsSyncNotifier extends Notifier<ObsSyncState> {
  @override
  ObsSyncState build() {
    final service = ref.watch(obsWebSocketServiceProvider);
    final sub = service.stateStream.listen(_onServiceState);
    ref.onDispose(() => unawaited(sub.cancel()));
    return service.currentState;
  }

  void _onServiceState(ObsSyncState next) {
    if (!ref.mounted) return;
    final prev = state;
    state = next;
    if (next.connecting && !next.connected) return;
    final nextTally = LiveTallyMessage(
      state: next.tallyState == .off ? .program : next.tallyState,
      sceneName: next.programScene,
    );
    final prevTally = LiveTallyMessage(
      state: prev.tallyState == .off ? .program : prev.tallyState,
      sceneName: prev.programScene,
    );
    final justDisconnected = prev.connected && !next.connected;
    if ((next.connected || next.tallyState != .off || justDisconnected) &&
        (next.connected != prev.connected || nextTally != prevTally)) {
      ref.read(multiCamProvider.notifier).broadcastTally(
            nextTally,
            inactiveSlotTally: justDisconnected ? const LiveTallyMessage(state: .preview) : null,
          );
    }
  }

  /// Connects and authenticates with OBS WebSocket using [obsConfigProvider].
  Future<bool> connect() => ref.read(obsWebSocketServiceProvider).connect(ref.read(obsConfigProvider));

  /// Disconnects from OBS WebSocket and resets tally status.
  Future<void> disconnect() => ref.read(obsWebSocketServiceProvider).disconnect();

  /// Toggles OBS Virtual Camera on or off.
  Future<bool> toggleVirtualCam() => ref.read(obsWebSocketServiceProvider).toggleVirtualCam();

  /// Creates or updates the Phone2Screen Browser Source in the active OBS scene.
  Future<bool> provisionCleanFeed() {
    final service = ref.read(obsWebSocketServiceProvider);
    if (!state.connected && !service.isConnected) return Future.value(false);
    final session = ref.read(sessionProvider);
    final ep = session.activeEndpoint;
    final settings = ref.read(appSettingsProvider);
    final streamCfg = ref.read(streamConfigProvider);
    final delayMs = ref.read(audioStudioProvider).lipSyncDelayMs;
    final host = (ep != null && ep.ip.trim().isNotEmpty) ? ep.ip.trim() : '127.0.0.1';
    final port = ep?.port ?? (settings.preferredPort > 0 ? settings.preferredPort : StreamConstants.defaultSignalingPort);
    final pin = (ep?.requiresPin ?? settings.pin.trim().isNotEmpty) ? settings.pin.trim() : '';
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: StreamConstants.obsCleanFeedPath,
      queryParameters: pin.isNotEmpty ? {'pin': pin} : null,
    );
    return service.ensureBrowserSource(
      cleanFeedUrl: uri.toString(),
      width: streamCfg.width,
      height: streamCfg.height,
      audioDelayMs: delayMs,
    );
  }

  /// Applies [delayMs] (`0..500`) audio sync offset to the OBS Clean Feed input.
  Future<bool> syncAudioDelay(int delayMs) {
    final service = ref.read(obsWebSocketServiceProvider);
    if (!state.connected && !service.isConnected) return Future.value(false);
    return service.setAudioSyncOffset(delayMs: delayMs.clamp(0, 500));
  }
}
