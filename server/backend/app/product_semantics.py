"""Search labels and safe query aliases, separate from primary categories.

Only true product types become category labels. Species and colloquial search
terms are facets, not fabricated taxonomy nodes. Never infer printed motifs
as the product's subject from its title.
"""
import re

from sqlalchemy import select

from .catalog_taxonomy import BY_ID, path_ids, ACCESSORY_CONTEXT
from .merchant_models import ProductSearchTag

# Canonical values, not automatically generated user-visible categories.
LEAF_FACETS = {
    'toys-plush': ('мягкая игрушка', 'игрушка', 'плюшевая игрушка'),
    'toys-dolls': ('кукла', 'игрушка'),
    'toys-cars': ('игрушечная машинка', 'игрушка'),
    'toys-construction': ('конструктор', 'игрушка'),
    'jewelry-rings': ('кольцо', 'украшение'),
    'jewelry-earrings': ('серьги', 'украшение'),
    'jewelry-necklaces': ('ожерелье', 'украшение'),
    'jewelry-bracelets': ('браслет', 'украшение'),
    'clothing-skirts': ('юбка', 'одежда'),
    'clothing-trousers': ('брюки', 'одежда'),
    'clothing-tshirts': ('футболка', 'одежда'),
    'clothing-jeans': ('джинсы', 'одежда'),
    'clothing-hoodies': ('худи', 'одежда'),
    'clothing-jackets': ('куртка', 'верхняя одежда'),
    'clothing-dresses': ('платье', 'одежда'),
    'clothing-coats': ('пальто', 'верхняя одежда'),
    'bags-handbags': ('сумка', 'аксессуар'),
    'bags-backpacks': ('рюкзак', 'аксессуар'),
    'bags-hats': ('головной убор', 'шапка'),
    'shoes-sneakers': ('кроссовки', 'обувь'),
    'shoes-boots': ('ботинки', 'обувь'),
    'shoes-sandals': ('сандалии', 'обувь'),
    'home-decor': ('декор', 'товары для дома'),
    'home-textile': ('текстиль', 'товары для дома'),
    'electronics-lighting': ('светильник', 'лампа', 'освещение'),
    'electronics-headphones': ('наушники', 'электроника'),
    'beauty-lipstick': ('помада', 'косметика'),
    'beauty-shampoo': ('шампунь', 'косметика'),
}

QUERY_ALIASES = {
    # Russian colloquial names, word forms and a common misspelling.
    'обезяна': 'обезьяна', 'обезяны': 'обезьяна', 'обезьяны': 'обезьяна',
    'обезьянка': 'обезьяна', 'обезьянки': 'обезьяна',
    'мартышка': 'обезьяна', 'мартышки': 'обезьяна',
    'кольца': 'кольцо', 'колечко': 'кольцо', 'колечки': 'кольцо',
    'юбки': 'юбка', 'юбочку': 'юбка',
    'игрушки': 'игрушка', 'плюшевые игрушки': 'плюшевая игрушка',
    'мягкие игрушки': 'мягкая игрушка',
    'кролик': 'заяц', 'зайчик': 'заяц', 'зайка': 'заяц',
    'мишки': 'медведь', 'мишка': 'медведь', 'медвежонок': 'медведь',
    'ковёр': 'ковер', 'ковры': 'ковер', 'коврик': 'ковер',
    'лампы': 'лампа', 'настольная лампа': 'лампа',
    'шапки': 'шапка', 'штаны': 'брюки',
}

# Species/object tags are inferred only for appropriate product groups.
TOY_SPECIES = {
    'обезьяна': re.compile(r'\b(обезьян\w*|обезян\w*|мартышк\w*)\b'),
    'заяц': re.compile(r'\b(зайц\w*|зайч\w*|кролик\w*)\b'),
    'медведь': re.compile(r'\b(медвед\w*|мишк\w*|медвеж\w*)\b'),
    'кот': re.compile(r'\b(кот\w*|кошк\w*)\b'),
    'собака': re.compile(r'\b(собак\w*|щенк\w*|песик\w*)\b'),
}


def normalize(value: str) -> str:
    text = (value or '').casefold().replace('ё', 'е')
    return ' '.join(re.findall(r'[а-яa-z0-9]+', text))[:80]


ALIASES = {normalize(k): normalize(v) for k, v in QUERY_ALIASES.items()}


def query_terms(query: str) -> set[str]:
    value = normalize(query)
    if not value:
        return set()
    return {value, ALIASES.get(value, value)}


def category_facets(leaf: str | None) -> dict[str, str]:
    if leaf not in BY_ID:
        return {}
    result = {}
    for ancestor in path_ids(leaf):
        result[normalize(BY_ID[ancestor][2])] = 'category'
    for word in LEAF_FACETS.get(leaf, ()):
        result[normalize(word)] = 'category'
    return {term: source for term, source in result.items() if term}


def title_facets(title: str, leaf: str | None) -> dict[str, str]:
    value = normalize(title)
    if not value or ACCESSORY_CONTEXT.search(value):
        return {}
    # A monkey printed on a T-shirt is not a monkey toy.
    if leaf != 'toys-plush':
        return {}
    return {tag: 'title' for tag, pattern in TOY_SPECIES.items()
            if pattern.search(value)}


def sync_search_facets(db, product, leaf: str | None,
                       photo_objects=(), preserve_photos=False):
    """Idempotent replacement, never changes merchant/product publication.

    When ML is unavailable, retain previous photo facets while photos still
    exist; an index outage must not remove previously searchable records.
    """
    wanted = category_facets(leaf)
    wanted.update(title_facets(product.title, leaf))
    if leaf == 'toys-plush':
        for item in photo_objects:
            if item in TOY_SPECIES:
                wanted[normalize(item)] = 'photo'
    existing = {row.tag: row for row in db.scalars(
        select(ProductSearchTag).where(ProductSearchTag.product_id == product.id))}
    if preserve_photos and product.images and leaf == 'toys-plush':
        for word, row in existing.items():
            if row.source == 'photo' and word not in wanted:
                wanted[word] = 'photo'
    for tag, row in existing.items():
        if tag not in wanted:
            db.delete(row)
        elif row.source != wanted[tag]:
            row.source = wanted[tag]
    for tag, source in wanted.items():
        if tag not in existing:
            db.add(ProductSearchTag(product_id=product.id, tag=tag, source=source))
