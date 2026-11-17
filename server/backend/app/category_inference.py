"""Title + optional real OpenCLIP photo inference, with explicit abstention.

Cosine thresholds are conservative heuristics, NOT calibrated probabilities.
Photo inference is available only with the existing SEARCH_BACKEND=clip stack.
"""
from functools import lru_cache
import logging
import math

from .config import SEARCH_BACKEND
from .merchant_models import ProductCategoryState, ProductCategoryAssignment
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM, _model_bundle, MODEL_ARCH
from .product_categories import resolve_category, is_unassigned, UNASSIGNED
from .catalog_taxonomy import LEGACY, BY_ID, path_ids, resolve_leaf

log = logging.getLogger(__name__)
PROMPTS = {
    'Верхняя одежда': ('a photo of a winter jacket', 'a photo of a coat', 'a photo of a puffer jacket'),
    'Сумки': ('a photo of a handbag', 'a photo of a backpack', 'a photo of a purse'),
    'Обувь': ('a photo of sneakers', 'a photo of boots', 'a photo of shoes'),
    'Платья': ('a photo of a dress', 'a photo of a sundress'),
    'Одежда': ('a photo of a t-shirt', 'a photo of a hoodie', 'a photo of jeans', 'a photo of a skirt', 'a photo of a sweater', 'a photo of a shirt'),
    # An explicit outside class keeps unrelated images from being forced into clothing.
    '_other': ('a photo of furniture', 'a photo of electronics', 'a photo of food', 'a photo of cosmetics', 'a photo of jewelry', 'a photo of a toy', 'a photo of a belt', 'a photo of fabric', 'a photo of a watch', 'a photo of a hat'),
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



def sync_taxonomy(db, product, state):
    """Refresh the precise category without changing offer publication or review state."""
    leaf = resolve_leaf(product.title)
    legacy = LEGACY.get(product.category)
    # Keep explicit seller categories authoritative when a known legacy mapping exists.
    if state.source == 'manual':
        leaf = legacy
    elif state.status == 'conflict':
        leaf = None
    elif legacy and (leaf is None or legacy not in path_ids(leaf)):
        leaf = legacy

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
    sync_taxonomy(db, product, state)
    return state


def describe(db, product):
    state = db.get(ProductCategoryState, product.id)
    if not state:
        return {'source': 'legacy', 'status': 'needs_review' if is_unassigned(product.category) else 'assigned'}
    return {'source': state.source, 'status': state.status, 'suggestion': state.suggestion,
            'score': state.score, 'score_kind': 'cosine_similarity', 'photo_model': MODEL_ID if SEARCH_BACKEND == 'clip' else None}
