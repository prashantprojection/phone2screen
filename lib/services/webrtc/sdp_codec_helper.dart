/// Reorders payload types on the SDP `m=video` line to place H.264 first.
///
/// Prioritizing H.264 steers WebRTC toward hardware MediaCodec offload on
/// Tier-3 low-end phones, avoiding CPU/thermal overload from VP8/VP9 software
/// encoding.
String prioritizeH264InSdp(String sdp) {
  if (sdp.isEmpty) return sdp;
  final lineEnding = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(lineEnding);

  var mVideoIndex = -1;
  var videoEndIndex = lines.length;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('m=video ')) {
      mVideoIndex = i;
    } else if (mVideoIndex != -1 && lines[i].startsWith('m=')) {
      videoEndIndex = i;
      break;
    }
  }
  if (mVideoIndex == -1) return sdp;

  final h264Pts = <String>{};
  final rtpmapRegex = RegExp(r'^a=rtpmap:(\d+)\s+([A-Za-z0-9-]+)\/');
  for (var i = mVideoIndex + 1; i < videoEndIndex; i++) {
    final match = rtpmapRegex.firstMatch(lines[i]);
    if (match != null && match.group(2)?.toUpperCase() == 'H264') {
      h264Pts.add(match.group(1)!);
    }
  }
  if (h264Pts.isEmpty) return sdp;

  final parts = lines[mVideoIndex].split(' ');
  if (parts.length <= 3) return sdp;

  final preferred = <String>[];
  final remaining = <String>[];
  for (final pt in parts.sublist(3)) {
    (h264Pts.contains(pt) ? preferred : remaining).add(pt);
  }
  if (preferred.isEmpty) return sdp;

  lines[mVideoIndex] = [
    ...parts.sublist(0, 3),
    ...preferred,
    ...remaining,
  ].join(' ');
  return lines.join(lineEnding);
}
