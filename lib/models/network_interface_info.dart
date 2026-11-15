/// Local IPv4 network interface candidate discovered on the host device.
class const NetworkInterfaceInfo({
  required final String name,
  required final String address,
  final bool isPreferred = false,
  final bool isUsbTethered = false,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkInterfaceInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          address == other.address &&
          isPreferred == other.isPreferred &&
          isUsbTethered == other.isUsbTethered;

  @override
  int get hashCode => Object.hash(name, address, isPreferred, isUsbTethered);
}
