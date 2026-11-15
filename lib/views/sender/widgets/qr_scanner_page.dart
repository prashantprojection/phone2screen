import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/signaling_data.dart';

/// Camera QR scanner page that parses [SignalingData] pairing payloads.
class const QrScannerPage({super.key}) extends StatefulWidget {
  static Future<SignalingData?> scan(BuildContext context) {
    return Navigator.of(context).push<SignalingData>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
  }

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  DateTime? _lastErrorAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    try {
      final endpoint = SignalingData.fromQrString(raw);
      _handled = true;
      Navigator.of(context).pop(endpoint);
    } catch (_) {
      final now = DateTime.now();
      if (_lastErrorAt == null ||
          now.difference(_lastErrorAt!) > const Duration(seconds: 2)) {
        _lastErrorAt = now;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Invalid QR — scan an encrypted Phone2Screen pairing code',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Receiver QR'),
        actions: [
          // Read live torch state from MobileScannerState, not initial torchEnabled config.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final isTorchOn = state.torchState == .on;
              final unavailable = state.torchState == .unavailable;
              return IconButton(
                tooltip: isTorchOn ? 'Turn off flash' : 'Turn on flash',
                onPressed: unavailable ? null : _controller.toggleTorch,
                icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off),
              );
            },
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: .expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const IgnorePointer(
            child: CustomPaint(painter: _ScannerReticlePainter(), size: .infinite),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Center(
              child: Container(
                padding: const .symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDark.withValues(alpha: 0.82),
                  borderRadius: .circular(999),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const Text(
                  'Align the encrypted Phone2Screen QR inside the frame',
                  textAlign: .center,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _ScannerReticlePainter() extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * 0.68).clamp(180.0, 280.0);
    final rect = Rect.fromCenter(center: size.center(.zero), width: side, height: side);
    final rRect = RRect.fromRectAndRadius(rect, const .circular(18));

    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rRect)
      ..fillType = .evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.56));

    final cornerPaint = Paint()
      ..color = AppColors.cyanAccent
      ..style = .stroke
      ..strokeWidth = 4
      ..strokeCap = .round;
    const len = 28.0;

    void drawCorner(Offset origin, double dx, double dy) {
      final path = Path()
        ..moveTo(origin.dx, origin.dy + dy * len)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + dx * len, origin.dy);
      canvas.drawPath(path, cornerPaint);
    }

    drawCorner(rect.topLeft, 1, 1);
    drawCorner(rect.topRight, -1, 1);
    drawCorner(rect.bottomLeft, 1, -1);
    drawCorner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
