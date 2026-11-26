import 'dart:async';
import 'package:sadohod_shared_core/catalog_search.dart';
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
  late Future<CatalogSearchResults<DemoProduct>> _allProducts;
  Timer? _debounce;
  bool _pending = false;
  late final TextEditingController _text = TextEditingController(text: widget.textQuery);
  final Set<String> _zones = {};
  bool _filters = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<CatalogSearchResults<DemoProduct>> _searchAndRecord(String query) async {
    final results = await CatalogApi.instance.searchCatalog(query);
    if (results.products.isNotEmpty && AccountStore.instance.signedIn && !CatalogApi.localDemo) {
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
      : CatalogApi.instance.searchCatalog('');
  }

  @override
  void dispose() { _debounce?.cancel(); _text.dispose(); super.dispose(); }

  void _toggle(String zone) => setState(() => _zones.contains(zone) ? _zones.remove(zone) : _zones.add(zone));

  void _onSearchChanged(String value) {
    if (widget.query != null) return;
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _zones.clear();
        _filters = false;
        _pending = false;
        _allProducts = CatalogApi.instance.searchCatalog('');
      });
      return;
    }
    setState(() => _pending = true);
    _debounce = Timer(const Duration(milliseconds:300), () {
      if (!mounted) return;
      setState(() { _pending = false; _allProducts = CatalogApi.instance.searchCatalog(query); });
    });
  }

  String get _resultHeading => widget.query != null ? 'похожие товары'
      : _text.text.trim().isEmpty ? 'результат поиска' : _text.text.trim();

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
        onChanged: _onSearchChanged,
        onSubmitted: (value) { if (value.trim().isNotEmpty) context.push('/results?q=${Uri.encodeQueryComponent(value.trim())}'); },
      ),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(30, 12, 30, 30),
        children: [
          if (_filters)
            MarketFilters(
              title: _resultHeading,
              selectedZones: _zones,
              onToggleZone: _toggle,
              onClose: () => setState(() => _filters = false),
            )
          else
            Row(children: [
              Expanded(child: Text(_resultHeading,
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
            FutureBuilder<CatalogSearchResults<DemoProduct>>(
              future: _allProducts,
              builder: (context, snapshot) {
                if (_pending || snapshot.connectionState != ConnectionState.done) return const LoadingCatalog();
                if (!snapshot.hasData) {
                  if (snapshot.hasError) return ApiFailure(error: snapshot.error!, retry: () => setState(_load));
                  return const LoadingCatalog();
                }
                // Server has already matched title, category hierarchy and
                // available visual semantics. Re-filtering by title here
                // would discard all photo-inferred results without a name.
                final result = snapshot.data!;
                final filtered = result.products.where((p) => productInZones(p,_zones)).toList();
                return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  if(result.sellers.isNotEmpty) SellerSearchStrip(sellers:result.sellers,onOpen:(s)=>context.push('/seller/${Uri.encodeComponent(s.id)}')),
                  if(result.sellers.isNotEmpty && filtered.isNotEmpty) const Padding(padding:EdgeInsets.only(bottom:12),child:Text('товары',style:TextStyle(fontSize:14,fontWeight:FontWeight.w700))),
                  if(filtered.isNotEmpty) ProductGrid(products:filtered)
                  else if(result.sellers.isEmpty) const Center(child:Text('Ничего не найдено')),
                ]);
              },
            ),
        ],
      )),
    ]),
  );
}
