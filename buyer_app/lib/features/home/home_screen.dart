import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../data/catalog.dart';
import '../../data/api.dart';

/// Buyer feed: the opening artwork and the compact search share one scroll view.
/// No second catalogue page, no hard transition, no forced scroll reset.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialQuery = '', this.initialCategory = 'Все'});
  final String initialQuery;
  final String initialCategory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);
  late Future<List<DemoProduct>> _products = CatalogApi.instance.products();
  late String _category = widget.initialCategory;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery) _query.text = widget.initialQuery;
    if (widget.initialCategory != oldWidget.initialCategory) _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  void _backToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 480), curve: Curves.easeOutCubic);
    }
  }

  void _submitSearch(String text) {
    final value = text.trim();
    if (value.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      context.push('/results?q=${Uri.encodeQueryComponent(value)}');
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: CustomScrollView(
      key: const PageStorageKey('buyer-home-feed'),
      controller: _scroll,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SadoHomeHeader(
            controller: _query,
            onChanged: (_) => setState(() {}),
            onSubmitted: _submitSearch,
            onPhotoTap: () => context.push('/search'),
            onLogoTap: _backToTop,
            onTag: (value) => _submitSearch(value),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 21, 30, 30),
          sliver: SliverToBoxAdapter(
            child: FutureBuilder<List<DemoProduct>>(
              future: _products,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ApiFailure(error: snapshot.error!, retry: () => setState(() => _products = CatalogApi.instance.products()));
                }
                if (!snapshot.hasData) return const LoadingCatalog();
                final needle = _query.text.trim().toLowerCase();
                final items = snapshot.data!.where((p) {
                  final categoryMatches = _category == 'Все' || p.category == _category;
                  final queryMatches = needle.isEmpty || '${p.title} ${p.category} ${p.pavilion}'.toLowerCase().contains(needle);
                  return categoryMatches && queryMatches;
                }).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_category != 'Все') Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Align(alignment: Alignment.centerLeft,
                        child: ActionChip(label: Text('$_category ×'), onPressed: () => setState(() => _category = 'Все')),
                      ),
                    ),
                    if (items.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Товары не найдены')))
                    else ...[
                      ProductGrid(products: items.take(4).toList()),
                      if (items.length > 4) ...[
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: AspectRatio(
                            aspectRatio: 330 / 180,
                            child: Semantics(
                              label: 'Рекламное место, демонстрация',
                              child: Image.asset('assets/figma/e221c.png', fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ProductGrid(products: items.skip(4).toList()),
                      ],
                    ],
                    if (CatalogApi.localDemo) const Padding(padding: EdgeInsets.only(top: 22), child: DemoNotice()),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

/// One text field travels from the large opening layout into the pinned header.
/// No duplicated TextField, no opacity switch between two search controls.
class _SadoHomeHeader extends SliverPersistentHeaderDelegate {
  _SadoHomeHeader({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPhotoTap,
    required this.onLogoTap,
    required this.onTag,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged, onSubmitted, onTag;
  final VoidCallback onPhotoTap, onLogoTap;
  static const double _max = 402;
  static const double _min = 75;

  @override
  double get minExtent => _min;
  @override
  double get maxExtent => _max;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final offset = shrinkOffset.clamp(0.0, _max - _min).toDouble();
    // Search moves with the scroll until it docks at the top; then its width
    // changes continuously to make room for the compact Figma logo.
    final dock = ((offset - 182) / 54).clamp(0.0, 1.0).toDouble();
    final curve = Curves.easeInOutCubic.transform(dock);
    final shape = ((offset - 200) / 105).clamp(0.0, 1.0).toDouble();
    // The pin mask is drawn ABOVE the scrolling intro, not behind it.
    // Otherwise the photo tile and tag chips bleed into the docked search
    // when the sliver collapses (particularly visible on iOS Safari).
    final pinnedCover = ((offset - 55) / 55).clamp(0.0, 1.0).toDouble();
    final searchTop = (275 - offset).clamp(39.0, 275.0).toDouble();
    final left = 30 + 63 * curve;
    final searchHeight = 32 - 7 * curve;
    final width = MediaQuery.sizeOf(context).width;
    // Figma screen is 390 px wide. Keep the specified gutters on wider phones.
    final availableWidth = (width - left - 30).clamp(50.0, double.infinity);
    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        // The open header is flat white; its pinned 75 px end state uses the
        // original exported white cutout shape, not a Material border radius.
        Positioned.fill(child: Opacity(opacity: 1 - shape,
          child: const ColoredBox(color: Colors.white))),
        Positioned(
          top: -offset, left: 30, right: 30, height: _max,
          child: IgnorePointer(
            ignoring: offset > 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 58),
                Center(child: SizedBox(width: 98, height: 13,
                  child: SvgPicture.asset('assets/figma/sadohod_wordmark.svg',
                    width: 98, height: 13, fit: BoxFit.contain))),
                const SizedBox(height: 16),
                const Text('находи и забирай   //   без посредников',
                  style: TextStyle(fontSize: 12, color: Color(0xff6c6c6c))),
                const SizedBox(height: 2),
                const Text('11 тыс. магазинов садовода в одном месте',
                  style: TextStyle(fontSize: 12, color: Color(0xff6c6c6c))),
                const SizedBox(height: 15),
                Material(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: onPhotoTap,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 126, width: double.infinity,
                      child: Stack(children: [
                        const Positioned(top: 11, left: 11,
                          child: SizedBox(width: 27, height: 27,
                            child: SvgLogo('sadohod_photo_grid'))),
                        Positioned(right: 12, top: 11,
                          child: Opacity(opacity: .35, child: Image.asset(
                            'assets/figma/38630.png', width: 105, height: 99,
                            fit: BoxFit.cover))),
                        const Positioned(left: 9, bottom: 12,
                          child: Text('найти по фото', style: TextStyle(
                            fontSize: 22, letterSpacing: -.44,
                            color: Colors.white, fontWeight: FontWeight.bold))),
                      ]),
                    ),
                  ),
                ),
                // The SearchCapsule is positioned separately below so it is
                // the SAME actual control before, during, and after collapse.
                const SizedBox(height: 74),
                const Text('найти по тегам', style: TextStyle(
                  fontSize: 12, color: Color(0xff6c6c6c))),
                const SizedBox(height: 9),
                SizedBox(height: 22, child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [for (final tag in [
                    'брюки', 'верхняя одежда', 'головные уборы', 'футболки', 'обувь'
                  ]) Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: const Color(0xffeaeaea),
                      borderRadius: BorderRadius.circular(11),
                      child: InkWell(
                        onTap: () => onTag(tag),
                        borderRadius: BorderRadius.circular(11),
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 11),
                          child: Center(child: Text(tag, style: const TextStyle(
                            fontSize: 12, height: 1, color: Color(0xff343434))))),
                      ),
                    ),
                  )],
                )),
              ],
            ),
          ),
        ),
        // A real foreground mask for the pinned 75 px zone. The original
        // Figma SVG now occludes the intro as it scrolls UNDER the navbar.
        // Keeping it below the search/logo in stack order leaves those
        // controls crisp, while never showing ghost tags over the search.
        if (pinnedCover > 0)
          Positioned(left: -4, right: -4, top: -39, height: 114,
            child: IgnorePointer(child: Opacity(opacity: pinnedCover,
              child: SvgPicture.asset('assets/figma/388b2.svg', fit: BoxFit.fill)))),
        // Exact source emblem from Figma's collapsed header (25x25).
        Positioned(top: 39, left: 30, width: 25, height: 25,
          child: IgnorePointer(
            ignoring: dock < .90,
            child: Opacity(opacity: curve,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLogoTap,
                child: const DesignIcon('v082_compact_logo'),
              )),
          )),
        Positioned(
          left: left, top: searchTop, width: availableWidth, height: searchHeight,
          child: SearchCapsule(
            controller: controller,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            height: searchHeight,
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _SadoHomeHeader old) =>
      old.controller != controller || old.onChanged != onChanged ||
      old.onSubmitted != onSubmitted || old.onPhotoTap != onPhotoTap ||
      old.onLogoTap != onLogoTap || old.onTag != onTag;
}
