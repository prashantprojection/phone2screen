import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/constants/stream_constants.dart';
import '../../models/camera_control_state.dart';
import '../../models/clipboard_item.dart';
import '../../models/obs_sync_state.dart';
import '../../models/stream_telemetry.dart';
import 'data_channel_helper.dart';
import 'rtc_stats_sampler.dart';
import 'sdp_codec_helper.dart';

/// Manages WebRTC [RTCPeerConnection], H.264 SDP priority munging, early ICE
/// buffering, track replacement, bitrate caps, and control DataChannel sync.
class WebRtcSessionService {
  final DataChannelHelper _dataChannelHelper;
  final RtcStatsSampler _statsSampler;

  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<MediaStream> _remoteStreamController =
      StreamController<MediaStream>.broadcast();
  final StreamController<RTCPeerConnectionState> _stateController =
      StreamController<RTCPeerConnectionState>.broadcast();

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  RTCPeerConnection? _peerConnection;
  RTCRtpSender? _videoSender;
  MediaStream? _remoteStream;
  bool _remoteDescriptionSet = false;
  int _targetBitrateBps = StreamConstants.defaultVideoBitrate;
  bool _isSender = false;
  bool _disposed = false;

  /// Creates a [WebRtcSessionService] with optional helper overrides.
  WebRtcSessionService({
    DataChannelHelper? dataChannelHelper,
    RtcStatsSampler? statsSampler,
  }) : _dataChannelHelper = dataChannelHelper ?? DataChannelHelper(),
       _statsSampler = statsSampler ?? RtcStatsSampler();

  /// Emits gathered local ICE candidates to forward over signaling.
  Stream<RTCIceCandidate> get onLocalIceCandidate => _iceController.stream;

  /// Emits remote [MediaStream] when incoming media tracks arrive.
  Stream<MediaStream> get onRemoteStream => _remoteStreamController.stream;

  /// Emits peer connection lifecycle transitions.
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _stateController.stream;

  /// Emits 1Hz RTT, bitrate, resolution, fps, and duration telemetry updates.
  Stream<StreamTelemetry> get telemetryStream => _statsSampler.stream;

  /// Emits clipboard payloads received from the remote peer.
  Stream<ClipboardItem> get incomingClipboard =>
      _dataChannelHelper.incomingClipboard;

  /// Emits remote camera control commands (`cam_ctrl`) received from viewer.
  Stream<RemoteCameraCommand> get incomingCameraCommands =>
      _dataChannelHelper.incomingCameraCommands;

  /// Emits authoritative camera state (`cam_state`) snapshots from broadcaster.
  Stream<RemoteCameraState> get incomingCameraStates =>
      _dataChannelHelper.incomingCameraStates;

  /// Emits live OBS tally updates (`tally`) received from the host Receiver.
  Stream<LiveTallyMessage> get incomingTally =>
      _dataChannelHelper.incomingTally;

  /// Emits when the `phone2screen-control` DataChannel transitions to open.
  Stream<void> get onControlChannelOpen => _dataChannelHelper.onChannelOpen;

  /// Sender flow: creates peer connection, opens control DataChannel, adds
  /// tracks from [localStream], prefers H.264, and returns local SDP offer.
  Future<RTCSessionDescription> createOfferForStream(
    MediaStream localStream, {
    required int maxBitrateBps,
  }) async {
    await close();
    _isSender = true;
    _targetBitrateBps = maxBitrateBps;

    final pc = await _createConfiguredPeerConnection();
    final dcInit = RTCDataChannelInit()..ordered = true;
    final channel = await pc.createDataChannel(
      StreamConstants.controlChannelLabel,
      dcInit,
    );
    _dataChannelHelper.attach(channel);

    for (final track in localStream.getTracks()) {
      final sender = await pc.addTrack(track, localStream);
      if (track.kind == 'video') _videoSender = sender;
    }

    final rawOffer = await pc.createOffer();
    final mungedOffer = RTCSessionDescription(
      preferH264Codec(rawOffer.sdp ?? ''),
      rawOffer.type,
    );
    await pc.setLocalDescription(mungedOffer);
    await applyBitrateLimit(maxBitrateBps);
    return mungedOffer;
  }

  /// Receiver flow: applies remote [offer], flushes early buffered ICE
  /// candidates, prefers H.264, and returns local SDP answer.
  Future<RTCSessionDescription> acceptOfferAndCreateAnswer(
    RTCSessionDescription offer,
  ) async {
    await close();
    _isSender = false;

    final pc = await _createConfiguredPeerConnection();
    await pc.setRemoteDescription(offer);
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates(pc);

    final rawAnswer = await pc.createAnswer();
    final mungedAnswer = RTCSessionDescription(
      preferH264Codec(rawAnswer.sdp ?? ''),
      rawAnswer.type,
    );
    await pc.setLocalDescription(mungedAnswer);
    return mungedAnswer;
  }

