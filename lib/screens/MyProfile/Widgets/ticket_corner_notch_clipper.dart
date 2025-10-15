import 'package:flutter/material.dart';

/// Custom clipper that creates corner notches like real concert tickets
class TicketCornerNotchClipper extends CustomClipper<Path> {
  final double notchRadius;
  final double cornerRadius;

  TicketCornerNotchClipper({
    this.notchRadius = 12.0,
    this.cornerRadius = 20.0,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Start from top-left, after the corner radius and notch
    path.moveTo(cornerRadius + notchRadius, 0);

    // Top edge to top-right corner
    path.lineTo(w - cornerRadius - notchRadius, 0);

    // Top-right corner notch (circular cutout)
    path.arcToPoint(
      Offset(w - cornerRadius, notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Top-right corner radius
    path.arcToPoint(
      Offset(w, cornerRadius),
      radius: Radius.circular(cornerRadius),
    );

    // Right edge to bottom-right corner
    path.lineTo(w, h - cornerRadius - notchRadius);

    // Bottom-right corner notch (circular cutout)
    path.arcToPoint(
      Offset(w - notchRadius, h - cornerRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Bottom-right corner radius
    path.arcToPoint(
      Offset(w - cornerRadius, h),
      radius: Radius.circular(cornerRadius),
    );

    // Bottom edge to bottom-left corner
    path.lineTo(cornerRadius + notchRadius, h);

    // Bottom-left corner notch (circular cutout)
    path.arcToPoint(
      Offset(cornerRadius, h - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Bottom-left corner radius
    path.arcToPoint(
      Offset(0, h - cornerRadius),
      radius: Radius.circular(cornerRadius),
    );

    // Left edge to top-left corner
    path.lineTo(0, cornerRadius + notchRadius);

    // Top-left corner notch (circular cutout)
    path.arcToPoint(
      Offset(notchRadius, cornerRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Top-left corner radius
    path.arcToPoint(
      Offset(cornerRadius, 0),
      radius: Radius.circular(cornerRadius),
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(TicketCornerNotchClipper oldClipper) =>
      notchRadius != oldClipper.notchRadius ||
      cornerRadius != oldClipper.cornerRadius;
}

