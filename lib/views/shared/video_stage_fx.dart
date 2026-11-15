import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../models/viewer_display_config.dart';

/// Composites a center-feathered GPU portrait blur over [sharpVideo].
Widget buildPortraitBokehLayer({
  required PortraitBokehMode mode,
  required Widget sharpVideo,
  required Widget blurredSource,
}) {
  if (mode == .off) return sharpVideo;
  // Two buildVideo() textures + dstIn ShaderMask keep the subject crisp while
  // feathering the blurred background without BackdropFilter saveLayer passes
  // that disrupt WebRTC texture compositing and waste GPU fillrate.
  return Stack(
    fit: .expand,
    children: [
      sharpVideo,
      IgnorePointer(
        child: ClipRect(
          child: ShaderMask(
            blendMode: .dstIn,
            shaderCallback: (bounds) => const RadialGradient(
              center: Alignment(0, -0.06),
              radius: 0.82,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.black,
                Colors.black,
              ],
              stops: [0.0, 0.36, 0.68, 1.0],
            ).createShader(bounds),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: mode.sigma,
                sigmaY: mode.sigma,
                tileMode: .decal,
              ),
              child: blurredSource,
            ),
          ),
        ),
      ),
    ],
  );
}

/// Applies 180° overhead desk flip and 3D perspective keystone correction.
Widget applyDeskKeystoneTransform({
  required ViewerDisplayConfig config,
  required Widget child,
}) {
  if (!config.deskCamMode &&
      config.keystoneVertical == 0.0 &&
      config.keystoneHorizontal == 0.0) {
    return child;
  }
  final matrix = Matrix4.identity()
    ..setEntry(3, 2, 0.0014)
    ..rotateX(config.keystoneVertical * 0.65)
    ..rotateY(config.keystoneHorizontal * 0.65)
    ..rotateZ(config.deskCamMode ? math.pi : 0.0);
  return ClipRect(
    child: Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: child,
    ),
  );
}

/// Soft warm-white center fill-light glow layered over the receiver stage.
class const FaceFillLightOverlay({
  super.key,
  required final double intensity,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final clamped = intensity.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0.0) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.08),
            radius: 0.78,
            colors: [
              const Color(0xFFFFF6EA).withValues(alpha: clamped * 0.24),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Subtle dark edge vignette framing the subject on the receiver stage.
class const StageVignetteOverlay({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.88,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.52),
            ],
            stops: const [0.58, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Rule-of-Thirds composition guide overlay for the studio receiver stage.
class const StageThirdsGridOverlay({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(child: CustomPaint(painter: _ThirdsGridPainter()));
  }
}

class _ThirdsGridPainter extends CustomPainter {
  const _ThirdsGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0
      ..style = .stroke;

    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ThirdsGridPainter oldDelegate) => false;
}
