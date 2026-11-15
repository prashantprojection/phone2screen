import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import '../../models/discovered_peer.dart';
import '../../models/signaling_data.dart';

/// Native `dart:io` implementation of UDP port 41234 (`P2S_V1`) LAN discovery.
class LanDiscoveryImpl {
  final _peersController = StreamController<List<DiscoveredPeer>>.broadcast();
  final Map<String, DiscoveredPeer> _peers = {};

  RawDatagramSocket? _broadcastSocket;
  Timer? _broadcastTimer;
  String? _broadcastingSessionId;

  RawDatagramSocket? _listenSocket;
  StreamSubscription<RawSocketEvent>? _listenSub;
  Timer? _pruneTimer;
  bool _disposed = false;

  Stream<List<DiscoveredPeer>> get peersStream => _peersController.stream;

  List<DiscoveredPeer> get currentPeers {
    final sorted = _peers.values.toList()
      ..sort((a, b) {
        final nameCmp = a.endpoint.deviceName.compareTo(b.endpoint.deviceName);
        if (nameCmp != 0) return nameCmp;
        return a.endpoint.ip.compareTo(b.endpoint.ip);
      });
    return List.unmodifiable(sorted);
  }

  Future<void> startBroadcasting(SignalingData hostInfo) async {
    if (_disposed) return;
    await stopBroadcasting();
    if (_disposed) return;

    RawDatagramSocket socket;
    try {
      // Bind an ephemeral source port so broadcasting never contends with the
      // discovery listener on UDP 41234.
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
    } catch (_) {
      return;
    }

    if (_disposed) {
      socket.close();
      return;
    }

    _broadcastSocket = socket;
    _broadcastingSessionId = hostInfo.sessionId;

    final packet = utf8.encode(
      jsonEncode({
        'magic': StreamConstants.discoveryMagic,
        ...hostInfo.toJson(),
      }),
    );
    final targets = await _resolveBroadcastTargets(hostInfo.ip);
    if (_disposed || _broadcastSocket != socket) return;

    // Emit one beacon immediately so waiting senders don't stall for 2s.
    _sendPacket(socket, packet, targets);
    _broadcastTimer = Timer.periodic(
      StreamConstants.discoveryInterval,
      (_) => _sendPacket(socket, packet, targets),
    );
  }

  Future<void> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _broadcastingSessionId = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
  }

  Future<void> startListening() async {
    if (_disposed || _listenSocket != null) return;

    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        StreamConstants.udpDiscoveryPort,
        reuseAddress: true,
      );
    } on SocketException {
      // Fail softly when another local process already holds UDP 41234.
      return;
    } catch (_) {
      return;
    }

    if (_disposed) {
      socket.close();
      return;
    }

    _listenSocket = socket;
    _listenSub = socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          _drainDatagrams(socket);
        }
      },
      onError: (_) => unawaited(stopListening()),
      onDone: () {
        if (_listenSocket == socket) {
          _listenSocket = null;
        }
      },
    );

    _pruneTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pruneStalePeers(),
    );
  }

  Future<void> stopListening() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _listenSub?.cancel();
    _listenSub = null;
    _listenSocket?.close();
    _listenSocket = null;
    if (_peers.isNotEmpty) {
      _peers.clear();
      _emitPeers();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopBroadcasting();
    await stopListening();
    await _peersController.close();
  }

  void _sendPacket(
    RawDatagramSocket socket,
    List<int> packet,
    List<InternetAddress> targets,
  ) {
    if (_disposed || _broadcastSocket != socket) return;
    for (final target in targets) {
      try {
        socket.send(packet, target, StreamConstants.udpDiscoveryPort);
      } catch (_) {
        // Ignore single-subnet send failures so other broadcast targets succeed.
      }
    }
  }

  Future<List<InternetAddress>> _resolveBroadcastTargets(String hostIp) async {
    final ips = <String>{'255.255.255.255'};
    final hostBroadcast = _toSlash24Broadcast(hostIp);
    if (hostBroadcast != null) ips.add(hostBroadcast);

    // Also probe active /24 subnets because mobile hotspots & Windows multi-NIC
    // hosts sometimes drop limited 255.255.255.255 broadcasts across interfaces.
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final subnetBroadcast = _toSlash24Broadcast(addr.address);
          if (subnetBroadcast != null) ips.add(subnetBroadcast);
        }
      }
    } catch (_) {
      // Proceed with 255.255.255.255 and host subnet if enumeration fails.
    }

    return [for (final ip in ips) InternetAddress(ip)];
  }

  String? _toSlash24Broadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if (a == null || b == null || c == null || d == null) return null;
    if (a == 0 || a == 127 || (a == 169 && b == 254)) return null;
    return '$a.$b.$c.255';
  }

  void _drainDatagrams(RawDatagramSocket socket) {
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      _handleDatagram(datagram);
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['magic'] != StreamConstants.discoveryMagic) return;

      final payloadIp = decoded['ip'];
      if (payloadIp is! String || payloadIp.isEmpty || payloadIp == '0.0.0.0') {
        decoded['ip'] = datagram.address.address;
      }

      final endpoint = SignalingData.fromJson(decoded);
      // Skip beacons originating from this own service instance's active host session.
      if (_broadcastingSessionId != null &&
          endpoint.sessionId == _broadcastingSessionId) {
        return;
      }

      final key = '${endpoint.ip}:${endpoint.port}';
      _peers[key] = DiscoveredPeer(
        endpoint: endpoint,
        lastSeen: DateTime.now(),
      );
      _emitPeers();
    } catch (_) {
      // Ignore malformed or foreign UDP datagrams on port 41234.
    }
  }

  void _pruneStalePeers() {
    if (_disposed || _peers.isEmpty) return;
    final now = DateTime.now();
    var removed = false;
    _peers.removeWhere((_, peer) {
      final stale =
          now.difference(peer.lastSeen) > StreamConstants.peerStaleTimeout;
      if (stale) removed = true;
      return stale;
    });
    if (removed) _emitPeers();
  }

  void _emitPeers() {
    if (_disposed || _peersController.isClosed) return;
    _peersController.add(currentPeers);
  }
}
