import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/audio_routing_config.dart';
import '../windowing/windows_studio_service.dart';

/// Discovers audio output devices (including Virtual Audio Cables) and routes
/// WebRTC remote audio output and per-stream playback gain safely.
class AudioRoutingService {
  AudioRoutingService({WindowsStudioService? windowsStudio})
    : _windowsStudio = windowsStudio ?? WindowsStudioService();

  final WindowsStudioService _windowsStudio;

  /// Lists available audio output endpoints, falling back to Win32 WaveOut
  /// device enumeration on Windows when WebRTC returns none.
  Future<List<AudioEndpointDevice>> listAudioOutputs() async {
    final devices = <AudioEndpointDevice>[];
    final seenIds = <String>{};

    try {
      final enumerated = await navigator.mediaDevices.enumerateDevices();
      for (final device in enumerated) {
        if (device.kind != 'audiooutput') continue;
        final id = device.deviceId.trim();
        if (id.isEmpty || !seenIds.add(id)) continue;
        final rawLabel = device.label.trim();
        final label = rawLabel.isNotEmpty ? rawLabel : 'Audio Output ($id)';
        devices.add(
          AudioEndpointDevice(
            id: id,
            label: label,
            isVirtualCable: AudioEndpointDevice.detectVirtualCableLabel(label),
          ),
        );
      }
    } catch (_) {
      // Ignore platforms or headless test environments without WebRTC devices.
    }

    if (devices.isEmpty && _windowsStudio.isSupported) {
      final winDevices = await _windowsStudio.listAudioOutputDevices();
      for (final d in winDevices) {
        if (d.id.isEmpty || !seenIds.add(d.id)) continue;
        devices.add(
          AudioEndpointDevice(
            id: d.id,
            label: d.name,
            isVirtualCable:
                d.isVirtualCable ||
                AudioEndpointDevice.detectVirtualCableLabel(d.name),
          ),
        );
      }
    }

    if (devices.isNotEmpty && !seenIds.contains('default')) {
      devices.insert(
        0,
        const AudioEndpointDevice(id: 'default', label: 'System Default'),
      );
    }

    return List.unmodifiable(devices);
  }

  /// Routes WebRTC audio playback to [deviceId] (or `'default'` when null).
  Future<bool> selectOutputDevice(String? deviceId) async {
    final targetId = (deviceId == null || deviceId.trim().isEmpty)
        ? 'default'
        : deviceId.trim();
    try {
      await Helper.selectAudioOutput(targetId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Updates audio track enablement and playback volume (`0.0..2.0`).
  Future<void> applyStreamGain(
    MediaStream? stream, {
    required bool muted,
    required double gain,
  }) async {
    if (stream == null) return;
    final volume = muted ? 0.0 : gain.clamp(0.0, 2.0).toDouble();
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
      if (!kIsWeb) {
        try {
          await Helper.setVolume(volume, track);
        } catch (_) {
          // Ignore platforms or track implementations without volume control.
        }
      }
    }
  }
}