  /// Sender flow: applies remote SDP [answer] and flushes buffered ICE.
  Future<void> applyRemoteAnswer(RTCSessionDescription answer) async {
    final pc = _peerConnection;
    if (pc == null) return;
    await pc.setRemoteDescription(answer);
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates(pc);
    await applyBitrateLimit(_targetBitrateBps);
  }

  /// Adds a remote ICE candidate immediately, or queues it until
  /// `setRemoteDescription` finishes so early trickle ICE never fails.
  Future<void> addRemoteIceCandidate(RTCIceCandidate candidate) async {
    final pc = _peerConnection;
    if (pc == null || !_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (_) {
      // Ignore late or incompatible candidates on closing connections.
    }
  }

  /// Swaps the outgoing video track in-place without renegotiating SDP.
  Future<void> replaceVideoTrack(MediaStreamTrack track) async {
    if (_videoSender != null) {
      await _videoSender!.replaceTrack(track);
      return;
    }
    final pc = _peerConnection;
    if (pc == null) return;
    for (final sender in await pc.getSenders()) {
      if (sender.track?.kind == 'video') {
        _videoSender = sender;
        await sender.replaceTrack(track);
        return;
      }
    }
  }

  /// Applies [bps] max bitrate cap to the active video [RTCRtpSender].
  Future<void> applyBitrateLimit(int bps) async {
    _targetBitrateBps = bps;
    final sender = _videoSender;
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) {
        params.encodings = [RTCRtpEncoding(maxBitrate: bps)];
      } else {
        for (final encoding in encodings) {
          encoding.maxBitrate = bps;
        }
      }
      await sender.setParameters(params);
    } catch (_) {
      // Platforms may defer setParameters until DTLS/ICE setup finishes.
    }
  }

  /// Sends clipboard text across the `phone2screen-control` DataChannel.
  bool sendClipboard(String text) => _dataChannelHelper.sendClipboard(text);

  /// Sends a remote camera command (`cam_ctrl`) across the control channel.
  bool sendCameraCommand(RemoteCameraCommand cmd) =>
      _dataChannelHelper.sendCameraCommand(cmd);

  /// Sends authoritative camera state (`cam_state`) across the control channel.
  bool sendCameraState(RemoteCameraState state) =>
      _dataChannelHelper.sendCameraState(state);

  /// Sends a live OBS tally update (`tally`) across the control channel.
  bool sendTally(LiveTallyMessage tally) => _dataChannelHelper.sendTally(tally);

  /// Reorders payload types on `m=video` to prioritize hardware H.264.
  String preferH264Codec(String sdp) => prioritizeH264InSdp(sdp);

  Future<RTCPeerConnection> _createConfiguredPeerConnection() async {
    final pc = await createPeerConnection({
      'iceServers': [
        for (final server in StreamConstants.stunServers) {'urls': server},
      ],
      'sdpSemantics': 'unified-plan',
    });
    _peerConnection = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null &&
          candidate.candidate!.isNotEmpty &&
          !_disposed) {
        _iceController.add(candidate);
      }
    };
    pc.onDataChannel = _dataChannelHelper.attach;
    pc.onTrack = (event) async {
      if (_disposed) return;
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream!);
        return;
      }
      _remoteStream ??= await createLocalMediaStream('remote');
      await _remoteStream!.addTrack(event.track);
      _remoteStreamController.add(_remoteStream!);
    };
    pc.onAddStream = (stream) {
      if (_disposed) return;
      _remoteStream = stream;
      _remoteStreamController.add(stream);
    };
    pc.onConnectionState = (state) {
      if (_disposed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _statsSampler.start(
          pc,
          isSender: _isSender,
          readDataChannelRttMs: () => _dataChannelHelper.lastLatencyMs,
          onTick: _dataChannelHelper.sendPing,
        );
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _statsSampler.stop();
      }
      _stateController.add(state);
    };
    return pc;
  }

  Future<void> _flushPendingIceCandidates(RTCPeerConnection pc) async {
    if (_pendingRemoteCandidates.isEmpty) return;
    final buffered = List<RTCIceCandidate>.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in buffered) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {}
    }
  }

  /// Closes active peer connection and clears ICE buffer for the next session.
  Future<void> close() async {
    _pendingRemoteCandidates.clear();
    _remoteDescriptionSet = false;
    _videoSender = null;
    _remoteStream = null;
    _statsSampler.stop();
    await _dataChannelHelper.reset();

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
  }

  /// Permanently tears down the service and closes all broadcast streams.
  Future<void> dispose() async {
    _disposed = true;
    await close();
    await _statsSampler.dispose();
    await _dataChannelHelper.dispose();
    await _iceController.close();
    await _remoteStreamController.close();
    await _stateController.close();
  }
}
