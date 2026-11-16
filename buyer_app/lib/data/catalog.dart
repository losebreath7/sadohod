/// All data is fictional. No seller, stock, price or pavilion in this file is
/// verified to exist at the actual Sadovod market.
class Seller {
  const Seller({
    required this.id,
    required this.name,
    required this.pavilion,
    required this.zone,
    this.contact = '',
  });
  final String id;
  final String name;
  final String pavilion;
  final String zone;
  final String contact;
  factory Seller.fromJson(Map<String, dynamic> json) => Seller(
    id: json['id'] as String,
    name: json['name'] as String,
    pavilion: json['pavilion'] as String,
    zone: json['zone'] as String,
    contact: json['contact']?.toString() ?? '',
  );
}

/// A product may have multiple sellers and multiple pavilion offers.
/// This is not a SKU: the pavilion code is a real-world location field.
class ProductOffer {
  const ProductOffer({required this.seller, required this.pavilion, this.price, this.saleModes = const []});
  final Seller seller;
  final String pavilion;
  final int? price;
  final List<String> saleModes;
  factory ProductOffer.fromJson(Map<String, dynamic> json) {
    final seller = Seller.fromJson(json['seller'] as Map<String, dynamic>);
    final pavilion = json['pavilion'];
    return ProductOffer(
      seller: seller,
      pavilion: pavilion is Map ? (pavilion['code']?.toString() ?? seller.pavilion) : seller.pavilion,
      price: (json['price'] as num?)?.toInt(),
      saleModes: (json['sale_modes'] as List? ?? const []).map((v) => v.toString()).toList(),
    );
  }
}

class DemoProduct {
  const DemoProduct({
    required this.id,
    required this.title,
    required this.category,
    required this.price,
    required this.sellerId,
    required this.image,
    required this.description,
    required this.colors,
    this.seller,
    this.images = const [],
    this.saleModes = const [],
    this.offers = const [],
    this.preferredPavilion,
  });
  final String id;
  final String title;
  final String category;
  final int? price;
  final String sellerId;
  final String image;
  final String description;
  final List<String> colors;
  final Seller? seller;
  final List<String> images;
  final List<String> saleModes;
  final List<ProductOffer> offers;
  final String? preferredPavilion;
  String get pavilion =>
      preferredPavilion ?? (offers.isNotEmpty ? offers.first.pavilion : null) ?? seller?.pavilion ??
      DemoCatalog.findSeller(sellerId)?.pavilion ??
      'Павильон не указан';
  List<String> get photos => images.isEmpty ? [image] : images;
  List<ProductOffer> get availableOffers => offers.isEmpty && seller != null
      ? [ProductOffer(seller: seller!, pavilion: seller!.pavilion, price: price, saleModes: saleModes)]
      : offers;

  DemoProduct forSeller(String id) {
    ProductOffer? selected;
    for (final offer in availableOffers) {
      if (offer.seller.id == id) { selected = offer; break; }
    }
    if (selected == null) return this;
    return forOffer(selected);
  }

  /// One physical offer is attached to one seller and one pavilion address.
  /// Keeps the full offer list so the product detail can switch locations.
  DemoProduct forOffer(ProductOffer offer) => DemoProduct(
    id: id, title: title, category: category,
    price: offer.price, sellerId: offer.seller.id,
    image: image, description: description, colors: colors,
    seller: offer.seller, images: images,
    saleModes: offer.saleModes, offers: offers, preferredPavilion: offer.pavilion,
  );

