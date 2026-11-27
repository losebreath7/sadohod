import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../data/api.dart';
import '../../data/catalog.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    this.initialCategory = 'Все',
    this.initialQuery = '',
  });
  final String initialCategory, initialQuery;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final query = TextEditingController(text: widget.initialQuery);
  late Future<List<DemoProduct>> products = CatalogApi.instance.products();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: Column(
      children: [
        DesignHeader(
          child: Row(
            children: [
              const RoundBack(),
              const SizedBox(width: 15),
              Expanded(
                child: SearchCapsule(
                  height: 25,
                  controller: query,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DemoProduct>>(
            future: products,
            builder: (context, s) {
              if (s.hasError) {
                return ApiFailure(
                  error: s.error!,
                  retry: () =>
                      setState(() => products = CatalogApi.instance.products()),
                );
              }
              if (!s.hasData) return const LoadingCatalog();
              final q = query.text.trim().toLowerCase();
              final items = s.data!
                  .where(
                    (p) =>
                        (widget.initialCategory == 'Все' ||
                            p.category == widget.initialCategory) &&
                        '${p.title} ${p.category} ${p.pavilion}'
                            .toLowerCase()
                            .contains(q),
                  )
                  .toList();
              return ListView(
                key: PageStorageKey('catalog-${widget.initialCategory}'),
                padding: const EdgeInsets.fromLTRB(30, 4, 30, 24),
                children: [
                  if (widget.initialCategory != 'Все')
                    TextButton(
                      onPressed: () => context.pushReplacement('/catalog'),
                      child: Text('${widget.initialCategory} ×'),
                    ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('Ничего не нашли. Попробуйте другой запрос.'),
                    ),
                  ProductGrid(products: items.take(4).toList()),
                  if (items.length > 4) ...[
                    const SizedBox(height: 15),
                    Semantics(
                      label: 'Рекламное место, демонстрация',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: AspectRatio(
                          aspectRatio: 330 / 180,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/figma/e221c.png',
                                fit: BoxFit.cover,
                                alignment: const Alignment(0, .5),
                              ),
                              const Positioned(
                                left: 8,
                                bottom: 8,
                                child: ColoredBox(
                                  color: Colors.white70,
                                  child: Text(
                                    ' Рекламное место · демо ',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ProductGrid(products: items.skip(4).toList()),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
