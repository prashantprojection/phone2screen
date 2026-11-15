/// Network, discovery, signaling, and WebRTC defaults for Phone2Screen v0.1.
abstract final class StreamConstants {
  // Embedded HTTP static viewer + WebSocket signaling port range
  static const int defaultSignalingPort = 8080;
  static const int maxSignalingPort = 8095;

  // Embedded HTTPS companion port range (unlocks browser getUserMedia on LAN)
  static const int defaultHttpsPort = 8443;
  static const int maxHttpsPort = 8458;

  // LAN UDP broadcast discovery
  static const int udpDiscoveryPort = 41234;
  static const String discoveryMagic = 'P2S_V1';
  static const Duration discoveryInterval = Duration(seconds: 2);
  static const Duration peerStaleTimeout = Duration(seconds: 8);

  // Signaling, DataChannel control, and session guardrails
  static const String controlChannelLabel = 'phone2screen-control';
  static const Duration connectionTimeout = Duration(seconds: 20);
  static const Duration pingInterval = Duration(seconds: 1);
  static const int maxActivePeers = 1;
  static const int maxDesktopReceiverPeers = 4;
  static const String obsCleanFeedPath = '/obs';

  // Video resolution presets
  static const int width720p = 1280;
  static const int height720p = 720;
  static const int width1080p = 1920;
  static const int height1080p = 1080;
  static const int width4K = 3840;
  static const int height4K = 2160;

  // Frame rate and bitrate defaults (bps)
  static const int fps30 = 30;
  static const int fps60 = 60;
  static const int videoBitrate720p = 2_000_000;
  static const int videoBitrate1080p = 3_500_000;
  static const int videoBitrate4K = 8_000_000;
  static const int audioBitrate = 128_000;
  static const int defaultVideoBitrate = videoBitrate1080p;
  static const int minVideoBitrate = 500_000;
  static const int maxVideoBitrate = 25_000_000;

  // Fallback STUN servers for ICE candidate gathering
  static const List<String> stunServers = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
  ];
}
