import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/product_photo.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/account.dart';
import '../../data/catalog.dart';

/// The buyer shell never adds a second top SafeArea. Each compact header
/// calculates its own position from the device's system top inset.
/// Flutter does not expose the exact Dynamic Island bounding rectangle:
/// for tall iOS insets the obstruction ends above the bottom of the inset.
class BuyerHeaderLayout {
  const BuyerHeaderLayout._(this.obstructionBottom, this.contentTop, this.height);

  static const double gap = 12;
  static const double rowHeight = 28;
  final double obstructionBottom;
  final double contentTop;
  final double height;

  factory BuyerHeaderLayout.forInset(double safeTop) {
    final top = safeTop < 0 ? 0.0 : safeTop;
    // iPhone 16 Pro preview: safeTop=62, Dynamic Island bottom=40.
    // Conventional notches and plain Android status bars differ.
    final obstructionBottom = top >= 55
        ? top - 22
        : top >= 36 ? top - 12 : top;
    final contentTop = obstructionBottom + gap;
    return BuyerHeaderLayout._(
      obstructionBottom, contentTop, contentTop + rowHeight + gap);
  }

  static BuyerHeaderLayout of(BuildContext context) {
    final data = MediaQuery.of(context);
    final top = data.viewPadding.top > data.padding.top
        ? data.viewPadding.top : data.padding.top;
    return BuyerHeaderLayout.forInset(top);
  }
}


/// Original vector artwork exported from approved Figma home frames.
class SvgLogo extends StatelessWidget {
  const SvgLogo(this.asset, {super.key});
  final String asset;
  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/figma/$asset.svg');
}

class DesignIcon extends StatelessWidget {
  const DesignIcon(this.file, {super.key, this.color});
  final String file;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/figma/$file.svg',
    colorFilter: color == null
        ? null
        : ColorFilter.mode(color!, BlendMode.srcIn),
  );
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton(
    this.id, {
    super.key,
    this.seller = false,
    this.small = false,
    this.alignRight = false,
  });
  final String id;
  final bool seller, small, alignRight;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AccountStore.instance,
    builder: (context, _) {
      final a = AccountStore.instance,
          saved = (seller ? a.sellers : a.products).contains(id);
      return IconButton(
        tooltip: saved ? 'Убрать из избранного' : 'В избранное',
        constraints: small
            ? const BoxConstraints(minWidth: 18, minHeight: 17)
            : const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
        alignment: alignRight ? Alignment.centerRight : Alignment.center,
        onPressed: () async {
          await a.toggle(id, seller: seller);
          if (context.mounted && a.syncError != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(a.syncError!)));
          }
        },
        icon: SizedBox(
          width: small ? 16 : 23,
          height: small ? 15 : 21,
          child: FavoriteHeartGlyph(filled: saved),
        ),
      );
    },
  );
}

/// A black heart with a narrow white outline, readable against any photo.
/// No background circle, badge, or other surface is painted behind the heart.
class FavoriteHeartGlyph extends StatelessWidget {
  const FavoriteHeartGlyph({super.key, required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FavoriteHeartPainter(filled: filled),
    size: const Size(24, 24),
  );
}

class _FavoriteHeartPainter extends CustomPainter {
  const _FavoriteHeartPainter({required this.filled});
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final heart = Path()
      ..moveTo(12, 21)
      ..cubicTo(10.6, 19.7, 2, 13.5, 2, 8.4)
      ..cubicTo(2, 5.2, 4.4, 3, 7.5, 3)
      ..cubicTo(9.4, 3, 11, 3.9, 12, 5.1)
      ..cubicTo(13, 3.9, 14.6, 3, 16.5, 3)
      ..cubicTo(19.6, 3, 22, 5.2, 22, 8.4)
      ..cubicTo(22, 13.5, 13.4, 19.7, 12, 21)
      ..close();

