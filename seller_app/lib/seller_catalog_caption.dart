import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

/// Use the same two-line caption layout as a buyer's ProductTile:
/// pavilion and price together, then the item name.
class SellerCatalogCaption extends StatelessWidget {
  const SellerCatalogCaption({
    required this.address,
    required this.price,
    required this.title,
    super.key,
  });

  final String address;
  final int? price;
  final String title;

  /// Match the buyer catalogue's ruble grouping with an approximation sign.
  static String rubles(int amount) => approximateRubles(amount);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 11,
              child: Text(
                address,
                key: const ValueKey('seller-card-address'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BuyerProductType.catalogAddress,
              ),
            ),
            if (price != null) ...[
              const SizedBox(width: 6),
              Flexible(
                flex: 9,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    rubles(price!),
                    key: const ValueKey('seller-card-price'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: BuyerProductType.catalogPrice,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          title.trim().isEmpty ? 'Без названия' : title.trim(),
          key: const ValueKey('seller-card-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: BuyerProductType.catalogTitle,
        ),
      ],
    ),
  );
}

/// Address information comes from a merchant listing, not from the product.
/// Some older API records lack the embedded pavilion, so resolve by the same
/// pavilion_id from the merchant's already approved pavilion list.
String sellerListingAddress(
  Map<String, dynamic>? listing,
  List<Map<String, dynamic>> approvedPavilions,
) {
  if (listing == null) return '';
  final attached = listing['pavilion'];
  if (attached is Map) {
    final code = '${attached['code'] ?? ''}'.trim();
    if (code.isNotEmpty) return code;
  }
  final pavilionId = listing['pavilion_id']?.toString();
  if (pavilionId == null || pavilionId.isEmpty) return '';
  for (final row in approvedPavilions) {
    if (row['id']?.toString() == pavilionId) {
      return '${row['code'] ?? ''}'.trim();
    }
  }
  return '';
}
