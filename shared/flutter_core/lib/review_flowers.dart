import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Original review flower vectors exported from Figma Page 1:
/// 134:160, 134:161, 134:162, 134:163, 134:159.
/// The painter-generated approximation was removed.
const reviewColors = [
  Color(0xff569365),
  Color(0xfff4cb5e),
  Color(0xff89aacF),
  Color(0xffff6480),
  Color(0xffeb8f5e),
];

const reviewFlowerAssets = [
  'assets/figma/review_green.svg',
  'assets/figma/review_yellow.svg',
  'assets/figma/review_blue.svg',
  'assets/figma/review_pink.svg',
  'assets/figma/review_orange.svg',
];

class ReviewFlower extends StatelessWidget {
  const ReviewFlower({super.key, required this.index, this.fill = 1, this.size = 19});
  final int index;
  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = reviewFlowerAssets[index];
    final fraction = fill.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        SvgPicture.asset(asset, width: size, height: size,
          colorFilter: const ColorFilter.mode(
            Color(0xffd9d9d9), BlendMode.srcIn)),
        if (fraction > 0)
          SizedBox(
            width: size * fraction,
            height: size,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: size, maxWidth: size,
                minHeight: size, maxHeight: size,
                child: SvgPicture.asset(asset, width: size, height: size),
              ),
            ),
          ),
      ]),
    );
  }
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
          ReviewFlower(index: i,
            fill: (rating - i).clamp(0.0, 1.0), size: size),
          if (i != 4) const SizedBox(width: 3),
        ],
      ],
    )),
  );
}

/// Common heading geometry for public seller and courier reviews.
class ReviewStripHeading extends StatelessWidget {
  const ReviewStripHeading({super.key, required this.average});
  final double? average;
  static const double cardGap = 8;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 28),
    child: Align(
      alignment: Alignment.bottomLeft,
      heightFactor: 1,
      child: average == null
        ? const Text('нет отзывов', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Text(average!.toStringAsFixed(1), style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            ReviewRatingFlowers(rating: average!, size: 12),
          ]),
    ),
  );
}
