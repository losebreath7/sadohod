"""Title + optional real OpenCLIP photo inference, with explicit abstention.

Cosine thresholds are conservative heuristics, NOT calibrated probabilities.
Photo inference is available only with the existing SEARCH_BACKEND=clip stack.
"""
from functools import lru_cache
import logging
import math

from .config import SEARCH_BACKEND
from .merchant_models import ProductCategoryState, ProductCategoryAssignment, CatalogCategory
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM, _model_bundle, MODEL_ARCH
from .product_categories import resolve_category, is_unassigned, UNASSIGNED
from .catalog_taxonomy import NODES_V1, LEGACY, BY_ID, path_ids, resolve_leaf

log = logging.getLogger(__name__)
PROMPTS = {
    'Верхняя одежда': ('a photo of a winter jacket', 'a photo of a coat', 'a photo of a puffer jacket'),
    'Сумки': ('a photo of a handbag', 'a photo of a backpack', 'a photo of a purse'),
    'Обувь': ('a photo of sneakers', 'a photo of boots', 'a photo of shoes'),
    'Платья': ('a photo of a dress', 'a photo of a sundress'),
    'Одежда': ('a photo of a t-shirt', 'a photo of a hoodie', 'a photo of jeans', 'a photo of a skirt', 'a photo of a sweater', 'a photo of a shirt'),
    'Игрушки': ('a product photo of a doll toy', 'a product photo of a plush toy', 'a product photo of building blocks'),
    'Красота и уход': ('a product photo of facial cream', 'a product photo of lipstick', 'a product photo of shampoo'),
    'Товары для дома': ('a product photo of a saucepan', 'a product photo of bedding', 'a product photo of a towel'),
    'Электроника': ('a product photo of headphones', 'a product photo of a phone charger', 'a product photo of a lamp'),
    'Украшения': ('a product photo of earrings', 'a product photo of a necklace', 'a product photo of a ring'),
    'Детские товары': ('a product photo of a stroller', 'a product photo of baby diapers'),
    'Спорт и отдых': ('a product photo of a soccer ball', 'a product photo of camping equipment'),
    'Зоотовары': ('a product photo of a dog collar', 'a product photo of a pet bed'),
    'Канцтовары': ('a product photo of a notebook', 'a product photo of pens'),
    'Инструменты и ремонт': ('a product photo of a drill', 'a product photo of hand tools'),
    # An explicit outside class keeps unrelated images from forced labels.
    '_other': ('a photo of food', 'a photo of a car', 'a photo of a building', 'a photo of a person', 'a photo of fabric', 'a photo of a watch'),
}


@lru_cache(maxsize=1)
def text_vectors():
    import open_clip
    model, _, torch = _model_bundle()
    entries = [(category, prompt) for category, prompts in PROMPTS.items() for prompt in prompts]
    tokens = open_clip.get_tokenizer(MODEL_ARCH)([prompt for _, prompt in entries])
    with torch.inference_mode():
        vectors = model.encode_text(tokens).float()
        vectors = vectors / vectors.norm(dim=-1, keepdim=True).clamp(min=1e-12)
    return [(entry[0], vector) for entry, vector in zip(entries, vectors.cpu().tolist())]


def photo_vote(vector):
    if len(vector) != DIM or not all(math.isfinite(v) for v in vector):
        raise ValueError('Invalid image vector')
    norm = math.sqrt(sum(v*v for v in vector))
    if norm < 1e-12:
        raise ValueError('Empty image vector')
    scores = {}
    for category, candidate in text_vectors():
        value = sum(a*b for a, b in zip(vector, candidate)) / norm
        scores[category] = max(scores.get(category, -1.0), value)
    ranked = sorted(scores.items(), key=lambda p: p[1], reverse=True)
    category, score = ranked[0]
    confident = category != '_other' and score >= .28 and score - ranked[1][1] >= .05
    return category, score, confident




