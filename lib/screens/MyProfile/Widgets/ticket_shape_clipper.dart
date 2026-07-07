import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Creates a ticket shape with scalloped edges for a realistic look
class TicketShapeClipper extends CustomClipper<Path> {
  final double holeRadius;
  final double cornerRadius;

  const TicketShapeClipper({this.holeRadius = 8, this.cornerRadius = 12});

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Start from top-left corner with rounded corner
    path.moveTo(cornerRadius, 0);

    // Top edge with scalloped cutouts
    final topScallops = (w - 2 * cornerRadius) ~/ (holeRadius * 4);
    final topScallopWidth = (w - 2 * cornerRadius) / topScallops;

    for (int i = 0; i < topScallops; i++) {
      final x = cornerRadius + i * topScallopWidth;
      path.lineTo(x + topScallopWidth * 0.3, 0);
      path.arcToPoint(
        Offset(x + topScallopWidth * 0.7, 0),
        radius: Radius.circular(holeRadius),
        clockwise: false,
      );
    }

    // Top-right corner
    path.lineTo(w - cornerRadius, 0);
    path.quadraticBezierTo(w, 0, w, cornerRadius);

    // Right edge with notch for tear-off
    path.lineTo(w, h * 0.35);
    path.arcToPoint(
      Offset(w, h * 0.35 + holeRadius * 2),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(w, h * 0.65 - holeRadius);
    path.arcToPoint(
      Offset(w, h * 0.65 + holeRadius),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );

    // Bottom-right corner
    path.lineTo(w, h - cornerRadius);
    path.quadraticBezierTo(w, h, w - cornerRadius, h);

    // Bottom edge with scalloped cutouts
    for (int i = topScallops - 1; i >= 0; i--) {
      final x = cornerRadius + i * topScallopWidth;
      path.lineTo(x + topScallopWidth * 0.7, h);
      path.arcToPoint(
        Offset(x + topScallopWidth * 0.3, h),
        radius: Radius.circular(holeRadius),
        clockwise: false,
      );
    }

    // Bottom-left corner
    path.lineTo(cornerRadius, h);
    path.quadraticBezierTo(0, h, 0, h - cornerRadius);

    // Left edge with notch
    path.lineTo(0, h * 0.65 + holeRadius);
    path.arcToPoint(
      Offset(0, h * 0.65 - holeRadius),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(0, h * 0.35 + holeRadius * 2);
    path.arcToPoint(
      Offset(0, h * 0.35),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );

    // Back to top-left corner
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(TicketShapeClipper oldClipper) =>
      oldClipper.holeRadius != holeRadius ||
      oldClipper.cornerRadius != cornerRadius;
}

/// Painter for perforated line effect
class PerforatedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  const PerforatedLinePainter({
    this.color = Colors.grey,
    this.strokeWidth = 1.0,
    this.dashWidth = 5.0,
    this.dashSpace = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    double currentX = 0;

    while (currentX < size.width) {
      path.moveTo(currentX, 0);
      path.lineTo(math.min(currentX + dashWidth, size.width), 0);
      currentX += dashWidth + dashSpace;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PerforatedLinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashSpace != dashSpace;
}
