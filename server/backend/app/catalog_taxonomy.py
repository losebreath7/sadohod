"""Stable v1 catalog tree and conservative title-to-leaf classification.

The IDs are persistent DB keys. Never rename/reparent an existing ID without
an explicit data migration. Do not infer age/gender from generic titles.
"""
import re

# (id, parent_id, visible title). Stable order is also the catalog display order.
NODES_V1 = (
    ('clothing', None, 'Одежда'),
    ('clothing-women', 'clothing', 'Женская одежда'),
    ('clothing-men', 'clothing', 'Мужская одежда'),
    ('clothing-kids', 'clothing', 'Детская одежда'),
    ('clothing-outerwear', 'clothing', 'Верхняя одежда'),
    ('clothing-jackets', 'clothing-outerwear', 'Куртки'),
    ('clothing-coats', 'clothing-outerwear', 'Пальто'),
    ('clothing-dresses', 'clothing-women', 'Платья'),
    ('clothing-tshirts', 'clothing', 'Футболки'),
    ('clothing-hoodies', 'clothing', 'Худи'),
    ('clothing-jeans', 'clothing', 'Джинсы'),
    ('clothing-trousers', 'clothing', 'Брюки'),
    ('clothing-shirts', 'clothing', 'Рубашки'),
    ('clothing-skirts', 'clothing-women', 'Юбки'),
    ('clothing-underwear', 'clothing', 'Нижнее бельё'),
    ('clothing-kids-jackets', 'clothing-kids', 'Куртки'),
    ('shoes', None, 'Обувь'),
    ('shoes-women', 'shoes', 'Женская обувь'),
    ('shoes-men', 'shoes', 'Мужская обувь'),
    ('shoes-kids', 'shoes', 'Детская обувь'),
    ('shoes-sneakers', 'shoes', 'Кроссовки'),
    ('shoes-women-sneakers', 'shoes-women', 'Кроссовки'),
    ('shoes-men-sneakers', 'shoes-men', 'Кроссовки'),
    ('shoes-kids-sneakers', 'shoes-kids', 'Кроссовки'),
    ('shoes-boots', 'shoes', 'Ботинки и сапоги'),
    ('shoes-sandals', 'shoes', 'Сандалии'),
    ('bags', None, 'Сумки и аксессуары'),
    ('bags-handbags', 'bags', 'Сумки'),
    ('bags-backpacks', 'bags', 'Рюкзаки'),
    ('bags-wallets', 'bags', 'Кошельки'),
    ('bags-belts', 'bags', 'Ремни'),
    ('bags-hats', 'bags', 'Головные уборы'),
    ('toys', None, 'Игрушки'),
    ('toys-kids', 'toys', 'Детские игрушки'),
    ('toys-dolls', 'toys-kids', 'Куклы'),
    ('toys-plush', 'toys-kids', 'Мягкие игрушки'),
    ('toys-cars', 'toys-kids', 'Машинки'),
    ('toys-construction', 'toys-kids', 'Конструкторы'),
    ('toys-board', 'toys', 'Настольные игры'),
    ('beauty', None, 'Красота и уход'),
    ('beauty-skincare', 'beauty', 'Уходовая косметика'),
    ('beauty-face-cream', 'beauty-skincare', 'Кремы для лица'),
    ('beauty-makeup', 'beauty', 'Декоративная косметика'),
    ('beauty-lipstick', 'beauty-makeup', 'Помады'),
    ('beauty-mascara', 'beauty-makeup', 'Тушь для ресниц'),
    ('beauty-hair', 'beauty', 'Уход за волосами'),
    ('beauty-shampoo', 'beauty-hair', 'Шампуни'),
    ('beauty-fragrance', 'beauty', 'Парфюмерия'),
    ('home', None, 'Товары для дома'),
    ('home-kitchen', 'home', 'Кухня и посуда'),
    ('home-pots', 'home-kitchen', 'Кастрюли'),
    ('home-pans', 'home-kitchen', 'Сковороды'),
    ('home-cups', 'home-kitchen', 'Кружки и чашки'),
    ('home-textile', 'home', 'Домашний текстиль'),
    ('home-bedding', 'home-textile', 'Постельное бельё'),
    ('home-towels', 'home-textile', 'Полотенца'),
    ('home-decor', 'home', 'Декор'),
    ('home-storage', 'home', 'Хранение и организация'),
    ('electronics', None, 'Электроника'),
    ('electronics-phone', 'electronics', 'Аксессуары для телефонов'),
    ('electronics-headphones', 'electronics', 'Наушники'),
    ('electronics-chargers', 'electronics', 'Зарядные устройства'),
    ('electronics-lighting', 'electronics', 'Освещение'),
    ('jewelry', None, 'Украшения'),
    ('jewelry-earrings', 'jewelry', 'Серьги'),
    ('jewelry-rings', 'jewelry', 'Кольца'),
    ('jewelry-bracelets', 'jewelry', 'Браслеты'),
    ('jewelry-necklaces', 'jewelry', 'Цепочки и ожерелья'),
    ('kids', None, 'Детские товары'),
    ('kids-strollers', 'kids', 'Коляски'),
    ('kids-feeding', 'kids', 'Кормление'),
    ('kids-diapers', 'kids', 'Подгузники'),
    ('sport', None, 'Спорт и отдых'),
    ('sport-fitness', 'sport', 'Фитнес'),
    ('sport-balls', 'sport', 'Мячи'),
    ('sport-camping', 'sport', 'Туризм'),
    ('pets', None, 'Зоотовары'),
    ('pets-collars', 'pets', 'Ошейники'),
    ('pets-beds', 'pets', 'Лежанки'),
    ('pets-toys', 'pets', 'Игрушки для животных'),
    ('office', None, 'Канцтовары'),
    ('office-notebooks', 'office', 'Тетради и блокноты'),
    ('office-pens', 'office', 'Ручки и карандаши'),
    ('tools', None, 'Инструменты и ремонт'),
    ('tools-hand', 'tools', 'Ручные инструменты'),
    ('tools-electric', 'tools', 'Электроинструменты'),
    ('seasonal', None, 'Сезонные товары'),
    ('seasonal-christmas', 'seasonal', 'Новогодние украшения'),
    ('seasonal-gifts', 'seasonal', 'Подарочные товары'),
)
BY_ID = {item[0]: item for item in NODES_V1}
LEGACY = {
    'Верхняя одежда': 'clothing-outerwear',
    'Платья': 'clothing-dresses',
    'Одежда': 'clothing',
    'Обувь': 'shoes',
    'Сумки': 'bags-handbags',
}

