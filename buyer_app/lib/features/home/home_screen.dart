import 'dart:ui' show PointerDeviceKind;

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
  static const double _min = buyerCompactHeaderHeight;

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
    final searchTop = (275 - offset).clamp(buyerCompactContentTop, 275.0).toDouble();
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
        // Original 98 x 13 Figma wordmark at y=58. The intro text keeps its
        // Figma y-position, so the 16 px spacing below the logo is restored.
        // Foreground painting prevents the pinned-header mask from hiding it.
        if (offset < 71)
          Positioned(
            top: 58 - offset, left: 30, right: 30, height: 13,
            child: IgnorePointer(
              child: Center(
                child: const SadohodWordmark(),
              ),
            ),
          ),
        // Compact emblem sits below the island; tapping scrolls the current home to top.
        Positioned(top: buyerCompactContentTop, left: 30, width: 25, height: 25,
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

/// The approved Figma logo, drawn natively from its vector coordinates.
/// This bypasses the malformed SVG command in the original asset.
class SadohodWordmark extends StatelessWidget {
  const SadohodWordmark({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 98,
    height: 13,
    child: CustomPaint(painter: _SadohodWordmarkPainter()),
  );
}

class _SadohodWordmarkPainter extends CustomPainter {
  const _SadohodWordmarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 98, size.height / 13);
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final p0 = Path();
    p0.moveTo(57.1149, 12.8329);
    p0.lineTo(61.5422, 6.44279);
    p0.lineTo(57.1814, 0.126709);
    p0.lineTo(61.2277, 0.131701);
    p0.lineTo(63.5599, 3.54144);
    p0.lineTo(65.9263, 0.131701);
    p0.lineTo(69.9592, 0.131701);
    p0.lineTo(65.5851, 6.44279);
    p0.lineTo(69.995, 12.8329);
    p0.lineTo(66.0003, 12.8645);
    p0.lineTo(63.5608, 9.34581);
    p0.lineTo(61.1511, 12.8329);
    p0.lineTo(57.1157, 12.8329);
    p0.lineTo(57.1149, 12.8329);
    p0.close();
    canvas.drawPath(p0, paint);
    final p1 = Path();
    p1.moveTo(76.0473, 0.009277);
    p1.cubicTo(72.4678, 0.009277, 69.5565, 2.92145, 69.5565, 6.50009);
    p1.cubicTo(69.5565, 10.0787, 72.4678, 12.9909, 76.0473, 12.9909);
    p1.cubicTo(79.6267, 12.9909, 82.5381, 10.0787, 82.5381, 6.50009);
    p1.cubicTo(82.5381, 2.92145, 79.6267, 0.009277, 76.0473, 0.009277);
    p1.close();
    p1.moveTo(79.3538, 6.50009);
    p1.cubicTo(79.3538, 8.32311, 77.8711, 9.80666, 76.0473, 9.80666);
    p1.cubicTo(74.2234, 9.80666, 72.7407, 8.32311, 72.7407, 6.50009);
    p1.cubicTo(72.7407, 4.67707, 74.2234, 3.19353, 76.0473, 3.19353);
    p1.cubicTo(77.8711, 3.19353, 79.3538, 4.67707, 79.3538, 6.50009);
    p1.close();
    canvas.drawPath(p1, paint);
    final p2 = Path();
    p2.moveTo(9.61901, 7.49677);
    p2.cubicTo(9.45676, 7.99932, 9.18468, 8.44281, 8.81109, 8.81639);
    p2.quadraticBezierTo(8.18622, 9.44043, 7.35667, 9.78573);
    p2.lineTo(6.47054, 9.78573);
    p2.cubicTo(5.59023, 9.78656, 4.76234, 9.44376, 4.1408, 8.82222);
    p2.cubicTo(3.5176, 8.19901, 3.17562, 7.37112, 3.17646, 6.48832);
    p2.cubicTo(3.17812, 5.60635, 3.52259, 4.77596, 4.14746, 4.15193);
    p2.cubicTo(4.77149, 3.52706, 5.60188, 3.18259, 6.48385, 3.18092);
    p2.lineTo(6.48801, 3.18092);
    p2.cubicTo(7.36832, 3.18092, 8.19538, 3.52373, 8.81692, 4.14527);
    p2.cubicTo(9.18967, 4.51803, 9.46009, 4.96151, 9.62151, 5.4624);
    p2.lineTo(9.64896, 5.54727);
    p2.lineTo(12.8956, 5.54311);
    p2.lineTo(12.8723, 5.40083);
    p2.cubicTo(12.6502, 4.06373, 12.027, 2.85143, 11.0693, 1.89374);
    p2.cubicTo(9.84783, 0.672297, 8.22367, 0, 6.4955, 0);
    p2.lineTo(6.48718, 0);
    p2.cubicTo(4.75569, 0.002496, 3.12653, 0.678121, 1.90093, 1.90456);
    p2.cubicTo(-0.629336, 4.43482, -0.634329, 8.54847, 1.89011, 11.0729);
    p2.cubicTo(3.15066, 12.3335, 4.80644, 12.9633, 6.46388, 12.9633);
    p2.cubicTo(8.12132, 12.9633, 9.79125, 12.3293, 11.0585, 11.0621);
    p2.cubicTo(12.0178, 10.1027, 12.6443, 8.88795, 12.8698, 7.55001);
    p2.lineTo(12.894, 7.4069);
    p2.lineTo(9.6473, 7.41106);
    p2.lineTo(9.61985, 7.49593);
    p2.lineTo(9.61901, 7.49677);
    p2.close();
    canvas.drawPath(p2, paint);
    final p3 = Path();
    p3.moveTo(50.9469, 0.025146);
    p3.cubicTo(47.3683, 0.025146, 44.4561, 2.92983, 44.4561, 6.50015);
    p3.cubicTo(44.4561, 10.0705, 47.3683, 12.9752, 50.9469, 12.9752);
    p3.cubicTo(54.5256, 12.9752, 57.4377, 10.0705, 57.4377, 6.50015);
    p3.cubicTo(57.4377, 2.92983, 54.5264, 0.025146, 50.9469, 0.025146);
    p3.close();
    p3.moveTo(54.2535, 6.50015);
    p3.cubicTo(54.2535, 8.31901, 52.7708, 9.7984, 50.9469, 9.7984);
    p3.cubicTo(49.1231, 9.7984, 47.6404, 8.31901, 47.6404, 6.50015);
    p3.cubicTo(47.6404, 4.68129, 49.1239, 3.20191, 50.9469, 3.20191);
    p3.cubicTo(52.77, 3.20191, 54.2535, 4.68129, 54.2535, 6.50015);
    p3.close();
    canvas.drawPath(p3, paint);
    final p4 = Path();
    p4.moveTo(27.3441, 0.131752);
    p4.lineTo(24.2772, 0.131752);
    p4.lineTo(24.2772, 1.25751);
    p4.cubicTo(23.2089, 0.48537, 21.9, 0.024414, 20.4831, 0.024414);
    p4.cubicTo(16.9044, 0.024414, 13.9922, 2.9291, 13.9922, 6.49942);
    p4.cubicTo(13.9922, 10.0697, 16.9044, 12.9744, 20.4831, 12.9744);
    p4.cubicTo(21.9, 12.9744, 23.2089, 12.5135, 24.2772, 11.7413);
    p4.lineTo(24.2772, 12.8471);
    p4.lineTo(27.5871, 12.8471);
    p4.lineTo(27.5871, 0.130086);
    p4.lineTo(27.3441, 0.130086);
    p4.lineTo(27.3441, 0.131752);
    p4.close();
    p4.moveTo(20.4822, 9.7985);
    p4.cubicTo(18.6592, 9.7985, 17.1757, 8.31911, 17.1757, 6.50025);
    p4.cubicTo(17.1757, 4.68139, 18.6592, 3.20201, 20.4822, 3.20201);
    p4.cubicTo(22.3053, 3.20201, 23.7888, 4.68139, 23.7888, 6.50025);
    p4.cubicTo(23.7888, 8.31911, 22.3053, 9.7985, 20.4822, 9.7985);
    p4.close();
    canvas.drawPath(p4, paint);
    final p5 = Path();
    p5.moveTo(44.05, 9.53802);
    p5.lineTo(42.6596, 9.53802);
    p5.lineTo(42.6596, 0.149171);
    p5.cubicTo(39.3938, 0.149171, 35.7869, 0.126709, 32.5211, 0.126709);
    p5.cubicTo(31.7914, 3.26353, 31.0617, 6.40119, 30.332, 9.53802);
    p5.lineTo(28.9417, 9.53802);
    p5.lineTo(28.9417, 12.8504);
    p5.lineTo(44.0225, 12.8504);
    p5.lineTo(44.0225, 12.8487);
    p5.lineTo(44.05, 12.8487);
    p5.lineTo(44.05, 9.53885);
    p5.lineTo(44.05, 9.53802);
    p5.close();
    p5.moveTo(35.2802, 2.91241);
    p5.lineTo(39.3464, 2.91241);
    p5.lineTo(39.3356, 9.53885);
    p5.lineTo(33.7367, 9.53885);
    p5.cubicTo(34.251, 7.32976, 34.766, 5.1215, 35.2802, 2.91241);
    p5.close();
    canvas.drawPath(p5, paint);
    final p6 = Path();
    p6.moveTo(97.8262, 9.53802);
    p6.lineTo(96.4358, 9.53802);
    p6.lineTo(96.4358, 0.149171);
    p6.cubicTo(93.17, 0.149171, 89.5631, 0.126709, 86.2973, 0.126709);
    p6.cubicTo(85.5676, 3.26353, 84.8379, 6.40119, 84.1082, 9.53802);
    p6.lineTo(82.7178, 9.53802);
    p6.lineTo(82.7178, 12.8504);
    p6.lineTo(97.7987, 12.8504);
    p6.lineTo(97.7987, 12.8487);
    p6.lineTo(97.8262, 12.8487);
    p6.lineTo(97.8262, 9.53885);
    p6.lineTo(97.8262, 9.53802);
    p6.close();
    p6.moveTo(89.0564, 2.91241);
    p6.lineTo(93.1226, 2.91241);
    p6.lineTo(93.1118, 9.53885);
    p6.lineTo(87.5129, 9.53885);
    p6.cubicTo(88.0271, 7.32976, 88.5422, 5.1215, 89.0564, 2.91241);
    p6.close();
    canvas.drawPath(p6, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SadohodWordmarkPainter oldDelegate) => false;
}
