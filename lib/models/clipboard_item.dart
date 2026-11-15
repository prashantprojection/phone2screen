/// Text payload exchanged between peers over the WebRTC control DataChannel.
class const ClipboardItem({
  required final String text,
  required final DateTime timestamp,
  required final bool fromRemote,
});