# Finer visual categories are only assigned when the product's image is
# unambiguous. Ambiguous photos retain the broad group (e.g. 'Игрушки').
TOY_LEAF_PROMPTS = {
    'toys-plush': (
        'a product photo of a soft plush monkey toy',
        'a product photo of a stuffed plush animal toy',
        'a product photo of a teddy bear stuffed toy',
    ),
    'toys-dolls': ('a product photo of a plastic fashion doll toy',),
    'toys-cars': ('a product photo of a toy car',),
    'toys-construction': ('a product photo of plastic building blocks toy',),
    '_other': ('a product photo of a sweatshirt', 'a product photo of shoes'),
}


@lru_cache(maxsize=1)
def toy_text_vectors():
    import open_clip
    model, _, torch = _model_bundle()
    entries = [(category, prompt) for category, prompts in
               TOY_LEAF_PROMPTS.items() for prompt in prompts]
    tokens = open_clip.get_tokenizer(MODEL_ARCH)(
        [prompt for _, prompt in entries])
    with torch.inference_mode():
        vectors = model.encode_text(tokens).float()
        vectors = vectors / vectors.norm(dim=-1, keepdim=True).clamp(min=1e-12)
    return [(entry[0], vector) for entry, vector in
            zip(entries, vectors.cpu().tolist())]


def toy_leaf_vote(vector):
    norm = math.sqrt(sum(x*x for x in vector))
    if len(vector) != DIM or norm < 1e-12:
        return None
    scores = {}
    for leaf, candidate in toy_text_vectors():
        score = sum(a*b for a, b in zip(vector, candidate)) / norm
        scores[leaf] = max(score, scores.get(leaf, -1.0))
    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    leaf, score = ranked[0]
    if leaf == '_other' or score < .29 or score - ranked[1][1] < .035:
        return None
    return leaf




def sync_taxonomy(db, product, state, photo_leaf=None):
    """Refresh the precise category without changing offer publication or review state."""
    leaf = resolve_leaf(product.title)
    if leaf is None and photo_leaf in BY_ID:
        leaf = photo_leaf
    legacy = LEGACY.get(product.category)
    # Keep explicit seller categories authoritative when a known legacy mapping exists.
    if state.source == 'manual':
        leaf = legacy
    elif state.status == 'conflict':
        leaf = None
    elif legacy and (leaf is None or path_ids(legacy)[0] != path_ids(leaf)[0]):
        leaf = legacy

    # Alembic seeds the entire taxonomy in deployed databases. The fallback
    # supports isolated ORM-created test DBs and remains additive/idempotent.
    if leaf and db.get(CatalogCategory, leaf) is None:
        positions = {id: i for i, (id, _, _) in enumerate(NODES_V1)}
        for node_id in path_ids(leaf):
            if db.get(CatalogCategory, node_id) is None:
                _, parent, name = BY_ID[node_id]
                db.add(CatalogCategory(id=node_id, parent_id=parent,
                                       name=name, position=positions[node_id]))
                db.flush()
    assignment = db.get(ProductCategoryAssignment, product.id)
    if not leaf:
        if assignment:
            db.delete(assignment)
        return
    if assignment is None:
        assignment = ProductCategoryAssignment(product_id=product.id,
                                               category_id=leaf,
                                               source=state.source)
        db.add(assignment)
    else:
        assignment.category_id = leaf
        assignment.source = state.source
    # Preserve existing legacy categories for old clients. New groups get a
    # meaningful root label instead of showing "Без категории" forever.
    if is_unassigned(product.category):
        root = path_ids(leaf)[0]
        product.category = BY_ID[root][2]
        state.assigned = product.category
        if state.status in ('needs_review', 'photo_model_disabled', 'photo_index_missing'):
            state.source = 'title'
            state.status = 'assigned'
        assignment.source = state.source


