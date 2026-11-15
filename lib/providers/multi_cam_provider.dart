import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/camera_control_state.dart';
import '../models/camera_feed_slot.dart';
import '../models/device_role.dart';
import '../models/signaling_message.dart';
import '../models/viewer_display_config.dart';
import '../services/signaling/signaling_server_service.dart';
import '../services/webrtc/webrtc_session_service.dart';
import '../services/windowing/desktop_window_service.dart';
import 'discovery_provider.dart';
import 'platform_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

/// Singleton registry managing auxiliary desktop receiver windows.
final desktopWindowServiceProvider = Provider<DesktopWindowService>((ref) {
  final service = DesktopWindowService();
  ref.onDispose(service.dispose);
  return service;
});

/// Factory creating an isolated [WebRtcSessionService] per secondary camera.
final multiCamWebRtcFactoryProvider =
    Provider<WebRtcSessionService Function(String peerId)>(
      (ref) => (_) => WebRtcSessionService(),
    );

/// Runtime multi-camera grid, selected camera, and desktop child window state.
class const MultiCamState({
  final Map<String, CameraFeedSlot> secondarySlots = const {},
  final MultiCamLayout layout = .solo,
  final String? selectedPeerId,
  final List<DesktopWindowEntry> childWindows = const [],
  final bool layoutUserPinned = false,
}) {
  MultiCamState copyWith({
    Map<String, CameraFeedSlot>? secondarySlots,
    MultiCamLayout? layout,
    String? selectedPeerId,
    bool clearSelectedPeer = false,
    List<DesktopWindowEntry>? childWindows,
    bool? layoutUserPinned,
  }) => MultiCamState(
    secondarySlots: secondarySlots ?? this.secondarySlots,
    layout: layout ?? this.layout,
    selectedPeerId: clearSelectedPeer ? null : (selectedPeerId ?? this.selectedPeerId),
    childWindows: childWindows ?? this.childWindows,
    layoutUserPinned: layoutUserPinned ?? this.layoutUserPinned,
  );
}

/// Manages secondary WebRTC camera feeds (Camera 2..4) and desktop child windows.
final multiCamProvider = NotifierProvider<MultiCamNotifier, MultiCamState>(
  MultiCamNotifier.new,
);

/// Coordinates isolated secondary peer connections, layout auto-upgrade, and
/// remote camera / framing dispatch for multi-camera Receiver mode.
class MultiCamNotifier extends Notifier<MultiCamState> {
  final Map<String, WebRtcSessionService> _peerWebRtc = {};
  final Map<String, List<StreamSubscription<dynamic>>> _peerSubs = {};
  final Map<String, String> _peerSessionIds = {};
  final List<StreamSubscription<dynamic>> _hubSubs = [];

  @override
  MultiCamState build() {
    final server = ref.watch(signalingServerServiceProvider);
    final windowService = ref.watch(desktopWindowServiceProvider);
    _hubSubs.addAll([
      server.peerConnectionEvents.listen((e) => _onPeerConnectionEvent(server, e)),
      server.peerMessages.listen((e) => unawaited(_onPeerMessage(server, e))),
      windowService.windowsStream.listen(_onWindowsUpdated),
    ]);
    ref.listen<DeviceRole>(activeRoleProvider, (prev, next) {
      if (prev != null && prev != next && next != .receiver) unawaited(_clearAllSecondaryPeers());
    });
    ref.onDispose(_disposeAll);
    return MultiCamState(childWindows: windowService.activeWindows);
  }

  /// Selects primary (`null`) or a secondary camera slot by [peerId].
  void selectSlot(String? peerId) {
    final resolved = peerId != null && state.secondarySlots.containsKey(peerId) ? peerId : null;
    state = state.copyWith(selectedPeerId: resolved, clearSelectedPeer: resolved == null);
  }

  /// Pins the multi-camera stage layout to [layout] until feeds return to zero.
  void setLayout(MultiCamLayout layout) =>
      state = state.copyWith(layout: layout, layoutUserPinned: true);

