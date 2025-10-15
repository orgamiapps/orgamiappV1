import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Creates a modern gradient mesh background with multiple color stops
class GradientMeshPainter extends CustomPainter {
  final List<Color> colors;
  final double animation;
  final bool isVIP;

  GradientMeshPainter({
    required this.colors,
    this.animation = 0.0,
    this.isVIP = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Create multiple radial gradients for mesh effect
    final positions = [
      Offset(size.width * 0.2, size.height * 0.3),
      Offset(size.width * 0.8, size.height * 0.2),
      Offset(size.width * 0.3, size.height * 0.8),
      Offset(size.width * 0.7, size.height * 0.7),
    ];

    for (int i = 0; i < positions.length; i++) {
      final gradient = ui.Gradient.radial(
        positions[i],
        size.width * 0.5,
        [
          colors[i % colors.length].withValues(alpha: 0.15),
          colors[i % colors.length].withValues(alpha: 0.05),
          Colors.transparent,
        ],
        [0.0, 0.5, 1.0],
      );

      final paint = Paint()..shader = gradient;
      canvas.drawCircle(
        positions[i],
        size.width * 0.6,
        paint,
      );
    }

    // Add animated waves for VIP tickets
    if (isVIP) {
      final wavePaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, size.height),
          Offset(size.width, 0),
          [
            const Color(0xFFFFD700).withValues(alpha: 0.08),
            const Color(0xFFFFA500).withValues(alpha: 0.05),
            const Color(0xFFFF69B4).withValues(alpha: 0.03),
          ],
        );

      final path = Path();
      path.moveTo(0, size.height * 0.7);

      for (double x = 0; x <= size.width; x += 5) {
        final y = size.height * 0.7 +
            math.sin((x / size.width) * math.pi * 4 + animation * math.pi * 2) *
                15;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(GradientMeshPainter oldDelegate) =>
      animation != oldDelegate.animation || isVIP != oldDelegate.isVIP;
}