def mark_manual(db, product):
    state = db.get(ProductCategoryState, product.id)
    if state is None:
        state = ProductCategoryState(product_id=product.id)
        db.add(state)
    state.source = 'manual'
    state.status = 'assigned' if not is_unassigned(product.category) else 'needs_review'
    state.assigned = product.category
    state.suggestion = ''
    state.score = 0.0
    sync_taxonomy(db, product, state)
    return state


def assign_category(db, product, supplied=None):
    state = db.get(ProductCategoryState, product.id)
    # Pre-existing explicit categories and externally edited categories are manual.
    if (state is None and not is_unassigned(product.category)) or (
        state is not None and product.category != state.assigned and not is_unassigned(product.category)
    ):
        return mark_manual(db, product)
    if state is not None and state.source == 'manual' and not is_unassigned(product.category):
        sync_taxonomy(db, product, state)
        return state
    if state is None:
        state = ProductCategoryState(product_id=product.id)
        db.add(state)
    state.score, state.suggestion = 0.0, ''
    photo_leaf = None
    title_category = resolve_category(product.title)
    category = title_category
    state.source = 'title' if not is_unassigned(category) else 'unknown'
    state.status = 'assigned' if not is_unassigned(category) else 'needs_review'
    if product.images and SEARCH_BACKEND == 'clip':
        try:
            vectors = [db.get(ImageMLEmbedding, (img.id, MODEL_ID)) for img in product.images]
            if any(row is None for row in vectors):
                state.status = 'photo_index_missing'
                category = UNASSIGNED
            else:
                votes = [photo_vote(row.embedding) for row in vectors]
                state.score = min(vote[1] for vote in votes)
                categories = {vote[0] for vote in votes}
                if len(categories) == 1 and all(vote[2] for vote in votes):
                    photo_category = votes[0][0]
                    if photo_category == 'Игрушки':
                        leaves = [toy_leaf_vote(row.embedding) for row in vectors]
                        if leaves and leaves[0] is not None and len(set(leaves)) == 1:
                            photo_leaf = leaves[0]
                    state.suggestion = photo_category
                    if is_unassigned(title_category) or title_category == photo_category:
                        category = photo_category
                        state.source = 'photo' if is_unassigned(title_category) else 'title_and_photo'
                        state.status = 'assigned'
                    else:
                        category, state.status = UNASSIGNED, 'conflict'
                else:
                    category, state.status = UNASSIGNED, 'needs_review'
        except Exception:
            # Upload remains saved. The category API truthfully reports unavailable.
            log.exception('Category inference unavailable for product %s', product.id)
            category, state.status = UNASSIGNED, 'model_unavailable'
    elif product.images and is_unassigned(category):
        state.status = 'photo_model_disabled'
    product.category = category
    state.assigned = category
    sync_taxonomy(db, product, state, photo_leaf=photo_leaf)
    return state


def describe(db, product):
    state = db.get(ProductCategoryState, product.id)
    if not state:
        return {'source': 'legacy', 'status': 'needs_review' if is_unassigned(product.category) else 'assigned'}
    return {'source': state.source, 'status': state.status, 'suggestion': state.suggestion,
            'score': state.score, 'score_kind': 'cosine_similarity', 'photo_model': MODEL_ID if SEARCH_BACKEND == 'clip' else None}


def reclassify_indexed_products(db):
    """Idempotently refresh existing products after ML backfills their images.

    Merchant-selected manual categories are never overwritten. Products retain
    their publication and moderation status regardless of inference outcome.
    """
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload
    from .models import Product
    products = db.scalars(select(Product).options(
        selectinload(Product.images),
        selectinload(Product.category_assignment))).all()
    changed = 0
    for product in products:
        state = db.get(ProductCategoryState, product.id)
        if state is not None and state.source == 'manual':
            continue
        before = product.category_assignment.category_id if product.category_assignment else None
        assign_category(db, product)
        db.flush()
        assigned = db.get(ProductCategoryAssignment, product.id)
        if (assigned.category_id if assigned else None) != before:
            changed += 1
    db.commit()
    log.info('Reclassified %s of %s indexed products', changed, len(products))
    return changed
