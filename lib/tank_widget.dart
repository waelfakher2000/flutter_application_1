import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'types.dart';

class TankWidget extends StatefulWidget {
  final TankType tankType;
  final double waterLevel; // 0.0 to 1.0
  final double? minThreshold; // 0.0 to 1.0
  final double? maxThreshold; // 0.0 to 1.0
  final double volume;
  final double percentage;
  final GraduationSide graduationSide;
  final double majorTickMeters; // project units are meters
  final int minorDivisions;
  final double fullHeightMeters; // used for labeling ticks in meters
  // For horizontal cylinder graduation (non-linear volume mapping)
  final double? capacityLiters; // total capacity used for labeling volume ticks
  final double? innerCylinderDiameterMeters; // inner diameter for circular segment math

  const TankWidget({
    super.key,
    required this.tankType,
    required this.waterLevel,
    this.minThreshold,
    this.maxThreshold,
    required this.volume,
    required this.percentage,
    this.graduationSide = GraduationSide.left,
    this.majorTickMeters = 0.1,
    this.minorDivisions = 4,
    this.fullHeightMeters = 1.0,
    this.capacityLiters,
    this.innerCylinderDiameterMeters,
  });

  @override
  State<TankWidget> createState() => _TankWidgetState();
}

class _TankWidgetState extends State<TankWidget> with TickerProviderStateMixin {
  // Animates level transitions (on data updates)
  late AnimationController _levelController;
  late Animation<double> _levelAnimation;
  double _animatedLevel = 0.0;

