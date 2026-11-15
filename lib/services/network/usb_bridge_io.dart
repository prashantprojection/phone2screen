import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import '../../models/discovered_peer.dart';
import '../../models/signaling_data.dart';
import 'usb_bridge_service.dart';

/// Native `dart:io` implementation of ADB reverse tunneling and `127.0.0.1`
/// loopback `/p2s-info` receiver probing.
class UsbBridgeImpl {
  UsbBridgeImpl({UsbProcessRunner? processRunner, bool? allowInTestOverride})
    : _customRunner = processRunner,
      _allowInTestOverride = allowInTestOverride ?? false;

  final UsbProcessRunner? _customRunner;
  final bool _allowInTestOverride;
  final _statusController = StreamController<UsbBridgeStatus>.broadcast();

  UsbBridgeStatus _status = const UsbBridgeStatus();
  bool _disposed = false;

  Stream<UsbBridgeStatus> get statusStream => _statusController.stream;

  UsbBridgeStatus get currentStatus => _status;

  bool get _inFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<UsbBridgeStatus> syncAdbReversePorts(List<int> ports) async {
    if (_disposed) return _status;

    final hasCustomRunner = _customRunner != null;
    final canRunAdb =
        (_isDesktop || hasCustomRunner || _allowInTestOverride) &&
        (!_inFlutterTest || hasCustomRunner || _allowInTestOverride);
    if (!canRunAdb) return _updateStatus(const UsbBridgeStatus());

    final uniquePorts = _dedupePorts(ports);
    final runner = _customRunner ?? _defaultProcessRunner;

    final ({int exitCode, String stdout, String stderr}) devicesRes;
    try {
      devicesRes = await runner('adb', const ['devices']);
    } on ProcessException {
      return _updateStatus(const UsbBridgeStatus(adbAvailable: false));
    } catch (_) {
      return _updateStatus(const UsbBridgeStatus(adbAvailable: false));
    }

    if (_disposed) return _status;
    if (devicesRes.exitCode != 0) {
      return _updateStatus(const UsbBridgeStatus(adbAvailable: false));
    }

    final parsed = _parseAdbDevices(devicesRes.stdout);
    final forwardedSet = <int>{};

    for (final serial in parsed.connected) {
      for (final port in uniquePorts) {
        try {
          final rev = await runner('adb', [
            '-s', serial, 'reverse', 'tcp:$port', 'tcp:$port',
          ]);
          if (rev.exitCode == 0) forwardedSet.add(port);
        } on ProcessException {
          return _updateStatus(const UsbBridgeStatus(adbAvailable: false));
        } catch (_) {
          // Keep attempting remaining ports/devices on a single reverse failure.
        }
      }
    }

    if (_disposed) return _status;
    return _updateStatus(
      UsbBridgeStatus(
        adbAvailable: true,
        connectedSerials: List.unmodifiable(parsed.connected),
        unauthorizedSerials: List.unmodifiable(parsed.unauthorized),
        forwardedPorts: List.unmodifiable([
          for (final p in uniquePorts)
            if (forwardedSet.contains(p)) p,
        ]),
      ),
    );
  }

  Future<List<DiscoveredPeer>> probeLoopbackReceivers({
    List<int> ports = const [8080, 8081, 8082, 8083],
    String? ignoreSessionId,
    Duration timeout = const Duration(milliseconds: 350),
  }) async {
    if (_disposed || (_inFlutterTest && !_allowInTestOverride)) return const [];
    final uniquePorts = _dedupePorts(ports);
    if (uniquePorts.isEmpty) return const [];

    // Bypass OS proxies so 127.0.0.1 ADB loopback probes connect directly.
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final results = await Future.wait([
        for (final port in uniquePorts)
          _probePort(
            client,
            port,
            ignoreSessionId: ignoreSessionId,
            timeout: timeout,
          ),
      ]);
      return List.unmodifiable(results.whereType<DiscoveredPeer>());
    } finally {
      client.close(force: true);
    }
  }

  Future<DiscoveredPeer?> _probePort(
    HttpClient client,
    int port, {
    required String? ignoreSessionId,
    required Duration timeout,
  }) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$port${StreamConstants.usbInfoPath}');
      final req = await client.getUrl(uri).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        return null;
      }
      final body = await utf8.decodeStream(resp).timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['magic'] != StreamConstants.discoveryMagic) return null;
      final mode = decoded['mode'];
      if (mode != null && mode != 'sendToReceiver') return null;
      final sid = decoded['sessionId'];
      if (sid is! String || sid.isEmpty || sid == ignoreSessionId) return null;

      final endpoint = SignalingData.fromJson({
        ...decoded,
        'ip': '127.0.0.1',
        'port': (decoded['port'] as num?)?.toInt() ?? port,
      });
      return DiscoveredPeer(
        endpoint: endpoint,
        lastSeen: DateTime.now(),
        isUsbLoopback: true,
      );
    } catch (_) {
      return null;
    }
  }

  UsbBridgeStatus _updateStatus(UsbBridgeStatus next) {
    _status = next;
    if (!_disposed && !_statusController.isClosed) _statusController.add(next);
    return next;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _statusController.close();
  }

  static List<int> _dedupePorts(List<int> ports) {
    final seen = <int>{};
    return [for (final p in ports) if (p > 0 && p <= 65535 && seen.add(p)) p];
  }

  static ({List<String> connected, List<String> unauthorized}) _parseAdbDevices(
    String stdoutText,
  ) {
    final connected = <String>[];
    final unauthorized = <String>[];
    final seenConnected = <String>{};
    final seenUnauth = <String>{};
    for (final line in stdoutText.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('List of devices') ||
          trimmed.startsWith('*')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final serial = parts[0];
      final state = parts[1].toLowerCase();
      if (state == 'device' && seenConnected.add(serial)) {
        connected.add(serial);
      } else if (state == 'unauthorized' && seenUnauth.add(serial)) {
        unauthorized.add(serial);
      }
    }
    return (connected: connected, unauthorized: unauthorized);
  }

  static Future<({int exitCode, String stdout, String stderr})>
  _defaultProcessRunner(String exe, List<String> args) async {
    final res = await Process.run(exe, args);
    return (
      exitCode: res.exitCode,
      stdout: res.stdout is String ? res.stdout as String : '${res.stdout}',
      stderr: res.stderr is String ? res.stderr as String : '${res.stderr}',
    );
  }
}
