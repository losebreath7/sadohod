import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/market_addresses.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/product_photo.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog.dart';
import '../../data/api.dart';
import '../theme/app_theme.dart';
import 'design.dart';

const double pagePadding = 30;

class SadoHeader extends StatelessWidget {
  const SadoHeader({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(pagePadding, 20, pagePadding, 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => context.go('/home'),
          child: const Text(
            'садоход.',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.25,
              color: Palette.ink,
            ),
          ),
        ),
        const Text(
          'ДЕМО  /  0.2',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.7,
            color: Palette.muted,
          ),
        ),
      ],
    ),
  );
}

class SectionOverline extends StatelessWidget {
  const SectionOverline(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.8,
      color: Palette.muted,
    ),
  );
}

class DarkAction extends StatelessWidget {
  const DarkAction({
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 58,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ink,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 19),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Icon(icon, size: 21),
        ],
      ),
    ),
  );
}

class ProductTile extends StatelessWidget {
  const ProductTile({required this.product, this.imageFit = BoxFit.cover, super.key});
  final DemoProduct product;
  final BoxFit imageFit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Stack(children: [
        GestureDetector(
          onTap: () => context.push('/product/${product.id}'),
          child: PhotoGallery(product.photos, small: true, fit: imageFit),
        ),
        Positioned(top: 6, right: 6,
          child: SizedBox(width: 28, height: 28,
            child: FavoriteButton(product.id, small: true, alignRight: true))),
      ]),
      const SizedBox(height: 9),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/product/${product.id}'),
              child: Text(
                product.seller != null &&
                    marketTerritories.contains(product.seller!.zone.toLowerCase())
                    ? '${product.seller!.zone} · ${product.pavilion}'
                    : product.pavilion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BuyerProductType.catalogAddress,
              ),
            ),
          ),
          if (product.price != null) ...[
            const SizedBox(width: 6),
            Text(
              formatRubles(product.price!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BuyerProductType.catalogPrice,
            ),
          ],
        ],
      ),
      const SizedBox(height: 5),
      GestureDetector(
        onTap: () => context.push('/product/${product.id}'),
        child: Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: BuyerProductType.catalogTitle,
        ),
      ),
    ],
  );
}

class ProductGrid extends StatelessWidget {
  const ProductGrid({required this.products, this.imageFit = BoxFit.cover, super.key});
  final List<DemoProduct> products;
  final BoxFit imageFit;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 780
            ? 4
            : constraints.maxWidth >= 520
            ? 3
            : 2;
        final tileWidth = (constraints.maxWidth - (count - 1) * 16) / count;
        final tileHeight = tileWidth + 66;
        return GridView.builder(
          // This is a nested grid in our screen scroll views, not an
          // independent safe-area scroll view. Flutter's implicit top padding
          // would otherwise reintroduce the iPhone's 62 px notch inset here.
          padding: EdgeInsets.zero,
          itemCount: products.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: 20,
            crossAxisSpacing: 16,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemBuilder: (context, index) =>
              ProductTile(product: products[index], imageFit: imageFit),
        );
      },
    );
  }
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({
    this.message =
        'Демонстрационный каталог: товары, цены и павильоны вымышлены.',
    super.key,
  });
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0EC),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: Palette.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: Palette.muted,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class PageChrome extends StatelessWidget {
  const PageChrome({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      titleSpacing: 0,
    ),
    body: SafeArea(top: false, child: child),
  );
}

class LoadingCatalog extends StatelessWidget {
  const LoadingCatalog({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 55),
    child: Center(
      child: CircularProgressIndicator(color: Palette.ink, strokeWidth: 2),
    ),
  );
}

class ApiFailure extends StatelessWidget {
  const ApiFailure({required this.error, required this.retry, super.key});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 25),
    child: Column(
      children: [
        const Icon(Icons.wifi_off_outlined, size: 30, color: Palette.muted),
        const SizedBox(height: 14),
        Text(
          error is ApiException
              ? (error as ApiException).message
              : 'Не удалось загрузить данные',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Palette.muted,
          ),
        ),
        const SizedBox(height: 14),
        TextButton(onPressed: retry, child: const Text('Попробовать снова')),
      ],
    ),
  );
}

class ProductImageView extends StatelessWidget {
  const ProductImageView({
    required this.product,
    this.fit = BoxFit.cover,
    super.key,
  });
  final DemoProduct product;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => SadohodProductPhoto(
    path: product.image,
    fit: fit,
    placeholder: Palette.tile,
  );
}
