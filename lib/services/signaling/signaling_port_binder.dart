import 'dart:convert';
import 'dart:io';

import '../../core/constants/stream_constants.dart';
import 'lan_tls_credentials.dart';
import 'obs_clean_feed_page.dart';
import 'web_companion_mode.dart';
import 'web_viewer_page.dart';

/// Binds an HTTP server on [preferredPort] (`0` for ephemeral, or retrying
/// through `StreamConstants.maxSignalingPort`).
Future<HttpServer> bindHttpPortRange(int preferredPort) async {
  if (preferredPort == 0) {
    return HttpServer.bind(InternetAddress.anyIPv4, 0);
  }

  final startPort = preferredPort;
  final endPort = preferredPort > StreamConstants.maxSignalingPort
      ? preferredPort
      : StreamConstants.maxSignalingPort;

  SocketException? lastError;
  for (var port = startPort; port <= endPort; port++) {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (e) {
      lastError = e;
    }
  }

  throw StateError(
    'Unable to bind signaling server on ports $startPort..$endPort: '
    '${lastError?.message ?? 'unknown socket error'}',
  );
}

/// Best-effort bind of a companion TLS `HttpServer` so LAN browsers get a
/// Secure Context for camera/screen capture. Returns `null` if unavailable so
/// plain HTTP signaling never fails.
Future<HttpServer?> tryBindHttpsPortRange(int? preferredHttpsPort) async {
  if (preferredHttpsPort == null) return null;
  try {
    final context = buildLanSecurityContext();
    if (preferredHttpsPort == 0) {
      return await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, context);
    }

    final startPort = preferredHttpsPort;
    final endPort = preferredHttpsPort > StreamConstants.maxHttpsPort
        ? preferredHttpsPort
        : StreamConstants.maxHttpsPort;

    for (var port = startPort; port <= endPort; port++) {
      try {
        return await HttpServer.bindSecure(
          InternetAddress.anyIPv4,
          port,
          context,
        );
      } on SocketException {
        // Try next port in range.
      }
    }
  } catch (_) {
    // TLS context or socket bind unavailable; keep HTTP signaling running.
  }
  return null;
}

/// Serves static HTTP routes (`GET /health`, `GET /p2s-info`, `GET /obs`,
/// `GET /`, or 404) for the signaling server's USB probe, companion, and OBS
/// Browser Source pages.
Future<void> serveSignalingHttpRequest(
  HttpRequest request, {
  required String sessionId,
  required String deviceName,
  required bool requiresPin,
  required WebCompanionMode mode,
  required int httpPort,
  required int? httpsPort,
}) async {
  final path = request.uri.path;
  if (path == '/health' && request.method == 'GET') {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'status': 'ok',
          'sessionId': sessionId,
          'deviceName': deviceName,
          'requiresPin': requiresPin,
          'httpsPort': httpsPort,
          'mode': mode.name,
        }),
      );
    await request.response.close();
    return;
  }
  if (path == StreamConstants.usbInfoPath && request.method == 'GET') {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'magic': StreamConstants.discoveryMagic,
          'ip': '127.0.0.1',
          'port': httpPort,
          'httpsPort': ?httpsPort,
          'sessionId': sessionId,
          'deviceName': deviceName,
          'requiresPin': requiresPin,
          'mode': mode.name,
        }),
      );
    await request.response.close();
    return;
  }
  if (path == StreamConstants.obsCleanFeedPath && request.method == 'GET') {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        buildObsCleanFeedHtml(
          sessionId: sessionId,
          deviceName: deviceName,
          requiresPin: requiresPin,
          mode: mode,
        ),
      );
    await request.response.close();
    return;
  }
  if (path == '/' && request.method == 'GET') {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        buildWebCompanionHtml(
          sessionId: sessionId,
          deviceName: deviceName,
          requiresPin: requiresPin,
          mode: mode,
          httpPort: httpPort,
          httpsPort: httpsPort,
        ),
      );
    await request.response.close();
    return;
  }

  request.response.statusCode = HttpStatus.notFound;
  await request.response.close();
}
