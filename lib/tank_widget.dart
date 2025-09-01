import 'package:flutter/material.dart';
import 'types.dart';

class TankWidget extends StatefulWidget {
  final TankType tankType;
  final double waterLevel; // 0.0 to 1.0
  final double? minThreshold; // 0.0 to 1.0
  final double? maxThreshold; // 0.0 to 1.0
  final double volume;
  final double percentage;

  const TankWidget({
    super.key,
    required this.tankType,
    required this.waterLevel,
    this.minThreshold,
    this.maxThreshold,
    required this.volume,
    required this.percentage,
  });

  @override
  State<TankWidget> createState() => _TankWidgetState();
}

class _TankWidgetState extends State<TankWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _animatedLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _animatedLevel = widget.waterLevel;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: _animatedLevel, end: widget.waterLevel).animate(_controller)
      ..addListener(() {
        setState(() {});
      });
    _controller.forward();
  }

  @override
  void didUpdateWidget(TankWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waterLevel != widget.waterLevel) {
      _animation = Tween<double>(begin: oldWidget.waterLevel, end: widget.waterLevel).animate(_controller);
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TankPainter(
        tankType: widget.tankType,
        waterLevel: _animation.value,
        minThreshold: widget.minThreshold,
        maxThreshold: widget.maxThreshold,
        percentage: widget.percentage,
        volume: widget.volume,
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

  TankPainter({
    required this.tankType,
    required this.waterLevel,
    this.minThreshold,
    this.maxThreshold,
    required this.percentage,
    required this.volume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tankBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.grey.shade700, Colors.grey.shade500, Colors.grey.shade700],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;

    final waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.blue.shade300, Colors.blue.shade800],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw tank
    final tankPath = _getTankPath(size);
    canvas.drawPath(tankPath, tankBorderPaint);

    // Draw water
    final waterRect = Rect.fromLTRB(
      0,
      size.height * (1 - waterLevel),
      size.width,
      size.height,
    );

    canvas.save();
    canvas.clipPath(tankPath);
    canvas.drawRect(waterRect, waterPaint);
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
            const Radius.circular(30),
          ));
      case TankType.horizontalCylinder:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, size.height * 0.25, size.width, size.height * 0.5),
            Radius.circular(size.height * 0.25),
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
