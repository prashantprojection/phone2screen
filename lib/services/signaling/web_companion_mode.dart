/// Operating mode for the embedded `GET /` Browser Web Companion page.
enum WebCompanionMode {
  /// Browser acts as WebRTC Sender casting camera/screen to this Receiver.
  sendToReceiver,

  /// Browser acts as WebRTC Viewer watching this Sender's live stream.
  viewSenderStream,
}