  /// Updates the per-camera [ViewerDisplayConfig] for secondary [peerId].
  void updateSecondaryDisplay(
    String peerId,
    ViewerDisplayConfig Function(ViewerDisplayConfig) update,
  ) {
    if (!state.secondarySlots.containsKey(peerId)) return;
    _updateSlot(peerId, (s) => s.copyWith(displayConfig: update(s.displayConfig)));
  }

  /// Sends a `cam_ctrl` DataChannel command to secondary camera [peerId].
  bool sendSecondaryCameraCommand(String peerId, RemoteCameraCommand cmd) =>
      _peerWebRtc[peerId]?.sendCameraCommand(cmd) ?? false;

  /// Launches an auxiliary desktop camera receiver window on the next free slot.
  Future<DesktopWindowEntry?> openCameraWindow({bool cleanFeed = false}) async {
    final basePort = ref.read(sessionProvider).activeEndpoint?.port ??
        ref.read(appSettingsProvider).preferredPort;
    final service = ref.read(desktopWindowServiceProvider);
    final entry = await service.openCameraWindow(basePort: basePort, cleanFeed: cleanFeed);
    if (ref.mounted) state = state.copyWith(childWindows: service.activeWindows);
    return entry;
  }

  /// Closes the auxiliary desktop camera window occupying [slot].
  Future<bool> closeCameraWindow(int slot) async {
    final service = ref.read(desktopWindowServiceProvider);
    final closed = await service.closeWindow(slot);
    if (ref.mounted) state = state.copyWith(childWindows: service.activeWindows);
    return closed;
  }

  /// Disconnects all active secondary peers while keeping primary hosting intact.
  Future<void> disconnectAll() async {
    final server = ref.read(signalingServerServiceProvider);
    final peerIds = state.secondarySlots.keys.toList();
    await _clearAllSecondaryPeers();
    for (final peerId in peerIds) {
      await server.disconnectClient('Host ended session', peerId);
    }
  }

  void _onWindowsUpdated(List<DesktopWindowEntry> windows) {
    if (ref.mounted) state = state.copyWith(childWindows: windows);
  }

  void _onPeerConnectionEvent(SignalingServerService server, PeerConnectionEvent event) {
    if (event.isPrimary || !ref.mounted) return;
    if (!event.connected) {
      unawaited(_removeSecondaryPeer(event.peerId));
      return;
    }
    _ensurePeerWebRtc(server, event.peerId, deviceName: event.deviceName);
  }

  Future<void> _onPeerMessage(SignalingServerService server, PeerSignalingEvent event) async {
    if (event.isPrimary || !ref.mounted) return;
    final peerId = event.peerId;
    final msg = event.message;
    _peerSessionIds[peerId] = msg.sessionId;

    switch (msg.type) {
      case .hello:
        final rawName = (msg.payload['deviceName'] as String?)?.trim();
        _ensurePeerWebRtc(server, peerId, deviceName: rawName);
        if (rawName != null && rawName.isNotEmpty) _updateSlot(peerId, (s) => s.copyWith(deviceName: rawName));
      case .offer:
        final sdp = msg.payload['sdp'] as String?;
        final type = (msg.payload['type'] as String?) ?? 'offer';
        if (sdp == null || sdp.isEmpty) return;
        final rtc = _ensurePeerWebRtc(server, peerId);
        final answer = await rtc.acceptOfferAndCreateAnswer(RTCSessionDescription(sdp, type));
        if (!ref.mounted || _peerWebRtc[peerId] != rtc) return;
        server.send(SignalingMessage(type: .answer, sessionId: msg.sessionId, payload: {'sdp': answer.sdp, 'type': answer.type}), peerId: peerId);
      case .ice:
        final rtc = _peerWebRtc[peerId];
        final candidate = msg.payload['candidate'] as String?;
        if (rtc == null || candidate == null || candidate.isEmpty) return;
        await rtc.addRemoteIceCandidate(
          RTCIceCandidate(candidate, msg.payload['sdpMid'] as String?, (msg.payload['sdpMLineIndex'] as num?)?.toInt()),
        );
      case .bye:
        await _removeSecondaryPeer(peerId);
      case .welcome || .answer || .error:
        break;
    }
  }

