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


def visual_prompt(query: str) -> str:
    q = query.casefold().replace('ё', 'е')
    for pattern, prompt in _TEXT_PROMPTS:
        if pattern.search(q):
            return prompt
    # Canonical searches for known product types have grounded English photo
    # prompts, even if the Russian title or category tag is missing.
    # Do not map generic group words (e.g. "одежда") to a random leaf.
    from .category_inference import VISUAL_LEAF_PROMPTS
    from .product_semantics import LEAF_FACETS, normalize
    candidates = query_terms(q)
    for leaf, prompts in VISUAL_LEAF_PROMPTS.items():
        if leaf not in BY_ID:
            continue
        exact_labels = {normalize(BY_ID[leaf][2])}
        exact_labels.update(normalize(label) for label in LEAF_FACETS.get(leaf, ())[:1])
        if candidates & exact_labels:
            return prompts[0]
    # No invented translation for an unknown object. English query is supported.
    if re.fullmatch(r'[a-z0-9 \-]{2,80}', q):
        return f'a product photo of {q}'
    return ''


def visual_product_ids(session, query: str, limit: int = 30,
                       min_score: float = 0.28) -> list[str]:
    prompt = visual_prompt(query)
    if not prompt:
        return []
    from .ml_clip import embed_text, MODEL_ID
    from .search import ranked_images
    from .models import ProductImage
    vector = embed_text(prompt)
    hits = ranked_images(session, vector, limit=limit * 2, model_id=MODEL_ID)
    image_ids = [image_id for image_id, score in hits if score >= min_score]
    if not image_ids:
        return []
    products = dict(session.execute(
        select(ProductImage.id, ProductImage.product_id).where(
            ProductImage.id.in_(image_ids))).all())
    seen = set()
    out = []
    for image_id, score in hits:
        pid = products.get(image_id)
        if score >= min_score and pid and pid not in seen:
            seen.add(pid)
            out.append(pid)
        if len(out) == limit:
            break
    return out
