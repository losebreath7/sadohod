import 'package:flutter/material.dart';

/// The navigation guide chevron; callbacks remain owned by each screen.
class SadohodBackButton extends StatelessWidget {
  const SadohodBackButton({
    super.key, required this.onBack, this.color = Colors.black,
  });
  static const double width = 32;
  static const double height = 28;
  static const double iconSize = 27;
  final VoidCallback onBack;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Назад', button: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onBack,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(width: width, height: height,
          child: Center(child: Icon(Icons.chevron_left, size: iconSize, color: color))),
      ),
    ),
  );
}
