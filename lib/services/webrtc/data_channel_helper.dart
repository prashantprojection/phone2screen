import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/camera_control_state.dart';
import '../../models/clipboard_item.dart';

/// Manages the `phone2screen-control` WebRTC DataChannel for `ping`/`pong` RTT,
/// bidirectional clipboard synchronization, and remote camera control frames.
class DataChannelHelper {
  final StreamController<ClipboardItem> _clipboardController =
      StreamController<ClipboardItem>.broadcast();
  final StreamController<RemoteCameraCommand> _cameraCmdController =
      StreamController<RemoteCameraCommand>.broadcast();
  final StreamController<RemoteCameraState> _cameraStateController =
      StreamController<RemoteCameraState>.broadcast();
  final StreamController<void> _channelOpenController =
      StreamController<void>.broadcast();

  RTCDataChannel? _channel;
  int _lastLatencyMs = 0;
  bool _isOpen = false;
  bool _disposed = false;

  /// Stream of remote clipboard items received over the control channel.
  Stream<ClipboardItem> get incomingClipboard => _clipboardController.stream;

  /// Stream of remote camera control commands (`cam_ctrl`) from the viewer.
  Stream<RemoteCameraCommand> get incomingCameraCommands =>
      _cameraCmdController.stream;

  /// Stream of authoritative camera hardware state (`cam_state`) snapshots.
  Stream<RemoteCameraState> get incomingCameraStates =>
      _cameraStateController.stream;

  /// Emits when the control DataChannel opens so peers can push initial state.
  Stream<void> get onChannelOpen => _channelOpenController.stream;

  /// Latest measured round-trip latency in milliseconds (`0` before first pong).
  int get lastLatencyMs => _lastLatencyMs;

  /// True when the control DataChannel is open for sending JSON frames.
  bool get isOpen => _isOpen;

  /// Attaches an ordered `phone2screen-control` DataChannel to this helper.
  void attach(RTCDataChannel channel) {
    if (_disposed) return;
    _channel = channel;
    final initiallyOpen =
        channel.state == RTCDataChannelState.RTCDataChannelOpen;
    _isOpen = initiallyOpen;
    channel.onDataChannelState = (state) {
      if (_channel != channel || _disposed) return;
      final becameOpen =
          !_isOpen && state == RTCDataChannelState.RTCDataChannelOpen;
      _isOpen = state == RTCDataChannelState.RTCDataChannelOpen;
      if (becameOpen) _channelOpenController.add(null);
    };
    channel.onMessage = (message) {
      if (_channel == channel && !_disposed) _handleMessage(message);
    };
    if (initiallyOpen) _channelOpenController.add(null);
  }

  /// Sends a 1Hz heartbeat `ping` frame when the DataChannel is open.
  void sendPing() {
    if (!_isOpen) return;
    _sendJson({
      'kind': 'ping',
      'ts': DateTime.now().millisecondsSinceEpoch,
      if (_lastLatencyMs > 0) 'rtt': _lastLatencyMs,
    });
  }

  /// Sends clipboard text across the control DataChannel if open.
  bool sendClipboard(String text) {
    if (!_isOpen || _channel == null || text.isEmpty) return false;
    return _sendJson({
      'kind': 'clipboard',
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Sends a remote camera control command (`cam_ctrl`) from Receiver to Sender.
  bool sendCameraCommand(RemoteCameraCommand cmd) => _sendJson(cmd.toJson());

  /// Broadcasts authoritative camera hardware state (`cam_state`) to Receiver.
  bool sendCameraState(RemoteCameraState state) => _sendJson(state.toJson());

  void _handleMessage(RTCDataChannelMessage message) {
    if (message.isBinary) return;
    try {
      final decoded = jsonDecode(message.text);
      if (decoded is! Map<String, dynamic>) return;
      final kind = decoded['kind'];
      if (kind == 'ping') {
        // Echo timestamp immediately so the peer measures clock-skew-free RTT.
        _sendJson({'kind': 'pong', 'ts': decoded['ts']});
        final peerRtt = _asInt(decoded['rtt']);
        if (_lastLatencyMs == 0 && peerRtt > 0) _lastLatencyMs = peerRtt;
      } else if (kind == 'pong') {
        final sentTs = _asInt(decoded['ts']);
        if (sentTs > 0) {
          final now = DateTime.now().millisecondsSinceEpoch;
          _lastLatencyMs = (now - sentTs).clamp(0, 9999);
        }
      } else if (kind == 'clipboard') {
        final text = decoded['text'];
        if (text is String && text.isNotEmpty && !_disposed) {
          final tsMs = _asInt(decoded['ts']);
          final timestamp = tsMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(tsMs)
              : DateTime.now();
          _clipboardController.add(
            ClipboardItem(text: text, timestamp: timestamp, fromRemote: true),
          );
        }
      } else if (kind == 'cam_ctrl') {
        // Forward viewer camera rig requests so the active Sender applies them locally.
        final cmd = RemoteCameraCommand.tryFromJson(decoded);
        if (cmd != null && !_disposed) _cameraCmdController.add(cmd);
      } else if (kind == 'cam_state') {
        // Sync Sender hardware state back to Receiver so HUD controls stay truthful.
        final state = RemoteCameraState.tryFromJson(decoded);
        if (state != null && !_disposed) _cameraStateController.add(state);
      }
    } catch (_) {
      // Ignore malformed DataChannel payloads rather than dropping the stream.
    }
  }

  bool _sendJson(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || !_isOpen) return false;
    try {
      channel.send(RTCDataChannelMessage(jsonEncode(payload)));
      return true;
    } catch (_) {
      return false;
    }
  }

  static int _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => num.tryParse(v)?.round() ?? 0,
    _ => 0,
  };

  /// Closes the active DataChannel and resets RTT state for the next peer.
  Future<void> reset() async {
    _isOpen = false;
    _lastLatencyMs = 0;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.close();
      } catch (_) {}
    }
  }

  /// Disposes DataChannel resources and closes stream controllers permanently.
  Future<void> dispose() async {
    _disposed = true;
    await reset();
    await _clipboardController.close();
    await _cameraCmdController.close();
    await _cameraStateController.close();
    await _channelOpenController.close();
  }
}
