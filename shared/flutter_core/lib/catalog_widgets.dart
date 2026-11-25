import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'display_format.dart';
import 'product_gallery.dart';
import 'market_addresses.dart';

/// Shared catalogue geometry for buyer and courier. Role-specific data,
/// colours and save actions are supplied by the owning application.
class SadohodCatalogTile extends StatelessWidget {
  const SadohodCatalogTile({
    super.key,
    required this.photos,
    required this.address,
    required this.title,
    required this.price,
    required this.onOpen,
    required this.saveAction,
    this.zone = '',
    this.imageFit = BoxFit.cover,
    this.ink = BuyerColors.ink,
    this.muted = BuyerColors.muted,
  });

  final List<String> photos;
  final String address, zone, title;
  final int? price;
  final VoidCallback onOpen;
  final Widget saveAction;
  final BoxFit imageFit;
  final Color ink, muted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Stack(children: [
        PhotoGallery(photos, small: true, fit: imageFit,
          onTap: (_) => onOpen()),
        Positioned(top: 6, right: 6,
          child: SizedBox(width: 28, height: 28, child: saveAction)),
      ]),
      const SizedBox(height: 9),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: GestureDetector(
            onTap: onOpen,
            child: Text(
              marketTerritories.contains(zone.toLowerCase())
                  ? '$zone · $address' : address,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: BuyerProductType.catalogAddress.copyWith(color: ink),
            ),
          )),
          if (price != null) ...[
            const SizedBox(width: 6),
            Flexible(child: Text(
              approximateRubles(price!), maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BuyerProductType.catalogPrice.copyWith(color: ink),
            )),
          ],
        ],
      ),
      const SizedBox(height: 5),
      GestureDetector(onTap: onOpen, child: Text(
        title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: BuyerProductType.catalogTitle.copyWith(color: muted),
      )),
    ],
  );
}

/// A nested grid must never inherit the phone's top safe-area padding.
/// The photo stays square and the two caption rows have 66 logical px.
class SadohodCatalogGrid extends StatelessWidget {
  const SadohodCatalogGrid({
    super.key, required this.itemCount, required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 780 ? 4
          : constraints.maxWidth >= 520 ? 3 : 2;
      final tileWidth = (constraints.maxWidth - (count - 1) * 16) / count;
      final tileHeight = tileWidth + 66;
      return GridView.builder(
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisSpacing: 20,
          crossAxisSpacing: 16,
          childAspectRatio: tileWidth / tileHeight,
        ),
        itemBuilder: itemBuilder,
      );
    },
  );
}
