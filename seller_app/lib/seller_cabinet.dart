import 'api.dart';

typedef RowData = Map<String, dynamic>;

// The API may omit status for already approved pavilion records.
// Explicit pending/rejected statuses must never unlock the product catalogue.
bool isApprovedPavilion(RowData pavilion) {
  final status = '${pavilion['status'] ?? 'approved'}'.trim().toLowerCase();
  return status == 'approved' || status == 'active';
}

List<RowData> rows(dynamic value) => (value is List ? value : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

class SellerCabinet {
  SellerCabinet(
    this.account,
    this.merchant,
    this.pavilions,
    this.requests,
    this.products,
  );

  final RowData account, merchant;
  final List<RowData> pavilions, requests, products;

  static Future<SellerCabinet> load(SellerApi api) async {
    final token = api.token;
    final account = await api.call('/account');
    if (api.token != token) throw StateError('Аккаунт изменился');
    final merchant = await api.call('/merchant/me');
    if (api.token != token) throw StateError('Аккаунт изменился');
    final hasShop = merchant['shop'] != null;
    final catalog = hasShop
        ? await Future.wait([
            api.call('/merchant/pavilions'),
            api.call('/merchant/products'),
          ])
        : <RowData>[];
    final requests =
        rows(hasShop ? catalog.first['requests'] : merchant['applications'])
            .where((r) => r['status'] != 'approved')
            .map(
              (r) => {
                ...r,
                '_requestType': hasShop ? 'pavilion' : 'application',
              },
            )
            .toList();
    return SellerCabinet(
      account,
      merchant,
      hasShop
          ? rows(catalog.first['items']).where(isApprovedPavilion).toList()
          : [],
      requests,
      hasShop ? rows(catalog.last['items']) : [],
    );
  }
}
