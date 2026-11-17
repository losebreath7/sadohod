import 'dart:math' as math;
import 'package:flutter/material.dart';

const reviewColors = [
  Color(0xff569d70), Color(0xfff3c953), Color(0xff91b7db),
  Color(0xfff06b89), Color(0xffe68a5b),
];

class ReviewFlower extends StatelessWidget {
  const ReviewFlower({super.key, required this.color, this.fill = 1, this.size = 19});
  final Color color;
  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _FlowerPainter(color, fill.clamp(0, 1))),
  );
}

class _FlowerPainter extends CustomPainter {
  const _FlowerPainter(this.color, this.fill);
  final Color color;
  final double fill;

  void _draw(Canvas canvas, Size size, Color ink) {
    final side = size.shortestSide;
    final paint = Paint()..color = ink;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    for (var i = 0; i < 5; i++) {
      canvas.save();
      canvas.rotate(2 * math.pi * i / 5);
      canvas.drawOval(Rect.fromCenter(
        center: Offset(0, -side * .23),
        width: side * .48, height: side * .57,
      ), paint);
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, side * .16, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, size, const Color(0xffd8d8d8));
    if (fill <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fill, size.height));
    _draw(canvas, size, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.color != color || old.fill != fill;
}

class ReviewRatingFlowers extends StatelessWidget {
  const ReviewRatingFlowers({super.key, required this.rating, this.size = 17});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Оценка ${rating.toStringAsFixed(1)} из 5',
    child: ExcludeSemantics(child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) ...[
          ReviewFlower(color: reviewColors[i],
            fill: (rating - i).clamp(0.0, 1.0), size: size),
          if (i != 4) const SizedBox(width: 3),
        ],
      ],
    )),
  );
}
