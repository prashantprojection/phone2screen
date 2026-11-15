import 'signaling_data.dart';

/// LAN peer discovered via UDP broadcast and tracked for staleness.
class const DiscoveredPeer({
  required final SignalingData endpoint,
  required final DateTime lastSeen,
});
