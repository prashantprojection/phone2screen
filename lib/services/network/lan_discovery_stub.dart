import 'dart:async';

import '../../models/discovered_peer.dart';
import '../../models/signaling_data.dart';

/// Web stub: browsers cannot open raw UDP sockets for LAN discovery.
class LanDiscoveryImpl {
  final _peersController = StreamController<List<DiscoveredPeer>>.broadcast();

  Stream<List<DiscoveredPeer>> get peersStream => _peersController.stream;

  List<DiscoveredPeer> get currentPeers => const [];

  Future<void> startBroadcasting(SignalingData hostInfo) async {}

  Future<void> stopBroadcasting() async {}

  Future<void> startListening() async {}

  Future<void> stopListening() async {}

  Future<void> dispose() async {
    await _peersController.close();
  }
}
