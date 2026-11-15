import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../../models/network_interface_info.dart';

final RegExp _en0Pattern = RegExp(r'(^|[^a-z0-9])en0([^a-z0-9]|$)');
final RegExp _virtualTokenPattern = RegExp(
  r'(^|[^a-z0-9])(tun|tap|wg)[0-9]*([^a-z0-9]|$)',
);
final RegExp _ethernetPattern = RegExp(
  r'(^|[^a-z0-9])(eth\d*|ethernet|en\d+|eno\d+|enp\w*|ens\d+)([^a-z0-9]|$)',
);

/// Enumerates local IPv4 interfaces, filtering unusable addresses and ranking
/// physical RFC1918 Wi-Fi/Ethernet adapters above virtual tunnels.
Future<List<NetworkInterfaceInfo>> listInterfaces() async {
  String? wifiIp;
  try {
    final raw = await NetworkInfo().getWifiIP();
    if (raw != null && _isUsableIpv4(raw)) {
      wifiIp = raw;
    }
  } catch (_) {
    // Platform plugin may be unsupported (e.g. headless tests or desktop Linux).
  }

  final byIp = <String, _ScoredInterface>{};

  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.isLinkLocal) continue;
        final ip = addr.address;
        if (!_isUsableIpv4(ip)) continue;

        final score = _scoreInterface(
          name: iface.name,
          address: ip,
          wifiIp: wifiIp,
        );
        final existing = byIp[ip];
        if (existing == null || score > existing.score) {
          byIp[ip] = _ScoredInterface(
            name: iface.name,
            address: ip,
            score: score,
          );
        }
      }
    }
  } catch (_) {
    // Fall back to Wi-Fi plugin address if interface enumeration throws.
  }

  // Some mobile OS configurations expose the Wi-Fi IP only via NetworkInfo.
  if (wifiIp != null && !byIp.containsKey(wifiIp)) {
    byIp[wifiIp] = _ScoredInterface(
      name: 'Wi-Fi',
      address: wifiIp,
      score: _scoreInterface(name: 'Wi-Fi', address: wifiIp, wifiIp: wifiIp),
    );
  }

  if (byIp.isEmpty) return const [];

  final sorted = byIp.values.toList()
    ..sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      final nameCmp = a.name.compareTo(b.name);
      return nameCmp != 0 ? nameCmp : a.address.compareTo(b.address);
    });

  return [
    for (var i = 0; i < sorted.length; i++)
      NetworkInterfaceInfo(
        name: sorted[i].name,
        address: sorted[i].address,
        isPreferred: i == 0,
      ),
  ];
}

/// Returns the top-ranked IPv4 address or `'127.0.0.1'` if none exist.
Future<String> resolvePrimaryIp() async {
  final interfaces = await listInterfaces();
  return interfaces.isEmpty ? '127.0.0.1' : interfaces.first.address;
}

bool _isUsableIpv4(String ip) {
  final octets = _parseOctets(ip);
  if (octets == null) return false;
  final a = octets[0];
  final b = octets[1];
  // Reject unspecified (0.0.0.0), loopback (127.0.0.0/8), and link-local (169.254.0.0/16).
  if (ip == '0.0.0.0' || a == 127) return false;
  if (a == 169 && b == 254) return false;
  return true;
}

int _scoreInterface({
  required String name,
  required String address,
  String? wifiIp,
}) {
  final lower = name.toLowerCase();

  // Virtual/tunnel adapters (WSL, Hyper-V, Docker, VPNs) often hold RFC1918
  // subnets unreachable from phones on the LAN, so demote them below physical NICs.
  if (_isVirtualAdapter(lower)) {
    return -1000 + _rfc1918Bonus(address);
  }

  var score = 100 + _rfc1918Bonus(address);

  if (_isWifiName(lower)) {
    score += 300;
    // Reward the OS-reported active Wi-Fi IP so secondary interfaces don't win.
    if (wifiIp != null && address == wifiIp) {
      score += 150;
    }
  } else if (_ethernetPattern.hasMatch(lower)) {
    score += 250;
  } else if (wifiIp != null && address == wifiIp) {
    score += 150;
  }

  return score;
}

bool _isVirtualAdapter(String lowerName) {
  const virtualKeywords = [
    'vethernet',
    'wsl',
    'hyper-v',
    'docker',
    'vmware',
    'virtualbox',
    'vbox',
    'utun',
    'tailscale',
    'wireguard',
  ];
  for (final keyword in virtualKeywords) {
    if (lowerName.contains(keyword)) return true;
  }
  return _virtualTokenPattern.hasMatch(lowerName);
}

bool _isWifiName(String lowerName) {
  return lowerName.contains('wlan') ||
      lowerName.contains('wi-fi') ||
      lowerName.contains('wifi') ||
      lowerName.contains('wireless') ||
      lowerName.startsWith('wlp') ||
      _en0Pattern.hasMatch(lowerName);
}

int _rfc1918Bonus(String ip) {
  final octets = _parseOctets(ip);
  if (octets == null) return 0;
  final a = octets[0];
  final b = octets[1];
  if (a == 192 && b == 168) return 120;
  if (a == 10) return 100;
  if (a == 172 && b >= 16 && b <= 31) return 90;
  return 10;
}

List<int>? _parseOctets(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  final result = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    result.add(value);
  }
  return result;
}

class const _ScoredInterface({
  required final String name,
  required final String address,
  required final int score,
});