    if (filled) {
      canvas.drawPath(heart, Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black
        ..isAntiAlias = true);
      canvas.drawPath(heart, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white
        ..isAntiAlias = true);
    } else {
      // White halo behind the dark outline, not a filled white heart.
      canvas.drawPath(heart, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white
        ..isAntiAlias = true);
      canvas.drawPath(heart, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black
        ..isAntiAlias = true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FavoriteHeartPainter oldDelegate) =>
      oldDelegate.filled != filled;
}

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
        PageView.builder(
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

class SearchCapsule extends StatefulWidget {
  const SearchCapsule({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.controller,
    this.onPhotoTap,
    this.height = 32,
  });
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final VoidCallback? onPhotoTap;
  final double height;

  @override
  State<SearchCapsule> createState() => _SearchCapsuleState();
}

class _SearchCapsuleState extends State<SearchCapsule> {
  TextEditingController? _ownedController;
  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SearchCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(_refresh);
      _controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _ownedController?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    // Do not unfocus: the keyboard and typing cursor stay available.
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    return SizedBox(
      height: widget.height,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        readOnly: widget.onTap != null,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'поиск',
          hintStyle: const TextStyle(color: Color(0xffa5a5a5)),
          isDense: true,
          prefixIconConstraints: const BoxConstraints(minWidth: 33, minHeight: 20),
          prefixIcon: const SizedBox(width: 33, child: Center(child: SizedBox(
            width: 10, height: 10, child: DesignIcon('v082_search_mini')))),
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 24),
          suffixIcon: !hasText && widget.onPhotoTap == null ? null : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                InkWell(
                  key: const ValueKey('search-clear'),
                  onTap: _clear,
                  borderRadius: BorderRadius.circular(20),
                  child: const SizedBox(
                    width: 32, height: 32,
                    child: Center(child: Icon(Icons.close, size: 14,
                        color: Color(0xffa5a5a5))),
                  ),
                ),
              if (widget.onPhotoTap != null)
                IconButton(
                  tooltip: 'Поиск по фотографии',
                  onPressed: widget.onPhotoTap,
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                ),
            ],
          ),
          filled: true,
          fillColor: const Color(0xffeaeaea),
          contentPadding: const EdgeInsets.only(left: 10, right: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class RoundBack extends StatelessWidget {
  const RoundBack({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Назад', button: true,
    child: InkWell(
      onTap: () => context.canPop() ? context.pop() : context.go('/home'),
      child: const SizedBox(width: 25, height: 25, child: DesignIcon('83594')),
    ),
  );
}

class AddressCard extends StatelessWidget {
  const AddressCard(this.seller, {super.key});
  final Seller seller;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/map', extra: seller),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${seller.pavilion} — павильон\n${seller.zone}',
              style: const TextStyle(fontSize: 12, color: Color(0xff6c6c6c)),
            ),
          ),
          const SizedBox(
            width: 32,
            height: 32,
            child: RotatedBox(quarterTurns: 2, child: DesignIcon('8b4c9')),
          ),
        ],
      ),
    ),
  );
}

class DesignHeader extends StatelessWidget {
  const DesignHeader({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    return SizedBox(
    height: header.height,
    child: Stack(
      children: [
        Positioned(
          top: header.height - 114,
          left: -5,
          right: -5,
          child: IgnorePointer(
            child: SizedBox(
              height: 114,
              child: SvgPicture.asset(
                'assets/figma/388b2.svg',
                fit: BoxFit.fill,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            22, header.contentTop, 22, BuyerHeaderLayout.gap),
          child: child,
        ),
      ],
    ),
  );
  }
}

/// Compact header shared by photo search, matches and favourite seller screens.
/// Its shape, spacing and icons follow the approved 390px Figma frames.
class BuyerTopBar extends StatelessWidget {
  const BuyerTopBar({super.key, required this.onBack, this.controller, this.onSubmitted, this.onChanged, this.showSearch = true});
  final VoidCallback onBack;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted, onChanged;
  final bool showSearch;
  @override
  Widget build(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    return Container(
    height: header.height,
    decoration: const BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        30, header.contentTop, 30, BuyerHeaderLayout.gap),
      child: Row(children: [
        GestureDetector(onTap: onBack,
          child: const SizedBox(width: 25, height: 25,
            child: CircleAvatar(backgroundColor: Colors.black,
              child: Icon(Icons.arrow_back, color: Colors.white, size: 17)))),
        if (showSearch) ...[
          const SizedBox(width: 38),
          Expanded(child: SizedBox(height: 25,
            child: SearchCapsule(controller: controller, onChanged: onChanged, onSubmitted: onSubmitted))),
        ] else const Spacer(),
      ]),
    ),
  );
  }
}
