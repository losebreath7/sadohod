import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/filters.dart';
import '../../data/api.dart';
import '../../data/account.dart';
import '../../data/catalog.dart';

/// Both image and text search use the same approved Figma grid.
/// Similarity is intentionally not displayed as a confidence percentage.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({this.query, this.textQuery = '', super.key});
  final ImageSearchQuery? query;
  final String textQuery;
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  Future<ImageSearchResponse>? _imageSearch;
  late Future<List<DemoProduct>> _allProducts;
  late final TextEditingController _text = TextEditingController(text: widget.textQuery);
  final Set<String> _zones = {};
  bool _filters = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<DemoProduct>> _searchAndRecord(String query) async {
    final results = await CatalogApi.instance.searchText(query);
    if (results.isNotEmpty && AccountStore.instance.signedIn && !CatalogApi.localDemo) {
      unawaited(_recordSearch(query));
    }
    return results;
  }

  Future<void> _recordSearch(String query) async {
    try {
      final response = await AccountStore.instance.request(
        '/account/interests/search', body: {'query': query});
      if (response['tracked'] == true) AccountStore.instance.interestViewed();
    } catch (_) {
      // Tracking failures never interrupt search results.
    }
  }

  void _load() {
    _imageSearch = widget.query == null ? null : CatalogApi.instance.searchImage(widget.query!.bytes, crop: widget.query!.crop);
    _allProducts = widget.query == null && widget.textQuery.trim().isNotEmpty
      ? _searchAndRecord(widget.textQuery)
      : CatalogApi.instance.products();
  }

  @override
  void dispose() { _text.dispose(); super.dispose(); }

  void _toggle(String zone) => setState(() => _zones.contains(zone) ? _zones.remove(zone) : _zones.add(zone));

  Widget _listing(List<DemoProduct> products) {
    final list = products.where((p) => productInZones(p, _zones)).toList();
    if (list.isEmpty) return const Padding(
      padding: EdgeInsets.only(top: 50),
      child: Center(child: Text('Похожих товаров пока нет', style: TextStyle(fontSize: 12, color: Color(0xff6c6c6c)))));
    return ProductGrid(products: list);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: Column(children: [
      BuyerTopBar(
        controller: _text,
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
        onSubmitted: (value) { if (value.trim().isNotEmpty) context.push('/results?q=${Uri.encodeQueryComponent(value.trim())}'); },
      ),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(30, 12, 30, 30),
        children: [
          if (_filters)
            MarketFilters(
              title: widget.query != null ? 'похожие товары' : (widget.textQuery.isEmpty ? 'результат поиска' : widget.textQuery),
              selectedZones: _zones,
              onToggleZone: _toggle,
              onClose: () => setState(() => _filters = false),
            )
          else
            Row(children: [
              Expanded(child: Text(widget.query != null ? 'похожие товары'
                : widget.textQuery.isEmpty ? 'результат поиска' : widget.textQuery,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -.44))),
              IconButton(
                onPressed: () => setState(() => _filters = true),
                icon: const Icon(Icons.tune, size: 25),
                tooltip: 'Фильтры',
              ),
            ]),
          const SizedBox(height: 12),
          if (_imageSearch != null)
            FutureBuilder<ImageSearchResponse>(
              future: _imageSearch,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  if (snapshot.hasError) return ApiFailure(error: snapshot.error!, retry: () => setState(_load));
                  return const LoadingCatalog();
                }
                return _listing(snapshot.data!.matches.map((m) => m.product).toList());
              },
            )
          else
            FutureBuilder<List<DemoProduct>>(
              future: _allProducts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  if (snapshot.hasError) return ApiFailure(error: snapshot.error!, retry: () => setState(_load));
                  return const LoadingCatalog();
                }
                // Server has already matched title, category hierarchy and
                // available visual semantics. Re-filtering by title here
                // would discard all photo-inferred results without a name.
                return _listing(snapshot.data!);
              },
            ),
        ],
      )),
    ]),
  );
}
