import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Painter that creates a subtle security pattern background like real tickets
class SecurityPatternPainter extends CustomPainter {
  final Color color;
  final double opacity;

  SecurityPatternPainter({
    this.color = const Color(0xFF667EEA),
    this.opacity = 0.03,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Create a microprint pattern (like security on currency)
    final spacing = 15.0;
    final rows = (size.height / spacing).ceil();
    final cols = (size.width / spacing).ceil();

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = col * spacing;
        final y = row * spacing;

        // Create various geometric patterns
        final pattern = (row + col) % 4;

        switch (pattern) {
          case 0:
            // Small circles
            canvas.drawCircle(Offset(x, y), 2, paint);
            break;
          case 1:
            // Diamond shapes
            final path = Path()
              ..moveTo(x, y - 3)
              ..lineTo(x + 3, y)
              ..lineTo(x, y + 3)
              ..lineTo(x - 3, y)
              ..close();
            canvas.drawPath(path, paint);
            break;
          case 2:
            // Cross pattern
            canvas.drawLine(Offset(x - 2, y), Offset(x + 2, y), paint);
            canvas.drawLine(Offset(x, y - 2), Offset(x, y + 2), paint);
            break;
          case 3:
            // Triangle
            final path = Path()
              ..moveTo(x, y - 2.5)
              ..lineTo(x + 2.5, y + 2.5)
              ..lineTo(x - 2.5, y + 2.5)
              ..close();
            canvas.drawPath(path, paint);
            break;
        }
      }
    }

    // Add wavy lines for extra security feel
    final wavePaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;

    for (int i = 0; i < 5; i++) {
      final path = Path();
      final yOffset = i * (size.height / 5);
      path.moveTo(0, yOffset);

      for (double x = 0; x <= size.width; x += 10) {
        final y = yOffset + math.sin(x * 0.1 + i) * 3;
        path.lineTo(x, y);
      }

      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(SecurityPatternPainter oldDelegate) =>
      color != oldDelegate.color || opacity != oldDelegate.opacity;
}