  factory DemoProduct.fromJson(Map<String, dynamic> json, String baseUrl) {
    final rawImage = (json['image'] ?? '') as String;
    final offers = json['offers'] as List? ?? [];
    final typedOffers = offers
        .whereType<Map<String, dynamic>>()
        .map(ProductOffer.fromJson)
        .toList();
    final sellerJson = typedOffers.isNotEmpty ? offers.first['seller'] : null;
    return DemoProduct(
      seller: sellerJson is Map<String, dynamic>
          ? Seller.fromJson(sellerJson)
          : null,
      images: (json['images'] as List? ?? [])
          .whereType<String>()
          .map((s) => s.startsWith('/') ? '$baseUrl$s' : s)
          .toList(),
      offers: typedOffers,
      saleModes: (offers.isNotEmpty && offers.first is Map && offers.first['sale_modes'] is List
              ? offers.first['sale_modes'] as List
              : (json['sale_modes'] as List? ?? const []))
          .map((e) => e.toString()).toList(),
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      price: (json['price'] as num?)?.toInt(),
      sellerId: typedOffers.isNotEmpty ? typedOffers.first.seller.id : (json['seller_id']?.toString() ?? ''),
      image: rawImage.startsWith('/') ? '$baseUrl$rawImage' : rawImage,
      description: (json['description'] ?? '') as String,
      colors: (json['colors'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class DemoCatalog {
  static const categories = [
    'Все',
    'Верхняя одежда',
    'Одежда',
    'Обувь',
    'Сумки',
    'Платья',
  ];

  static const sellers = <Seller>[
    Seller(
      id: 's01',
      name: 'Контур 01',
      pavilion: 'А-14',
      zone: 'Сектор А · линия 2',
    ),
    Seller(
      id: 's02',
      name: 'Студия 08',
      pavilion: 'Б-08',
      zone: 'Сектор Б · линия 1',
    ),
    Seller(
      id: 's03',
      name: 'Форма 17',
      pavilion: 'В-17',
      zone: 'Сектор В · линия 4',
    ),
    Seller(
      id: 's04',
      name: 'Линия 05',
      pavilion: 'Г-05',
      zone: 'Сектор Г · линия 3',
    ),
  ];

  static const products = <DemoProduct>[
    DemoProduct(
      id: 'p01',
      title: 'Укороченная куртка',
      category: 'Верхняя одежда',
      price: 3890,
      sellerId: 's01',
      image: 'assets/products/p01.jpg',
      description: 'Прямой силуэт, высокий воротник и молния по центру.',
      colors: ['Графит'],
    ),
    DemoProduct(
      id: 'p02',
      title: 'Сумка с короткими ручками',
      category: 'Сумки',
      price: 2450,
      sellerId: 's02',
      image: 'assets/products/p02.jpg',
      description:
          'Компактная сумка с основным отделением и внутренним карманом.',
      colors: ['Шоколад'],
    ),
    DemoProduct(
      id: 'p03',
      saleModes: ['wholesale', 'retail'],
      title: 'Футболка свободного кроя',
      category: 'Одежда',
      price: 990,
      sellerId: 's03',
      image: 'assets/products/p03.jpg',
      description: 'Свободная посадка и плотный круглый ворот.',
      colors: ['Молочный'],
    ),
    DemoProduct(
      id: 'p04',
      title: 'Кроссовки на платформе',
      category: 'Обувь',
      price: 2990,
      sellerId: 's04',
      image: 'assets/products/p04.jpg',
      description: 'Объёмная подошва, шнуровка, мягкая посадка.',
      colors: ['Песочный'],
    ),
    DemoProduct(
      id: 'p05',
      title: 'Худи с карманом',
      category: 'Одежда',
      price: 2690,
      sellerId: 's02',
      image: 'assets/products/p05.jpg',
      description: 'Мягкая модель свободного кроя с капюшоном.',
      colors: ['Серый'],
    ),
    DemoProduct(
      id: 'p06',
      title: 'Прямые брюки',
      category: 'Одежда',
      price: 1990,
      sellerId: 's01',
      image: 'assets/products/p06.jpg',
      description: 'Умеренно широкая посадка, прямые штанины.',
      colors: ['Тёмно-синий'],
    ),
    DemoProduct(
      id: 'p07',
      title: 'Платье миди',
      category: 'Платья',
      price: 3190,
      sellerId: 's03',
      image: 'assets/products/p07.jpg',
      description: 'Мягко приталенная форма и свободный низ.',
      colors: ['Терракотовый'],
    ),
    DemoProduct(
      id: 'p08',
      title: 'Куртка с воротником',
      category: 'Верхняя одежда',
      price: 4290,
      sellerId: 's04',
      image: 'assets/products/p08.jpg',
      description: 'Минималистичная верхняя одежда на каждый день.',
      colors: ['Оливковый'],
    ),
    DemoProduct(
      id: 'p09',
      title: 'Мини-сумка',
      category: 'Сумки',
      price: 1890,
      sellerId: 's02',
      image: 'assets/products/p09.jpg',
      description: 'Небольшой размер, жёсткая форма и короткие ручки.',
      colors: ['Чёрный'],
    ),
    DemoProduct(
      id: 'p10',
      title: 'Кеды низкие',
      category: 'Обувь',
      price: 2190,
      sellerId: 's03',
      image: 'assets/products/p10.jpg',
      description: 'Универсальная модель с контрастной подошвой.',
      colors: ['Графит'],
    ),
    DemoProduct(
      id: 'p11',
      title: 'Футболка базовая',
      category: 'Одежда',
      price: 1190,
      sellerId: 's01',
      image: 'assets/products/p11.jpg',
      description: 'Прямой крой, базовая посадка.',
      colors: ['Хаки'],
    ),
    DemoProduct(
      id: 'p12',
      title: 'Брюки широкие',
      category: 'Одежда',
      price: 2590,
      sellerId: 's04',
      image: 'assets/products/p12.jpg',
      description: 'Свободный прямой силуэт.',
      colors: ['Кофейный'],
    ),
  ];

  static DemoProduct? findProduct(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  static Seller? findSeller(String id) {
    for (final seller in sellers) {
      if (seller.id == id) return seller;
    }
    return null;
  }

  static List<DemoProduct> filtered({
    String category = 'Все',
    String query = '',
  }) {
    final needle = query.toLowerCase().trim();
    return products.where((p) {
      final categoryOk = category == 'Все' || p.category == category;
      final textOk =
          needle.isEmpty ||
          p.title.toLowerCase().contains(needle) ||
          p.category.toLowerCase().contains(needle);
      return categoryOk && textOk;
    }).toList();
  }
}

String formatRubles(int amount) {
  final str = amount.toString();
  final chunks = <String>[];
  for (var i = str.length; i > 0; i -= 3) {
    final start = i >= 3 ? i - 3 : 0;
    chunks.insert(0, str.substring(start, i));
  }
  return '${chunks.join(' ')} ₽';
}
