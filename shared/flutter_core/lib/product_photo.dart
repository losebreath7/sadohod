import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Subtle image arrival for feed/gallery tiles. Uses Flutter's image cache.
/// Network decode hints are optional and ignored by web renderers that cannot
/// resize decoded images; they must not be relied on for bandwidth savings.
class SadohodProductPhoto extends StatelessWidget {
  const SadohodProductPhoto({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder = const Color(0xFFF1F1F1),
  });
  final String path;
  final BoxFit fit;
  final int? cacheWidth;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    Widget placeholderView() => ColoredBox(
      color: placeholder,
      child: const Center(child: Icon(Icons.image_outlined,
          color: Color(0xFF777777), size: 24)),
    );

    Widget reveal(BuildContext context, Widget image, int? frame, bool synchronous) {
      return AnimatedOpacity(
        opacity: synchronous || frame != null ? 1 : 0,
        duration: SadohodMotion.imageFade,
        curve: SadohodMotion.curve,
        child: image,
      );
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        cacheWidth: cacheWidth,
        frameBuilder: reveal,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholderView(),
        errorBuilder: (_, _, _) => placeholderView(),
      );
    }
    return Image.asset(
      path,
      fit: fit,
      cacheWidth: cacheWidth,
      frameBuilder: reveal,
      errorBuilder: (_, _, _) => placeholderView(),
    );
  }
}