  // Continuous wave animation (purely visual)
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _animatedLevel = widget.waterLevel;
    _levelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _levelAnimation = Tween<double>(begin: _animatedLevel, end: widget.waterLevel).animate(_levelController)
      ..addListener(() {
        setState(() {});
      });
    _levelController.forward();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )
      ..addListener(() {
        // drive repaint for waves/bubbles
        if (mounted) setState(() {});
      })
      ..repeat();
  }

  @override
  void didUpdateWidget(TankWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waterLevel != widget.waterLevel) {
      _levelAnimation = Tween<double>(begin: oldWidget.waterLevel, end: widget.waterLevel).animate(_levelController);
      _levelController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
  _levelController.dispose();
  _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme-aware scale colors (grey in light mode, light-grey in dark mode)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color scaleColor = isDark ? Colors.grey.shade300 : Colors.grey.shade800;
    final Color scaleMinorColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final Color labelColor = isDark ? Colors.grey.shade200 : Colors.grey.shade800;
    return CustomPaint(
      painter: TankPainter(
        tankType: widget.tankType,
  waterLevel: _levelAnimation.value,
        minThreshold: widget.minThreshold,
        maxThreshold: widget.maxThreshold,
        percentage: widget.percentage,
        volume: widget.volume,
  wavePhase: _waveController.value * 2 * math.pi,
  waveAmplitude: 0.03, // ~3% of tank height
        graduationSide: widget.graduationSide,
        majorTickMeters: widget.majorTickMeters,
        minorDivisions: widget.minorDivisions,
        fullHeightMeters: widget.fullHeightMeters,
        capacityLiters: widget.capacityLiters,
        innerCylinderDiameterMeters: widget.innerCylinderDiameterMeters,
        scaleColor: scaleColor,
        scaleMinorColor: scaleMinorColor,
        labelColor: labelColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class TankPainter extends CustomPainter {
  final TankType tankType;
  final double waterLevel;
  final double? minThreshold;
  final double? maxThreshold;
  final double percentage;
  final double volume;
  final double wavePhase; // radians [0..2π)
  final double waveAmplitude; // fraction of height (e.g., 0.03)
  final GraduationSide graduationSide;
  final double majorTickMeters;
  final int minorDivisions;
  final double fullHeightMeters;
  final Color scaleColor;
  final Color scaleMinorColor;
  final Color labelColor;
  final double? capacityLiters;
  final double? innerCylinderDiameterMeters;

  TankPainter({
    required this.tankType,
    required this.waterLevel,
    this.minThreshold,
    this.maxThreshold,
    required this.percentage,
    required this.volume,
  required this.wavePhase,
  required this.waveAmplitude,
    required this.graduationSide,
    required this.majorTickMeters,
    required this.minorDivisions,
    required this.fullHeightMeters,
    this.capacityLiters,
    this.innerCylinderDiameterMeters,
    required this.scaleColor,
    required this.scaleMinorColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Tank border with subtle metallic gradient
    final tankBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.grey.shade300.withValues(alpha: 0.85),
          Colors.grey.shade600.withValues(alpha: 0.9),
          Colors.grey.shade400.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    // Water fill gradient (deeper at bottom)
    final waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF5EC8FF).withValues(alpha: 0.9),
          const Color(0xFF0A6FDB).withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw tank
    final tankPath = _getTankPath(size);
    canvas.drawPath(tankPath, tankBorderPaint);

    // Draw water with a wavy surface
    final levelY = size.height * (1 - waterLevel.clamp(0.0, 1.0));
    final amp = (size.height * waveAmplitude).clamp(0.0, size.height * 0.08);
    final cycles = 2.0; // number of waves across width

    final waterPath = Path();
    waterPath.moveTo(0, levelY);
    final steps = math.max(12, (size.width / 6).floor());
    for (int i = 0; i <= steps; i++) {
      final x = size.width * (i / steps);
      final y = levelY + amp * math.sin((x / size.width) * 2 * math.pi * cycles + wavePhase);
      waterPath.lineTo(x, y);
    }
    waterPath.lineTo(size.width, size.height);
    waterPath.lineTo(0, size.height);
    waterPath.close();

    canvas.save();
    canvas.clipPath(tankPath);
  canvas.drawPath(waterPath, waterPaint);

    // Subtle surface highlight
    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
  colors: [Colors.white.withValues(alpha: 0.25), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, levelY - amp - 8, size.width, amp + 16));
    canvas.drawRect(Rect.fromLTWH(0, levelY - amp - 8, size.width, amp + 16), highlight);

    // Bubbles rising
    _drawBubbles(canvas, size, tankPath);

    canvas.restore();

    // Draw threshold lines
    if (minThreshold != null) {
      _drawThresholdLine(canvas, size, minThreshold!, Colors.orange);
    }
    if (maxThreshold != null) {
      _drawThresholdLine(canvas, size, maxThreshold!, Colors.red);
    }

    // Draw text inside the tank
    _drawText(canvas, size, '${percentage.toStringAsFixed(1)}%', size.height / 2 - 20);
    _drawText(canvas, size, '${volume.toStringAsFixed(2)} L', size.height / 2 + 20);

    // Draw graduation scale on chosen side
    _drawGraduation(canvas, size);
  }

  void _drawText(Canvas canvas, Size size, String text, double y) {
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 4.0,
          color: Colors.black,
          offset: Offset(2.0, 2.0),
        ),
      ],
    );
    final textSpan = TextSpan(
      text: text,
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(
      minWidth: 0,
      maxWidth: size.width,
    );
    final x = (size.width - textPainter.width) / 2;
    textPainter.paint(canvas, Offset(x, y));
  }

  Path _getTankPath(Size size) {
    switch (tankType) {
      case TankType.verticalCylinder:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Radius.circular(32),
          ));
      case TankType.horizontalCylinder:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, size.height * 0.2, size.width, size.height * 0.6),
            Radius.circular(size.height * 0.3),
          ));
      case TankType.rectangle:
        return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    }
  }

  void _drawThresholdLine(Canvas canvas, Size size, double threshold, Color color) {
    final y = size.height * (1 - threshold);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    canvas.drawPath(path, paint);
  }

  void _drawBubbles(Canvas canvas, Size size, Path clipPath) {
    final bubblePaint = Paint()
  ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final n = 8;
    // Use phase as a time source; spread bubbles horizontally
    for (int i = 0; i < n; i++) {
      final phase0 = (wavePhase / (2 * math.pi) + i * 0.13) % 1.0;
      final x = size.width * (0.1 + 0.8 * (i / (n - 1)));
      final y = size.height - (size.height * phase0);
      final r = 1.5 + 2.5 * (1 - phase0);
      final bubble = Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
      // Clip to tank to avoid drawing outside
  canvas.save();
  canvas.clipPath(clipPath);
  canvas.drawPath(bubble, bubblePaint);
  canvas.restore();
    }
  }

  void _drawGraduation(Canvas canvas, Size size) {
    // Draw ticks and labels just outside the tank border
    final tickPaint = Paint()
      ..color = scaleColor
      ..strokeWidth = 2;
    final minorPaint = Paint()
      ..color = scaleMinorColor
      ..strokeWidth = 1;

    // Graduation spans full height with 0 at bottom and increasing upward
    // Compute pixel per meter based on the drawing height being 1.0 for waterLevel.
    // Since TankWidget doesn't know absolute meters, we treat 1.0 = full height and map majorTickMeters relative to that.
    // Caller should pass majorTickMeters normalized to full height when building this widget.

  final double majorStep = majorTickMeters; // normalized 0..1
  if (majorStep <= 0) return;
    final int minor = minorDivisions.clamp(0, 10);

    // Decide x position for ticks (left or right outside border)
    final bool right = graduationSide == GraduationSide.right;
    final double x0 = right ? size.width + 2 : -2;
    final double labelDx = right ? 4 : -4; // offset for text away from ticks

    // Helper to map height fraction (0=bottom..1=top) to canvas Y, aligned with visible tank bounds
    double yFromFrac(double f) {
      f = f.clamp(0.0, 1.0);
      if (tankType == TankType.horizontalCylinder) {
        final top = size.height * 0.2;
        final bottom = size.height * 0.8;
        return bottom - f * (bottom - top);
      }
      return size.height * (1 - f);
    }

    // Horizontal cylinder: ticks at equal volume fractions, not equal heights
    if (tankType == TankType.horizontalCylinder && (innerCylinderDiameterMeters ?? 0) > 0) {
      final D = innerCylinderDiameterMeters!;
      final r = D / 2.0;

      // Helper: map volume fraction (0..1) to height fraction (0..1) by inverting segment area
      double heightFracForVolFrac(double f) {
        f = f.clamp(0.0, 1.0);
        if (f <= 0) return 0.0;
        if (f >= 1) return 1.0;
        // Binary search h in [0, 2r] such that A(h)/(pi r^2) ~= f
        double lo = 0.0, hi = 2.0 * r;
        for (int it = 0; it < 30; it++) {
          final mid = 0.5 * (lo + hi);
          final a = _cylSegmentArea(r, mid) / (math.pi * r * r);
          if (a < f) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        final h = 0.5 * (lo + hi);
        return (h / (2.0 * r)).clamp(0.0, 1.0);
      }

      for (double frac = 0.0; frac <= 1.0001; frac += majorStep) {
        final vf = frac.clamp(0.0, 1.0);
        final hf = heightFracForVolFrac(vf);
        final y = yFromFrac(hf);
        final p1 = Offset(x0, y);
        final p2 = Offset(right ? x0 + 10 : x0 - 10, y);
        canvas.drawLine(p1, p2, tickPaint);

    // Label height (meters) at this tick
    final effectiveH = (innerCylinderDiameterMeters ?? fullHeightMeters);
    final meters = (hf * (effectiveH <= 0 ? 1.0 : effectiveH)).clamp(0.0, double.infinity);
    final text = TextSpan(text: '${meters.toStringAsFixed(2)}m', style: TextStyle(color: labelColor, fontSize: 10));
        final tp = TextPainter(text: text, textDirection: TextDirection.ltr);
        tp.layout(minWidth: 0);
        final labelX = right ? p2.dx + labelDx : p2.dx - tp.width + labelDx;
        tp.paint(canvas, Offset(labelX, y - tp.height / 2));

        if (minor > 0 && frac + majorStep <= 1.0 + 1e-6) {
          final double df = majorStep / (minor + 1);
          for (int i = 1; i <= minor; i++) {
            final ff = (frac + df * i).clamp(0.0, 1.0);
            final hfm = heightFracForVolFrac(ff);
            final ym = yFromFrac(hfm);
            final q1 = Offset(x0, ym);
            final q2 = Offset(right ? x0 + 6 : x0 - 6, ym);
            canvas.drawLine(q1, q2, minorPaint);
          }
        }
      }
    } else {
      // Default (rectangle, vertical cylinder): equal height steps labeled in meters
      for (double v = 0.0; v <= 1.0001; v += majorStep) {
        final y = yFromFrac(v);
        final p1 = Offset(x0, y);
        final p2 = Offset(right ? x0 + 10 : x0 - 10, y);
        canvas.drawLine(p1, p2, tickPaint);

        final meters = (v * (fullHeightMeters <= 0 ? 1.0 : fullHeightMeters)).clamp(0.0, double.infinity);
        final text = TextSpan(text: '${meters.toStringAsFixed(2)}m', style: TextStyle(color: labelColor, fontSize: 10));
        final tp = TextPainter(text: text, textDirection: TextDirection.ltr);
        tp.layout(minWidth: 0);
        final labelX = right ? p2.dx + labelDx : p2.dx - tp.width + labelDx;
        tp.paint(canvas, Offset(labelX, y - tp.height / 2));

        if (minor > 0 && v + majorStep <= 1.0 + 1e-6) {
          final double dv = majorStep / (minor + 1);
          for (int i = 1; i <= minor; i++) {
            final vm = v + dv * i;
            final ym = yFromFrac(vm);
            final q1 = Offset(x0, ym);
            final q2 = Offset(right ? x0 + 6 : x0 - 6, ym);
            canvas.drawLine(q1, q2, minorPaint);
          }
        }
      }
    }

    // Always draw the max (top) tick/label at 100% height
  const double vTop = 1.0;
  final yTop = yFromFrac(vTop);
    final pTop1 = Offset(x0, yTop);
    final pTop2 = Offset(right ? x0 + 10 : x0 - 10, yTop);
    canvas.drawLine(pTop1, pTop2, tickPaint);
    TextSpan topTextSpan;
    if (tankType == TankType.horizontalCylinder && (innerCylinderDiameterMeters ?? 0) > 0) {
      final effectiveH = (innerCylinderDiameterMeters ?? fullHeightMeters);
      final topMeters = (effectiveH <= 0 ? 1.0 : effectiveH);
      topTextSpan = TextSpan(text: '${topMeters.toStringAsFixed(2)}m', style: TextStyle(color: labelColor, fontSize: 10));
    } else {
      final topMeters = (fullHeightMeters <= 0 ? 1.0 : fullHeightMeters);
      topTextSpan = TextSpan(text: '${topMeters.toStringAsFixed(2)}m', style: TextStyle(color: labelColor, fontSize: 10));
    }
    final topTp = TextPainter(text: topTextSpan, textDirection: TextDirection.ltr);
    topTp.layout(minWidth: 0);
    final topLabelX = right ? pTop2.dx + labelDx : pTop2.dx - topTp.width + labelDx;
    topTp.paint(canvas, Offset(topLabelX, yTop - topTp.height / 2));
  }

  // Circular segment area for a horizontal cylinder cross-section filled to depth h (0..2r)
  double _cylSegmentArea(double r, double h) {
    if (h <= 0) return 0.0;
    if (h >= 2 * r) return math.pi * r * r;
    final a = r * r * math.acos((r - h) / r) - (r - h) * math.sqrt(2 * r * h - h * h);
    return a;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
