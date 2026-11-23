enum SellerStatus {
  approved,
  pending,
  paused,
  rejected,
  draft,
  unknown;

  static final _byName = values.asNameMap();

  static SellerStatus read(Object? value) =>
      _byName[value?.toString().toLowerCase()] ?? unknown;
}

class SellerListing {
  SellerListing(this.data);

  final Map<String, dynamic> data;
  String get pavilionId => data['pavilion_id'].toString();
  int? get price => (data['price'] as num?)?.toInt();
  List<String> get saleModes =>
      List<String>.from(data['sale_modes'] ?? ['retail']);
  SellerStatus get status => SellerStatus.read(data['status']);

  // Older records omit published. An explicit false means there is no offer.
  bool get isPublished =>
      (status == SellerStatus.approved || data['status'] == null) &&
      (data['published'] == true ||
          (!data.containsKey('published') && status == SellerStatus.approved));
}

class SellerProduct {
  SellerProduct(Map<String, dynamic> data)
    : status = SellerStatus.read(data['status']),
      listings = [
        for (final entry
            in (data['listings'] as List? ?? const []).whereType<Map>())
          SellerListing(Map<String, dynamic>.from(entry)),
      ];

  final SellerStatus status;
  final List<SellerListing> listings;

  bool get awaitingReview =>
      status == SellerStatus.pending ||
      listings.any((listing) => listing.status == SellerStatus.pending);

  SellerListing? forPavilion(String id) =>
      listings.where((listing) => listing.pavilionId == id).firstOrNull;

  int? priceFor(String id, int? fallback) {
    final existing = forPavilion(id);
    return existing == null ? fallback : existing.price;
  }

  SellerListing? catalogListing({
    String? pavilionId,
    String? saleMode,
    bool hidden = false,
  }) {
    for (final listing in listings) {
      if (pavilionId != null && listing.pavilionId != pavilionId) continue;
      if (saleMode != null && !listing.saleModes.contains(saleMode)) continue;
      if (hidden
          ? listing.status == SellerStatus.paused
          : status == SellerStatus.approved && listing.isPublished) {
        return listing;
      }
    }
    return null;
  }
}
