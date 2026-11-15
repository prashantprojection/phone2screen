/// Active runtime role for this device in a Phone2Screen session.
enum DeviceRole {
  receiver,
  sender;

  String get label => switch (this) {
    .receiver => 'Receiver',
    .sender => 'Sender',
  };

  String get subtitle => switch (this) {
    .receiver => 'Receive and display incoming phone streams',
    .sender => 'Stream camera or screen to a desktop or browser',
  };
}
