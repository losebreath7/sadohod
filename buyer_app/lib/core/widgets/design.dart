import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/account.dart';
import '../../data/catalog.dart';

// The 62px iPhone 16 Pro safe inset is already part of the full-screen
// buyer layout. Compact controls need their own row *below* that inset,
// rather than adding another MediaQuery/SafeArea around the whole screen.
const double buyerCompactHeaderHeight = 100;
const double buyerCompactContentTop = 66;

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
          child: DesignIcon(saved ? 'b2fbd' : 'heart_outline_clean'),
        ),
      );
    },
  );
}

class PhotoGallery extends StatefulWidget {
  const PhotoGallery(this.photos, {super.key, this.radius = 5, this.small = false, this.onTap});
  final List<String> photos;
  final double radius;
  final bool small;
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
        PageView.builder(
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => current = i),
          itemBuilder: (context, i) {
            final url = widget.photos[i];
            Widget failure(BuildContext c, Object e, StackTrace? s) =>
              const ColoredBox(color: Color(0xffeaeaea), child: Center(child: Icon(Icons.broken_image_outlined)));
            return GestureDetector(
              onTap: widget.onTap == null ? null : () => widget.onTap!(i),
              child: url.startsWith('http')
                ? Image.network(url, fit: BoxFit.cover, errorBuilder: failure)
                : Image.asset(url, fit: BoxFit.cover, errorBuilder: failure),
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

class SearchCapsule extends StatelessWidget {
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
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      readOnly: onTap != null,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: 'поиск',
        hintStyle: const TextStyle(color: Color(0xffa5a5a5)),
        isDense: true,
        prefixIconConstraints: const BoxConstraints(minWidth: 33, minHeight: 20),
        prefixIcon: const SizedBox(width: 33, child: Center(child: SizedBox(
          width: 10, height: 10, child: DesignIcon('v082_search_mini')))),
        suffixIcon: onPhotoTap == null ? null : IconButton(
          tooltip: 'Поиск по фотографии',
          onPressed: onPhotoTap,
          constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
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
  Widget build(BuildContext context) => SizedBox(
    height: buyerCompactHeaderHeight,
    child: Stack(
      children: [
        Positioned(
          top: -14,
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
          padding: const EdgeInsets.fromLTRB(22, 52, 22, 0),
          child: child,
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Container(
    height: buyerCompactHeaderHeight,
    decoration: const BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(30, buyerCompactContentTop, 30, 8),
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
