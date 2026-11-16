import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../data/catalog.dart';
import '../../data/api.dart';

// Original Figma wordmark embedded as SVG data so a stale/missing web asset
// cannot silently replace the brand logo with a system-font fallback.
const String _homeWordmarkVector = r'''<svg width="98" height="13" viewBox="0 0 98 13" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M57.1149 12.8329L61.5422 6.44279L57.1814 0.126709L61.2277 0.131701L63.5599 3.54144L65.9263 0.131701H69.9592L65.5851 6.44279L69.995 12.8329L66.0003 12.8645L63.5608 9.34581L61.1511 12.8329H57.1157H57.1149Z" fill="black"/>
<path d="M76.0473 0.00927734C72.4678 0.00927734 69.5565 2.92145 69.5565 6.50009C69.5565 10.0787 72.4678 12.9909 76.0473 12.9909C79.6267 12.9909 82.5381 10.0787 82.5381 6.50009C82.5381 2.92145 79.6267 0.00927734 76.0473 0.00927734ZM79.3538 6.50009C79.3538 8.32311 77.8711 9.80666 76.0473 9.80666C74.2234 9.80666 72.7407 8.32311 72.7407 6.50009C72.7407 4.67707 74.2234 3.19353 76.0473 3.19353C77.8711 3.19353 79.3538 4.67707 79.3538 6.50009Z" fill="black"/>
<path d="M9.61901 7.49677C9.45676 7.99932 9.18468 8.44281 8.81109 8.81639C8.18622 9.44043 7.35667 9.78573H6.47054C5.59023 9.78656 4.76234 9.44376 4.1408 8.82222C3.5176 8.19901 3.17562 7.37112 3.17646 6.48832C3.17812 5.60635 3.52259 4.77596 4.14746 4.15193C4.77149 3.52706 5.60188 3.18259 6.48385 3.18092H6.48801C7.36832 3.18092 8.19538 3.52373 8.81692 4.14527C9.18967 4.51803 9.46009 4.96151 9.62151 5.4624L9.64896 5.54727L12.8956 5.54311L12.8723 5.40083C12.6502 4.06373 12.027 2.85143 11.0693 1.89374C9.84783 0.672297 8.22367 0 6.4955 0H6.48718C4.75569 0.00249615 3.12653 0.678121 1.90093 1.90456C-0.629336 4.43482 -0.634329 8.54847 1.89011 11.0729C3.15066 12.3335 4.80644 12.9633 6.46388 12.9633C8.12132 12.9633 9.79125 12.3293 11.0585 11.0621C12.0178 10.1027 12.6443 8.88795 12.8698 7.55001L12.894 7.4069L9.6473 7.41106L9.61985 7.49593L9.61901 7.49677Z" fill="black"/>
<path d="M50.9469 0.0251465C47.3683 0.0251465 44.4561 2.92983 44.4561 6.50015C44.4561 10.0705 47.3683 12.9752 50.9469 12.9752C54.5256 12.9752 57.4377 10.0705 57.4377 6.50015C57.4377 2.92983 54.5264 0.0251465 50.9469 0.0251465ZM54.2535 6.50015C54.2535 8.31901 52.7708 9.7984 50.9469 9.7984C49.1231 9.7984 47.6404 8.31901 47.6404 6.50015C47.6404 4.68129 49.1239 3.20191 50.9469 3.20191C52.77 3.20191 54.2535 4.68129 54.2535 6.50015Z" fill="black"/>
<path d="M27.3441 0.131752H24.2772V1.25751C23.2089 0.48537 21.9 0.0244141 20.4831 0.0244141C16.9044 0.0244141 13.9922 2.9291 13.9922 6.49942C13.9922 10.0697 16.9044 12.9744 20.4831 12.9744C21.9 12.9744 23.2089 12.5135 24.2772 11.7413V12.8471H27.5871V0.130086H27.3441V0.131752ZM20.4822 9.7985C18.6592 9.7985 17.1757 8.31911 17.1757 6.50025C17.1757 4.68139 18.6592 3.20201 20.4822 3.20201C22.3053 3.20201 23.7888 4.68139 23.7888 6.50025C23.7888 8.31911 22.3053 9.7985 20.4822 9.7985Z" fill="black"/>
<path d="M44.05 9.53802H42.6596V0.149171C39.3938 0.149171 35.7869 0.126709 32.5211 0.126709C31.7914 3.26353 31.0617 6.40119 30.332 9.53802H28.9417V12.8504H44.0225V12.8487H44.05V9.53885V9.53802ZM35.2802 2.91241H39.3464L39.3356 9.53885H33.7367C34.251 7.32976 34.766 5.1215 35.2802 2.91241Z" fill="black"/>
<path d="M97.8262 9.53802H96.4358V0.149171C93.17 0.149171 89.5631 0.126709 86.2973 0.126709C85.5676 3.26353 84.8379 6.40119 84.1082 9.53802H82.7178V12.8504H97.7987V12.8487H97.8262V9.53885V9.53802ZM89.0564 2.91241H93.1226L93.1118 9.53885H87.5129C88.0271 7.32976 88.5422 5.1215 89.0564 2.91241Z" fill="black"/>
</svg>''';

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
                // Keep the logo's space in the scroll flow. The artwork itself
                // is painted in a foreground layer below, above the pin mask.
                const SizedBox(height: 13),
                const SizedBox(height: 16),
                const Text('находи и забирай   //   без посредников',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xff6c6c6c))),
                const SizedBox(height: 2),
                const Text('11 тыс. магазинов садовода в одном месте',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
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
                SizedBox(height: 22, child: ScrollConfiguration(
                  // Flutter Web excludes mouse dragging by default. Add it
                  // only to the tags, preserving the vertical page scroll.
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: ListView(
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
                ),
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
        // Original Figma wordmark (98 x 13, x centered, y = 58 at rest).
        // Foreground painting prevents the white pinned-header mask from
        // hiding the logo while the opening header is still visible.
        if (offset < 71)
          Positioned(
            top: 58 - offset, left: 30, right: 30, height: 13,
            child: IgnorePointer(
              child: Center(
                child: SvgPicture.string(
                  _homeWordmarkVector,
                  width: 98,
                  height: 13,
                  fit: BoxFit.contain,
                  semanticsLabel: 'садоход',
                ),
              ),
            ),
          ),
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
