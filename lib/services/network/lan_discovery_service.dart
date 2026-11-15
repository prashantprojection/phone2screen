import '../../models/discovered_peer.dart';
import '../../models/signaling_data.dart';
import 'lan_discovery_stub.dart'
    if (dart.library.io) 'lan_discovery_io.dart'
    as impl;

/// Broadcasts host presence and discovers LAN receivers over UDP port 41234.
class LanDiscoveryService {
  LanDiscoveryService() : _impl = impl.LanDiscoveryImpl();

  final impl.LanDiscoveryImpl _impl;

  /// Broadcast stream emitting updated snapshots of active LAN receivers.
  Stream<List<DiscoveredPeer>> get peersStream => _impl.peersStream;

  /// Snapshot of currently active (non-stale) discovered LAN peers.
  List<DiscoveredPeer> get currentPeers => _impl.currentPeers;

  /// Starts periodic `P2S_V1` UDP beacon broadcasts for [hostInfo].
  Future<void> startBroadcasting(SignalingData hostInfo) =>
      _impl.startBroadcasting(hostInfo);

  /// Stops UDP discovery broadcasts.
  Future<void> stopBroadcasting() => _impl.stopBroadcasting();

  /// Starts listening for `P2S_V1` UDP beacons and pruning stale peers.
  Future<void> startListening() => _impl.startListening();

  /// Stops listening for UDP beacons and clears cached peers.
  Future<void> stopListening() => _impl.stopListening();

  /// Releases all sockets, timers, and stream controllers.
  Future<void> dispose() => _impl.dispose();
}
