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

  /// Optional ring buffer of recent [lateralG, longitudinalG] readings.
  /// Pass alongside [trailStart] — the index of the oldest entry in the
  /// buffer (i.e. the next slot due to be overwritten) — so the trail can
  /// be read out in chronological order without needing to reallocate a
  /// reordered copy every frame.
  final List<List<double>>? trail;
  final int trailStart;

  const TractionCircle({
    super.key,
    required this.lateralG,
    required this.longitudinalG,
    this.maxG = 1.1,
    this.smoothing = const Duration(milliseconds: 12),
    this.trail,
    this.trailStart = 0,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill whatever box the parent gives us. Pair this widget with
        // AspectRatio(aspectRatio: 1) at the call site to keep it square.
        final size = constraints.maxWidth;
        return CustomPaint(
          size: Size(size, size),
          painter: _TractionCirclePainter(
            lateralG: _current.dx,
            longitudinalG: _current.dy,
            maxG: widget.maxG,
            trail: widget.trail,
            trailStart: widget.trailStart,
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
  final List<List<double>>? trail;
  final int trailStart;

  _TractionCirclePainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.maxG,
    this.trail,
    this.trailStart = 0,
  });

  /// Converts a raw [lateralG, longitudinalG] reading into a canvas
  /// position, using the same normalize-and-clamp logic as the dot so
  /// trail points line up exactly with where the dot would be.
  Offset _project(double g1, double g2, Offset center, double radius) {
    double nx = (g1 / maxG).clamp(-1.0, 1.0);
    double ny = (g2 / maxG).clamp(-1.0, 1.0);
    final magnitude = sqrt(nx * nx + ny * ny);
    if (magnitude > 1.0) {
      nx /= magnitude;
      ny /= magnitude;
    }
    return Offset(center.dx + nx * radius, center.dy - ny * radius);
  }

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

    // Fading trail: read the ring buffer starting at trailStart (the
    // oldest entry) so it comes out chronological without allocating a
    // reordered copy. Draw each segment with rising opacity so the
    // newest points are brightest and the oldest fade toward invisible.
    final trailPoints = trail;
    if (trailPoints != null && trailPoints.length > 1) {
      final projectedTrail = List<Offset>.generate(
        trailPoints.length,
        (index) {
          final bufferIndex = (trailStart + index) % trailPoints.length;
          final point = trailPoints[bufferIndex];
          return _project(point[0], point[2], center, radius);
        },
      );

      canvas.saveLayer(Offset.zero & size, Paint());
      for (int i = 0; i < projectedTrail.length - 1; i++) {
        final fadeOpacity = (i + 1) / projectedTrail.length;

        final paint = Paint()
          ..color = Colors.red.withOpacity(fadeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.src;

        canvas.drawLine(projectedTrail[i], projectedTrail[i + 1], paint);
      }
      canvas.restore();
    }

    // Dot always draws, independent of whether a trail exists — this
    // uses the live smoothed lateralG/longitudinalG, not a historical
    // trail point.
    final dotOffset = _project(lateralG, longitudinalG, center, radius);

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
        oldDelegate.longitudinalG != longitudinalG ||
        oldDelegate.trail != trail ||
        oldDelegate.trailStart != trailStart;
  }
}