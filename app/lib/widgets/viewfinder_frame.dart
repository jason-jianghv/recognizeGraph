import 'package:flutter/material.dart';

/// 白色四角取景框描边（拍照 / 相册对准共用）。
class ViewfinderCornerFrame extends StatelessWidget {
  const ViewfinderCornerFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: ViewfinderCornerPainter());
  }
}

class ViewfinderCornerPainter extends CustomPainter {
  const ViewfinderCornerPainter();

  static const _stroke = 3.0;
  static const _arm = 28.0;
  static const _radius = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final r = _radius;
    final a = _arm;

    canvas.drawPath(
      Path()
        ..moveTo(0, a)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
        ..lineTo(a, 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - a, 0)
        ..lineTo(w - r, 0)
        ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
        ..lineTo(w, a),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h - a)
        ..lineTo(0, h - r)
        ..arcToPoint(Offset(r, h), radius: Radius.circular(r), clockwise: false)
        ..lineTo(a, h),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - a, h)
        ..lineTo(w - r, h)
        ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r), clockwise: false)
        ..lineTo(w, h - a),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
