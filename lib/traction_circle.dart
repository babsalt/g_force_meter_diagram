import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A traction/G-G circle: draws a circle with a dot showing current
/// lateral (left/right) and longitudinal (accel/brake) G-force.
///
/// Rendering is decoupled from how often new sensor data arrives. A
/// [Ticker] runs continuously in sync with the display's own vsync
/// signal, and on every frame the dot's displayed position exponentially
/// chases whatever the latest sensor reading is. This means the dot
/// stays smooth and renders at your device's real max frame rate even
/// if sensor events arrive irregularly or below that rate.
class TractionCircle extends StatefulWidget {
  final double lateralG;      // x-axis: negative = left, positive = right
  final double longitudinalG; // y-axis: negative = braking, positive = accel
  final double maxG;          // radius of the circle in G units

  /// Time constant for the smoothing filter — roughly how long the dot
  /// takes to "catch up" to a new value. Smaller = snappier/twitchier,
  /// larger = smoother/laggier. This is independent of both the frame
  /// rate and the sensor sampling period.
  final Duration smoothing;

  const TractionCircle({
    super.key,
    required this.lateralG,
    required this.longitudinalG,
    this.maxG = 1.5,
    this.smoothing = const Duration(milliseconds: 20),
  });

  @override
  State<TractionCircle> createState() => _TractionCircleState();
}

class _TractionCircleState extends State<TractionCircle>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  late Offset _current;

  @override
  void initState() {
    super.initState();
    _current = Offset(widget.lateralG, widget.longitudinalG);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dtSeconds =
        (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dtSeconds <= 0) return;

    final target = Offset(widget.lateralG, widget.longitudinalG);
    final tauSeconds =
        widget.smoothing.inMicroseconds / Duration.microsecondsPerSecond;
    // Exponential decay toward target, framerate-independent.
    final alpha = tauSeconds > 0 ? 1 - exp(-dtSeconds / tauSeconds) : 1.0;

    setState(() {
      _current = Offset.lerp(_current, target, alpha)!;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(300, 300),
      painter: _TractionCirclePainter(
        lateralG: _current.dx,
        longitudinalG: _current.dy,
        maxG: widget.maxG,
      ),
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