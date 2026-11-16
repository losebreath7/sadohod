import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/filters.dart';
import '../../data/account.dart';
import '../../data/api.dart';
import '../../data/catalog.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.sellers = false});
  final bool sellers;
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<DemoProduct>> _products = CatalogApi.instance.products();
  late final TextEditingController _search = TextEditingController();
  final Set<String> _zones = {};
  bool _filters = false;
  bool _oneStore = false;
  Future<List<SellerPage?>>? _savedSellerPages;
  String _savedSellerIds = '';

  @override
  void dispose() { _search.dispose(); super.dispose(); }
  void _toggleZone(String zone) => setState(() => _zones.contains(zone) ? _zones.remove(zone) : _zones.add(zone));
  void _toTop() => context.go('/home');

  Widget _productsContent(List<DemoProduct> original, AccountStore a) {
    final needle = _search.text.trim().toLowerCase();
    final saved = original.where((p) => a.products.contains(p.id) && productInZones(p, _zones) &&
      (needle.isEmpty || '${p.title} ${p.category} ${p.pavilion}'.toLowerCase().contains(needle))).toList();
    if (saved.isEmpty) return const Padding(padding: EdgeInsets.only(top: 28),
      child: Center(child: Text('Пока нет избранных товаров', style: TextStyle(fontSize: 12))));
    if (!_oneStore) return ProductGrid(products: saved);

    // Do NOT select a seller. Rearrange the whole favourites feed by seller,
    // then by pavilion, in the stable order of their first appearance.
    // The only visible group headings are pavilion codes, never seller names.
    final groups = <String, Map<String, List<DemoProduct>>>{};
    for (final p in saved) {
      final offers = p.availableOffers;
      if (offers.isEmpty) {
        // Demo/legacy item without structured offers.
        final sellerKey = p.sellerId.isNotEmpty ? p.sellerId : 'unknown:${p.pavilion}';
        groups.putIfAbsent(sellerKey, () => <String, List<DemoProduct>>{})
          .putIfAbsent(p.pavilion, () => []).add(p);
        continue;
      }
      // A saved product may be offered by several sellers or pavilions.
      // Show each physical location in its own address section.
      for (final offer in offers) {
        final sellerSections = groups.putIfAbsent(offer.seller.id, () => <String, List<DemoProduct>>{});
        final products = sellerSections.putIfAbsent(offer.pavilion, () => []);
        if (!products.any((item) => item.id == p.id)) products.add(p.forOffer(offer));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final entry in groups.entries)
        for (final pavilion in (entry.value.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))) ...[
          Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Text(pavilion.key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
          ProductGrid(products: pavilion.value),
        ],
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AccountStore.instance,
    builder: (context, _) {
      final a = AccountStore.instance;
      return ColoredBox(
        color: const Color(0xfff1f1f1),
        child: Column(children: [
          if (widget.sellers) Container(
            height: 75,
            decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
            padding: const EdgeInsets.only(top: 35),
            alignment: Alignment.center,
            child: const Text('любимые продавцы', style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold)),
          ) else Container(
            height: 75,
            decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
            padding: const EdgeInsets.fromLTRB(30, 39, 30, 10),
            child: Row(children: [
              GestureDetector(onTap: _toTop,
                child: const SizedBox(width: 40, height: 28, child: Center(
                  child: SizedBox(width: 28, height: 28, child: DesignIcon('f4579'))))),
              const SizedBox(width: 23),
              Expanded(child: SearchCapsule(controller: _search, onChanged: (_) => setState(() {}))),
            ]),
          ),
          if (widget.sellers) Padding(
            padding: const EdgeInsets.fromLTRB(30, 14, 30, 3),
            child: SearchCapsule(controller: _search,
              onChanged: (_) => setState(() {})),
          ),
          Expanded(child: ListView(
            padding: EdgeInsets.fromLTRB(30, widget.sellers ? 12 : 10, 30, 24),
            children: [
              if (widget.sellers)
                const SizedBox.shrink()
              else if (_filters)
                MarketFilters(title: 'избранное', selectedZones: _zones,
                  onToggleZone: _toggleZone, onClose: () => setState(() => _filters = false),
                  oneStore: _oneStore, onToggleOneStore: () => setState(() => _oneStore = !_oneStore))
              else
                Row(children: [
                  const Expanded(child: Text('избранное',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  IconButton(
                    onPressed: () => setState(() => _filters = true),
                    tooltip: 'Фильтры избранного', icon: const Icon(Icons.tune, size: 22)),
                ]),
              SizedBox(height: widget.sellers ? 0 : 15),
              if (!a.signedIn)
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(onTap: () => context.go('/account'),
                    child: const Text('Войти, чтобы сохранить избранное на других устройствах',
                      style: TextStyle(fontSize: 11, color: Color(0xff6c6c6c))))),
              if (a.syncError != null)
                Text(a.syncError!, style: const TextStyle(color: Colors.red, fontSize: 11)),
              if (widget.sellers)
                _sellerItems(a)
              else
                FutureBuilder<List<DemoProduct>>(
                  future: _products,
                  builder: (context, s) {
                    if (s.hasError) return ApiFailure(error: s.error!,
                      retry: () => setState(() => _products = CatalogApi.instance.products()));
                    if (!s.hasData) return const LoadingCatalog();
                    return _productsContent(s.data!, a);
                  },
                ),
            ],
          )),
        ]),
      );
    },
  );

  Widget _sellerItems(AccountStore a) {
    final saved = a.sellers.toList();
    if (saved.isEmpty) return const Padding(padding: EdgeInsets.only(top: 30),
      child: Text('Сохранённые продавцы появятся здесь.', textAlign: TextAlign.center));
    final savedKey = saved.join('|');
    if (_savedSellerPages == null || _savedSellerIds != savedKey) {
      _savedSellerIds = savedKey;
      _savedSellerPages = Future.wait(saved.map((id) => CatalogApi.instance.seller(id)));
    }
    return FutureBuilder<List<SellerPage?>>(
      future: _savedSellerPages,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoadingCatalog();
        final items = snapshot.data!.whereType<SellerPage>().where((p) =>
          p.seller.name.toLowerCase().contains(_search.text.trim().toLowerCase())).toList();
        return LayoutBuilder(builder: (context, constraints) {
          final width = (constraints.maxWidth - 30) / 2;
          return Wrap(spacing: 30, runSpacing: 18, children: [
            for (final item in items)
              SizedBox(width: width, child: InkWell(
                onTap: () => context.push('/seller/${item.seller.id}'),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CircleAvatar(backgroundColor: Color(0xffd9d9d9), radius: 13.5,
                    child: Icon(Icons.person, size: 17, color: Color(0xff888888))),
                  const SizedBox(width: 7),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.seller.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                    _FavoriteSellerTag(id: item.seller.id),
                  ])),
                ]),
              )),
          ]);
        });
      },
    );
  }
}

class _FavoriteSellerTag extends StatefulWidget {
  const _FavoriteSellerTag({required this.id});
  final String id;
  @override
  State<_FavoriteSellerTag> createState() => _FavoriteSellerTagState();
}

class _FavoriteSellerTagState extends State<_FavoriteSellerTag> {
  String tag = '';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!AccountStore.instance.signedIn) return;
    try {
      final note = await AccountStore.instance.request('/sellers/${widget.id}/my-note', method: 'GET');
      if (mounted) setState(() => tag = note['text']?.toString() ?? '');
    } catch (_) { if (mounted) setState(() => tag = ''); }
  }
  @override
  Widget build(BuildContext context) => Text(tag,
    maxLines: 2, overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 11, color: Color(0xff6c6c6c)));
}
