"""Buyer-side title, taxonomy and (optional) OpenCLIP image/text retrieval.

Classic mode never claims to recognize a photograph. The ML mode uses indexed
image embeddings and explicit search similarity, without writing guessed names.
"""
import re
from sqlalchemy import or_, select
from .catalog_taxonomy import NODES_V1, BY_ID, descendant_ids, resolve_leaf
from .merchant_models import ProductCategoryAssignment, ProductSearchTag
from .product_semantics import query_terms
from .models import Product

# A minimal and explicit vocabulary for category navigation, not a fake
# image classifier. Object searches (e.g. monkey) require the image model.
_ALIASES = {
    'игрушка': 'toys', 'игрушки': 'toys',
    'мягкая игрушка': 'toys-plush', 'мягкие игрушки': 'toys-plush',
    'плюшевая игрушка': 'toys-plush', 'плюшевые игрушки': 'toys-plush',
    'кукла': 'toys-dolls', 'куклы': 'toys-dolls',
    'одежда': 'clothing', 'обувь': 'shoes',
    'сумка': 'bags-handbags', 'сумки': 'bags-handbags',
    'косметика': 'beauty',
}


def matched_category_ids(query: str) -> list[str]:
    q = ' '.join(query.casefold().replace('ё', 'е').split())
    category = _ALIASES.get(q) or resolve_leaf(q)
    if not category:
        for node_id, _, title in NODES_V1:
            if title.casefold().replace('ё', 'е') == q:
                category = node_id
                break
    return descendant_ids(category) if category in BY_ID else []


def text_filter(query: str):
    q = query.strip()[:80]
    matched = matched_category_ids(q)
    # Search verified tags and spelling aliases as well as the original title.
    # ProductSearchTag is separate from the authoritative taxonomy path.
    clauses = [Product.title.ilike(f'%{q}%'), Product.category.ilike(f'%{q}%')]
    terms = query_terms(q)
    if terms:
        clauses.append(Product.id.in_(
            select(ProductSearchTag.product_id).where(
                ProductSearchTag.tag.in_(terms))))
    if matched:
        clauses.append(Product.id.in_(
            select(ProductCategoryAssignment.product_id).where(
                ProductCategoryAssignment.category_id.in_(matched))))
        # A validated leaf query may differ from the title only by a Russian
        # noun ending: 'юбки' vs 'Юбка миди', 'платья' vs 'Платье'.
        # Never apply stemming to arbitrary free-form phrases or unknown words.
        normalized = q.casefold().replace('ё', 'е')
        leaf = resolve_leaf(normalized)
        if leaf in BY_ID and len(normalized) >= 4 and normalized.endswith(
                ('а', 'я', 'ы', 'и', 'е')):
            stem = normalized[:-1]
            if len(stem) >= 3:
                # SQLite LIKE is case-insensitive only for ASCII. Include
                # Cyrillic casing explicitly so local QA matches PostgreSQL.
                for variant in {stem, stem.capitalize(), stem.upper()}:
                    clauses.append(Product.title.like(f'%{variant}%'))
    return or_(*clauses)


# English prompts because this OpenCLIP checkpoint is English-oriented.
# No silent claim that arbitrary Russian nouns can be understood reliably.
_TEXT_PROMPTS = (
    (re.compile(r'\b(обезьян\w*|обезян\w*|мартышк\w*)\b'), 'a photo of a plush monkey toy'),
    (re.compile(r'\b(мягк\w*|плюшев\w*)\s+игрушк\w*\b'), 'a photo of a plush stuffed animal toy'),
    (re.compile(r'\bигрушк\w*\b'), 'a photo of a toy'),
    (re.compile(r'\bкольц\w*\b|\bколечк\w*\b'), 'a product photo of a finger ring'),
    (re.compile(r'\bюбк\w*\b|\bюбочк\w*\b'), 'a product photo of a skirt'),
    (re.compile(r'\b(ламп\w*|светильник\w*)\b'), 'a product photo of a lamp'),
    (re.compile(r'\b(ковр\w*|ковер\w*)\b'), 'a product photo of a floor rug'),
)


def visual_prompts(query: str) -> tuple[str, ...]:
    """Resolve every supported product type through one shared taxonomy.

    Keep a small set of English OpenCLIP phrasings per class instead of
    depending on a single handcrafted query phrase for a few examples.
    Ambiguous/broad classes must not pretend to be a precise product.
    """
    q = query.casefold().replace('ё', 'е')
    for pattern, prompt in _TEXT_PROMPTS:
        if pattern.search(q):
            # Special phrases still work; enrich them with the shared class
            # prompts when the query resolves unambiguously below.
            explicit = prompt
            break
    else:
        explicit = None
    from .category_inference import VISUAL_LEAF_PROMPTS, ANIMAL_TOY_PROMPTS
    from .product_semantics import LEAF_FACETS, normalize
    candidates = query_terms(q)
    for species, prompts in ANIMAL_TOY_PROMPTS.items():
        if species != '_other' and normalize(species) in candidates:
            return tuple(dict.fromkeys(((explicit,) if explicit else ()) + tuple(prompts)))
    generic = {
        'одежда', 'обувь', 'игрушка', 'украшение', 'аксессуар',
        'косметика', 'электроника', 'товары для дома',
        'верхняя одежда', 'детские товары', 'подарок',
    }
    matched = []
    for leaf, prompts in VISUAL_LEAF_PROMPTS.items():
        if leaf not in BY_ID:
            continue
        labels = {normalize(BY_ID[leaf][2])}
        labels.update(normalize(label) for label in LEAF_FACETS.get(leaf, ()))
        if candidates & (labels - generic):
            matched.append(leaf)
    if len(matched) == 1:
        prompts = tuple(VISUAL_LEAF_PROMPTS[matched[0]])
        return tuple(dict.fromkeys(((explicit,) if explicit else ()) + prompts))
    if explicit:
        return (explicit,)
    if re.fullmatch(r'[a-z0-9 \\-]{2,80}', q):
        return (f'a product photo of {q}',)
    return ()


def visual_prompt(query: str) -> str:
    """Compatibility helper; search uses the full prompt ensemble."""
    prompts = visual_prompts(query)
    return prompts[0] if prompts else ''


def combine_visual_hits(prompt_hits, min_score: float, limit: int):
    """Combine image matches from alternate prompts by best cosine score."""
    scores = {}
    for hits in prompt_hits:
        for image_id, score in hits:
            if score >= min_score:
                scores[image_id] = max(float(score), scores.get(image_id, -1.0))
    return sorted(scores.items(), key=lambda item: (-item[1], item[0]))[:limit]


def visual_product_ids(session, query: str, limit: int = 30,
                       min_score: float = 0.26) -> list[str]:
    prompts = visual_prompts(query)
    if not prompts:
        return []
    from .ml_clip import embed_text, MODEL_ID
    from .search import ranked_images
    from .models import ProductImage

    # Search at most three descriptions of one product class. The text model
    # and the index are identical; no extra classifier or DB migration.
    hits = combine_visual_hits(
        [ranked_images(session, embed_text(prompt), limit=limit * 3,
                       model_id=MODEL_ID) for prompt in prompts[:3]],
        min_score, limit * 3,
    )
    if not hits:
        return []
    image_ids = [image_id for image_id, _score in hits]
    products = dict(session.execute(
        select(ProductImage.id, ProductImage.product_id).where(
            ProductImage.id.in_(image_ids))).all())
    seen = set()
    out = []
    for image_id, score in hits:
        pid = products.get(image_id)
        if pid and pid not in seen:
            seen.add(pid)
            out.append(pid)
        if len(out) == limit:
            break
    return out
