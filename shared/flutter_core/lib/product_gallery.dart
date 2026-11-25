import 'package:flutter/material.dart';
import 'product_photo.dart';

class PhotoGallery extends StatefulWidget {
  const PhotoGallery(this.photos, {super.key, this.radius = 5, this.small = false, this.fit = BoxFit.cover, this.onTap});
  final List<String> photos;
  final double radius;
  final bool small;
  final BoxFit fit;
  final ValueChanged<int>? onTap;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  int current = 0;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(fit: StackFit.expand, children: [
        if (!widget.small && widget.fit == BoxFit.contain)
          const ColoredBox(color: Color(0xffeaeaea)),
        if (widget.photos.isEmpty)
          const ColoredBox(color: Color(0xFFEAEAEA), child: Center(child: Icon(Icons.image_outlined, color: Color(0xff777777), size: 24)))
        else PageView.builder(
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => current = i),
          itemBuilder: (context, i) {
            final url = widget.photos[i];
            return GestureDetector(
              onTap: widget.onTap == null ? null : () => widget.onTap!(i),
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(
                  child: SadohodProductPhoto(
                    path: url,
                    fit: widget.small ? BoxFit.cover : widget.fit,
                    placeholder: const Color(0xFFEAEAEA),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.photos.length > 1)
          Positioned(bottom: widget.small ? 7 : 10, left: 0, right: 0,
            child: IgnorePointer(child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (int i = 0; i < widget.photos.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: widget.small ? 4 : 8,
                  height: widget.small ? 4 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current ? Colors.white : const Color(0xffc9c9c9),
                  ),
                ),
              ],
            )),
          ),
      ]),
    ),
  );
}