  WebRtcSessionService _ensurePeerWebRtc(SignalingServerService server, String peerId, {String? deviceName}) {
    final existing = _peerWebRtc[peerId];
    if (existing != null) return existing;

    final rtc = ref.read(multiCamWebRtcFactoryProvider)(peerId);
    _peerWebRtc[peerId] = rtc;
    _peerSubs[peerId] = [
      rtc.onLocalIceCandidate.listen((c) {
        final sid = _peerSessionIds[peerId] ?? ref.read(sessionProvider).activeEndpoint?.sessionId;
        if (sid == null || _peerWebRtc[peerId] != rtc) return;
        server.send(
          SignalingMessage(type: .ice, sessionId: sid, payload: {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}),
          peerId: peerId,
        );
      }),
      rtc.onRemoteStream.listen((s) => _updateSlot(peerId, (slot) => slot.copyWith(stream: s))),
      rtc.telemetryStream.listen((t) => _updateSlot(peerId, (slot) => slot.copyWith(telemetry: t))),
      rtc.incomingCameraStates.listen((cam) => _updateSlot(peerId, (slot) => slot.copyWith(cameraState: cam))),
      rtc.onConnectionState.listen((s) {
        if ((s == .RTCPeerConnectionStateFailed || s == .RTCPeerConnectionStateClosed) && _peerWebRtc[peerId] == rtc) {
          unawaited(_removeSecondaryPeer(peerId));
        }
      }),
    ];

    final cleanName = deviceName?.trim();
    final label = (cleanName != null && cleanName.isNotEmpty) ? cleanName : 'Camera ${state.secondarySlots.length + 2}';
    final updated = Map<String, CameraFeedSlot>.of(state.secondarySlots)
      ..[peerId] = CameraFeedSlot(peerId: peerId, deviceName: label);
    state = state.copyWith(secondarySlots: Map.unmodifiable(updated), layout: _autoLayoutForCount(updated.length));
    return rtc;
  }

  void _updateSlot(String peerId, CameraFeedSlot Function(CameraFeedSlot) fn) {
    if (!ref.mounted) return;
    final current = state.secondarySlots[peerId];
    if (current == null) return;
    final updated = Map<String, CameraFeedSlot>.of(state.secondarySlots)..[peerId] = fn(current);
    state = state.copyWith(secondarySlots: Map.unmodifiable(updated));
  }

  Future<void> _removeSecondaryPeer(String peerId) async {
    final subs = _peerSubs.remove(peerId);
    final rtc = _peerWebRtc.remove(peerId);
    _peerSessionIds.remove(peerId);
    if (subs != null) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
    await rtc?.dispose();
    if (!ref.mounted || !state.secondarySlots.containsKey(peerId)) return;

    final updated = Map<String, CameraFeedSlot>.of(state.secondarySlots)..remove(peerId);
    final empty = updated.isEmpty;
    state = state.copyWith(
      secondarySlots: Map.unmodifiable(updated),
      clearSelectedPeer: state.selectedPeerId == peerId,
      layout: empty ? .solo : _autoLayoutForCount(updated.length),
      layoutUserPinned: empty ? false : state.layoutUserPinned,
    );
  }

  MultiCamLayout _autoLayoutForCount(int count) =>
      count <= 0 ? .solo : (state.layoutUserPinned ? state.layout : (count == 1 ? .split2 : .grid4));

  Future<void> _clearAllSecondaryPeers() async {
    for (final id in _peerWebRtc.keys.toList()) {
      await _removeSecondaryPeer(id);
    }
    if (ref.mounted && state.secondarySlots.isNotEmpty) {
      state = state.copyWith(secondarySlots: const {}, layout: .solo, clearSelectedPeer: true, layoutUserPinned: false);
    }
  }

  void _disposeAll() {
    for (final sub in _hubSubs.toList()) {
      unawaited(sub.cancel());
    }
    _hubSubs.clear();
    for (final sub in _peerSubs.values.expand((e) => e).toList()) {
      unawaited(sub.cancel());
    }
    _peerSubs.clear();
    for (final rtc in _peerWebRtc.values.toList()) {
      unawaited(rtc.dispose());
    }
    _peerWebRtc.clear();
    _peerSessionIds.clear();
  }
}
