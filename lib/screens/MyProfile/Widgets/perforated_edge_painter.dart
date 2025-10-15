import 'package:flutter/material.dart';
import 'dart:math' as math;

/// CustomPainter that draws a realistic perforated edge like real tickets
class PerforatedEdgePainter extends CustomPainter {
  final Color color;
  final double holeRadius;
  final double holeSpacing;
  final bool showLine;

  PerforatedEdgePainter({
    this.color = const Color(0xFFE0E0E0),
    this.holeRadius = 4.0,
    this.holeSpacing = 12.0,
    this.showLine = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw dotted line
    if (showLine) {
      final dashPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final dashWidth = 4.0;
      final dashSpace = 4.0;
      double startX = 0;

      while (startX < size.width) {
        canvas.drawLine(
          Offset(startX, 0),
          Offset(math.min(startX + dashWidth, size.width), 0),
          dashPaint,
        );
        startX += dashWidth + dashSpace;
      }
    }

    // Draw perforation holes
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final holeBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double currentX = holeSpacing;
    while (currentX < size.width - holeSpacing) {
      // Draw hole (white circle with border)
      canvas.drawCircle(
        Offset(currentX, 0),
        holeRadius,
        holePaint,
      );
      canvas.drawCircle(
        Offset(currentX, 0),
        holeRadius,
        holeBorderPaint,
      );
      
      currentX += holeSpacing + (holeRadius * 2);
    }
  }

  @override
  bool shouldRepaint(PerforatedEdgePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.holeRadius != holeRadius ||
        oldDelegate.holeSpacing != holeSpacing ||
        oldDelegate.showLine != showLine;
  }
}

/// Widget wrapper for the perforated edge
class PerforatedDivider extends StatelessWidget {
  final Color color;
  final double holeRadius;
  final double holeSpacing;
  final bool showLine;
  final double height;

  const PerforatedDivider({
    super.key,
    this.color = const Color(0xFFE0E0E0),
    this.holeRadius = 4.0,
    this.holeSpacing = 12.0,
    this.showLine = true,
    this.height = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: PerforatedEdgePainter(
          color: color,
          holeRadius: holeRadius,
          holeSpacing: holeSpacing,
          showLine: showLine,
        ),
      ),
    );
  }
}

