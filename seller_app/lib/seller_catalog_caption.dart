import 'package:flutter/material.dart';
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

  /// Match the buyer catalogue's ruble grouping and no approximation sign.
  static String rubles(int amount) {
    final text = amount.toString();
    final groups = <String>[];
    for (var end = text.length; end > 0; end -= 3) {
      final start = end >= 3 ? end - 3 : 0;
      groups.insert(0, text.substring(start, end));
    }
    return '${groups.join(' ')} ₽';
  }

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
              Text(
                rubles(price!),
                key: const ValueKey('seller-card-price'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BuyerProductType.catalogPrice,
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