# Every pattern matches a named physical product, not a property or a decoration.
RULES = (
    ('toys-dolls', r'\bкукл\w*\b|\bбарби\b'),
    ('toys-plush', r'\bмягк\w*\s+игрушк\w*\b|\bплюшев\w*\s+игрушк\w*\b'),
    ('toys-construction', r'\bконструктор\w*\b|\bлего\b'),
    ('toys-cars', r'\bмашинк\w*\b'),
    ('beauty-face-cream', r'\bкрем\w*\s+для\s+лиц\w*\b|\bкрем\w*\s+лицев\w*\b'),
    ('beauty-shampoo', r'\bшампун\w*\b'),
    ('beauty-lipstick', r'\bпомад\w*\b'),
    ('beauty-mascara', r'\bтушь\s+для\s+ресниц\w*\b'),
    ('home-pots', r'\bкастрюл\w*\b'),
    ('home-pans', r'\bсковород\w*\b'),
    ('home-towels', r'\bполотенц\w*\b'),
    ('home-bedding', r'\bпостельн\w*\s+бель\w*\b'),
    ('shoes-sneakers', r'\bкроссовк\w*\b|\bкед\w*\b'),
    ('shoes-boots', r'\bботинк\w*\b|\bсапог\w*\b'),
    ('shoes-sandals', r'\bсандали\w*\b|\bбосоножк\w*\b'),
    ('clothing-jackets', r'\bкуртк\w*\b|\bпуховик\w*\b'),
    ('clothing-coats', r'\bпальто\b'),
    ('clothing-dresses', r'\bплать\w*\b|\bсарафан\w*\b'),
    ('clothing-tshirts', r'\bфутболк\w*\b'),
    ('clothing-hoodies', r'\bхуди\b|\bтолстовк\w*\b'),
    ('clothing-jeans', r'\bджинс\w*\b'),
    ('clothing-trousers', r'\bбрюк\w*\b|\bштан\w*\b'),
    ('clothing-shirts', r'\bрубашк\w*\b'),
    ('clothing-skirts', r'\bюбк\w*\b'),
    ('bags-handbags', r'\bсумк\w*\b'),
    ('bags-backpacks', r'\bрюкзак\w*\b'),
    ('bags-wallets', r'\bкошел[её]к\w*\b'),
    ('electronics-headphones', r'\bнаушник\w*\b'),
    ('electronics-chargers', r'\bзарядн\w*\s+устройств\w*\b'),
    ('jewelry-earrings', r'\bсерьг\w*\b|\bсер[её]жк\w*\b'),
    ('jewelry-rings', r'\bкольц\w*\b'),
    ('kids-strollers', r'\bколяск\w*\b'),
    ('kids-diapers', r'\bподгузник\w*\b'),
    ('sport-balls', r'\bмяч\w*\b'),
    ('office-notebooks', r'\bтетрад\w*\b|\bблокнот\w*\b'),
    ('office-pens', r'\bкарандаш\w*\b|\bручк\w*\b'),
)
ACCESSORY_CONTEXT = re.compile(r'\b(чехол|чехлы|брелок|принт|рисунок|наклейка|выкройка|для\s+куклы|для\s+кроссовок)\b')
FEMALE = re.compile(r'\b(женск\w*|для\s+женщин)\b')
MALE = re.compile(r'\b(мужск\w*|для\s+мужчин)\b')
CHILD = re.compile(r'\b(детск\w*|для\s+детей)\b')


def path_ids(category_id):
    if category_id not in BY_ID:
        return []
    ids = []
    while category_id:
        ids.append(category_id)
        category_id = BY_ID[category_id][1]
    return list(reversed(ids))


def descendant_ids(category_id):
    if category_id not in BY_ID:
        return []
    return [node_id for node_id in BY_ID if category_id in path_ids(node_id)]


def category_path(category_id):
    return [{'id': node_id, 'name': BY_ID[node_id][2]} for node_id in path_ids(category_id)]


def resolve_leaf(title):
    value = ' '.join((title or '').casefold().replace('ё', 'е').split())
    if not value or ACCESSORY_CONTEXT.search(value):
        return None
    matched = [category_id for category_id, expression in RULES if re.search(expression, value)]
    # A title naming two different products is ambiguous, not a multi-category offer.
    if len(set(matched)) != 1:
        return None
    leaf = matched[0]
    if leaf == 'shoes-sneakers':
        if CHILD.search(value): return 'shoes-kids-sneakers'
        if FEMALE.search(value) and not MALE.search(value): return 'shoes-women-sneakers'
        if MALE.search(value) and not FEMALE.search(value): return 'shoes-men-sneakers'
    if leaf == 'clothing-jackets' and CHILD.search(value):
        return 'clothing-kids-jackets'
    return leaf
