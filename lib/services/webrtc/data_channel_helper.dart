import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/clipboard_item.dart';

/// Manages the `phone2screen-control` WebRTC DataChannel for `ping`/`pong` RTT
/// measurement and bidirectional clipboard synchronization.
class DataChannelHelper {
  final StreamController<ClipboardItem> _clipboardController =
      StreamController<ClipboardItem>.broadcast();

  RTCDataChannel? _channel;
  int _lastLatencyMs = 0;
  bool _isOpen = false;
  bool _disposed = false;

  /// Stream of remote clipboard items received over the control channel.
  Stream<ClipboardItem> get incomingClipboard => _clipboardController.stream;

  /// Latest measured round-trip latency in milliseconds (`0` before first pong).
  int get lastLatencyMs => _lastLatencyMs;

  /// True when the control DataChannel is open for sending JSON frames.
  bool get isOpen => _isOpen;

  /// Attaches an ordered `phone2screen-control` DataChannel to this helper.
  void attach(RTCDataChannel channel) {
    _channel = channel;
    _isOpen = channel.state == RTCDataChannelState.RTCDataChannelOpen;
    channel.onDataChannelState = (state) {
      _isOpen = state == RTCDataChannelState.RTCDataChannelOpen;
    };
    channel.onMessage = _handleMessage;
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
  }
}
