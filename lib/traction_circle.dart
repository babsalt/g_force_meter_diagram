import 'dart:math';
import 'package:flutter/material.dart';

/// A traction/G-G circle: draws a circle with a dot showing current
/// lateral (left/right) and longitudinal (accel/brake) G-force.

class TractionCircle extends StatelessWidget {
  final double lateralG;      // x-axis: negative = left, positive = right
  final double longitudinalG; // y-axis: negative = braking, positive = accel
  final double maxG;          // radius of the circle in G units
  final Duration smoothing;   // how long each eased transition takes

  const TractionCircle({
    super.key,
    required this.lateralG,
    required this.longitudinalG,
    this.maxG = 1.5,
    this.smoothing = const Duration(milliseconds: 20),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Offset>(
      duration: smoothing,
      curve: Curves.linear,
      // Only `end` is set — TweenAnimationBuilder automatically retargets
      // `begin` to whatever the current animated value is whenever `end`
      // changes, so a new sensor reading mid-animation redirects smoothly
      // instead of jumping back to the start.
      tween: Tween<Offset>(end: Offset(lateralG, longitudinalG)),
      builder: (context, offset, child) {
        return CustomPaint(
          size: const Size(300, 300),
          painter: _TractionCirclePainter(
            lateralG: offset.dx,
            longitudinalG: offset.dy,
            maxG: maxG,
          ),
        );
      },
    );
  }
}

class _TractionCirclePainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  final double maxG;

  _TractionCirclePainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.maxG,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Outer boundary circle
    final circlePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, circlePaint);

    // Reference rings + crosshair
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius * 0.66, gridPaint);
    canvas.drawCircle(center, radius * 0.33, gridPaint);
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), gridPaint);

    // Normalize G values to [-1, 1] range relative to maxG
    double normX = (lateralG / maxG).clamp(-1.0, 1.0);
    double normY = (longitudinalG / maxG).clamp(-1.0, 1.0);

    // Clamp the dot to the circle edge if the combined magnitude exceeds it
    final magnitude = sqrt(normX * normX + normY * normY);
    if (magnitude > 1.0) {
      normX /= magnitude;
      normY /= magnitude;
    }

    final dotOffset = Offset(
      center.dx + normX * radius,
      center.dy - normY * radius, // invert Y: up = positive (accel)
    );

    canvas.drawCircle(dotOffset, 10, Paint()..color = Colors.redAccent);
    canvas.drawCircle(
      dotOffset,
      14,
      Paint()
        ..color = Colors.redAccent.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant _TractionCirclePainter oldDelegate) {
    return oldDelegate.lateralG != lateralG ||
        oldDelegate.longitudinalG != longitudinalG;
  }
}