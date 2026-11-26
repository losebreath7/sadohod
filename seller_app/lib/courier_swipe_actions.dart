import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

/// Geometry from Figma 804:1072. Icons remain original exported vectors.
class CourierSwipeAction extends StatelessWidget {
  const CourierSwipeAction({
    super.key, required this.label, required this.onTap,
    this.icon, this.remove = false, this.collect = false, this.checked = false,
  });
  static const double width = 50;
  static const double height = 56;
  static const double gap = 6;
  static const double reveal = width * 2 + gap * 2;
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool remove, collect, checked;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: label,
    child: SizedBox(width: width, height: height,
      child: Material(
        color: remove ? Colors.transparent : SellerColors.blue,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: remove
            ? SvgPicture.asset('assets/figma/courier_swipe_delete.svg', fit: BoxFit.fill)
            : Center(child: collect
              ? Stack(alignment: Alignment.center, children: [
                  SvgPicture.asset('assets/figma/courier_swipe_collect.svg'),
                  if (checked) const Icon(Icons.check, size: 14, color: Colors.white),
                ])
              : Icon(icon, size: 20, color: Colors.white)),
        ),
      ),
    ),
  );
}
