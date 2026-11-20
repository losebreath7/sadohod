"""Title + optional real OpenCLIP photo inference, with explicit abstention.

Cosine thresholds are conservative heuristics, NOT calibrated probabilities.
Photo inference is available only with the existing SEARCH_BACKEND=clip stack.
"""
from collections import Counter
from functools import lru_cache
import logging
import math

from .config import SEARCH_BACKEND
from .merchant_models import ProductCategoryState, ProductCategoryAssignment, CatalogCategory
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM, _model_bundle, MODEL_ARCH
from .product_categories import resolve_category, is_unassigned, UNASSIGNED
from .catalog_taxonomy import NODES_V1, LEGACY, BY_ID, path_ids, resolve_leaf
from .product_semantics import sync_search_facets

log = logging.getLogger(__name__)
PROMPTS = {
    'Верхняя одежда': ('a photo of a winter jacket', 'a photo of a coat', 'a photo of a puffer jacket'),
    'Сумки': ('a photo of a handbag', 'a photo of a backpack', 'a photo of a purse', 'a product photo of a winter hat', 'a leather wallet for sale', 'a leather belt for sale'),
    'Обувь': ('a photo of sneakers', 'a photo of boots', 'a photo of shoes'),
    'Платья': ('a photo of a dress', 'a photo of a sundress'),
    'Одежда': ('a photo of a t-shirt', 'a photo of a hoodie', 'a photo of jeans', 'a photo of a skirt', 'a photo of a sweater', 'a photo of a shirt'),
    'Игрушки': ('a product photo of a doll toy', 'a product photo of a plush toy', 'a product photo of building blocks', 'a tabletop board game for sale'),
    'Красота и уход': ('a product photo of facial cream', 'a product photo of lipstick', 'a product photo of shampoo', 'a product photo of perfume', 'a tube of mascara'),
    'Товары для дома': ('a product photo of a saucepan', 'a product photo of bedding', 'a product photo of a towel', 'a product photo of a carpet or rug', 'a ceramic mug', 'a plastic household organizer', 'a decorative vase'),
    'Электроника': ('a product photo of headphones', 'a product photo of a phone charger', 'a product photo of a lamp', 'a mobile phone case for sale'),
    'Украшения': ('a product photo of earrings', 'a product photo of a necklace', 'a product photo of a ring'),
    'Детские товары': ('a product photo of a stroller', 'a product photo of baby diapers', 'a feeding bottle for a baby'),
    'Спорт и отдых': ('a product photo of a soccer ball', 'a product photo of camping equipment', 'a product photo of dumbbells'),
    'Зоотовары': ('a product photo of a dog collar', 'a product photo of a pet bed', 'a dog chew toy for sale'),
    'Канцтовары': ('a product photo of a notebook', 'a product photo of pens', 'a set of colored pencils'),
    'Инструменты и ремонт': ('a product photo of a drill', 'a product photo of hand tools'),
    'Сезонные товары': ('Christmas tree ornaments in a box', 'holiday decorations for sale', 'a gift set wrapped with a ribbon'),
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
    'toys-board': ('a tabletop board game with cards and playing pieces',),
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




# English-language OpenCLIP prompts for more precise, non-invented leaves.
# Conservative comparisons: no ML result is treated as a calibrated certainty.
VISUAL_LEAF_PROMPTS = {
    'clothing-skirts': ('a product photo of a skirt', 'a short plaid mini skirt on a plain background'),
    'clothing-trousers': ('a product photo of trousers', 'a pair of pants for sale'),
    'clothing-jeans': ('a product photo of denim jeans',),
    'clothing-shirts': ('a product photo of a button-up shirt',),
    'clothing-tshirts': ('a product photo of a t-shirt',),
    'clothing-hoodies': ('a product photo of a hoodie',),
    'clothing-dresses': ('a product photo of a dress',),
    'clothing-jackets': ('a product photo of a winter jacket',),
    'clothing-coats': ('a product photo of a wool coat',),
    'shoes-sneakers': ('a product photo of sneakers',),
    'shoes-boots': ('a product photo of boots',),
    'shoes-sandals': ('a product photo of sandals',),
    'bags-handbags': ('a product photo of a handbag',),
    'bags-backpacks': ('a product photo of a backpack',),
    'bags-hats': ('a product photo of a warm winter hat', 'a knitted beanie hat'),
    'toys-plush': ('a product photo of a soft stuffed toy monkey',
                   'a plush toy rabbit on a white background',
                   'a cuddly stuffed animal soft toy'),
    'toys-dolls': ('a product photo of a fashion doll toy',),
    'toys-construction': ('a product photo of a toy building block set',),
    'toys-cars': ('a product photo of a toy car',),
    'jewelry-rings': ('a product photo of a silver ring',
                       'a product photo of a gemstone finger ring'),
    'jewelry-earrings': ('a product photo of earrings',),
    'jewelry-necklaces': ('a product photo of a necklace',),
    'jewelry-bracelets': ('a product photo of a bracelet',),
    'home-textile': ('a product photo of a rug or floor carpet',
                     'a product photo of home textile',),
    'home-bedding': ('a product photo of bed sheets',),
    'home-pots': ('a product photo of a cooking pot',),
    'home-pans': ('a product photo of a frying pan',),
    'electronics-lighting': ('a product photo of a table lamp',
                             'a product photo of a desk lamp',),
    'electronics-headphones': ('a product photo of headphones',),
    'beauty-lipstick': ('a product photo of a lipstick',),
    'beauty-shampoo': ('a product photo of shampoo',),
    # Additional stable taxonomy leaves; visual guesses remain conservative.
    'clothing-underwear': ("a product photo of a set of underwear", "a product photo of a bra"),
    'bags-wallets': ("a product photo of a leather wallet", "a wallet with card slots"),
    'bags-belts': ("a product photo of a leather waist belt", "a clothing belt with buckle"),
    'toys-board': ("a board game box with playing cards and pieces", "a tabletop board game with dice"),
    'beauty-face-cream': ("a jar of facial skincare cream", "a product photo of face moisturizer"),
    'beauty-mascara': ("a cosmetic mascara wand and tube", "a product photo of mascara for eyelashes"),
    'beauty-fragrance': ("a product photo of a perfume bottle", "a fragrance spray bottle for sale"),
    'home-cups': ("a product photo of a ceramic coffee mug", "a porcelain teacup and saucer"),
    'home-towels': ("a folded bath towel for sale", "a product photo of cotton towels"),
    'home-decor': ("a decorative ceramic vase on a table", "a decorative home figurine for sale"),
    'home-storage': ("a household storage organizer with compartments", "a plastic storage box with a lid"),
    'electronics-phone': ("a smartphone protective case for sale", "a phone cover accessory"),
    'electronics-chargers': ("a USB phone charger and power adapter", "a charging cable with wall plug"),
    'kids-strollers': ("a baby stroller pram for sale", "a folding infant pushchair"),
    'kids-feeding': ("a baby feeding bottle for milk", "a baby sippy cup for feeding"),
    'kids-diapers': ("a pack of baby diapers", "disposable baby nappies in a package"),
    'sport-fitness': ("dumbbells for weight training", "an exercise fitness mat and resistance band"),
    'sport-balls': ("a product photo of a soccer ball", "an inflatable basketball for sale"),
    'sport-camping': ("a camping tent for hiking", "a rolled up sleeping bag for camping"),
    'pets-collars': ("a dog collar with buckle", "a pet collar for a cat"),
    'pets-beds': ("a soft pet bed for a dog", "a fluffy cat pet sleeping bed"),
    'pets-toys': ("a rubber chew toy for a dog", "a rope toy for a pet"),
    'office-notebooks': ("a spiral notebook for school", "a stationery notebook with pages"),
    'office-pens': ("ballpoint pens for writing", "a set of colored pencils"),
    'tools-hand': ("a metal hand hammer", "a hand screwdriver and wrench"),
    'tools-electric': ("a cordless electric power drill", "an electric screwdriver power tool"),
    'seasonal-christmas': ("Christmas tree ornaments and baubles", "festive holiday garland decorations"),
    'seasonal-gifts': ("a wrapped gift box with ribbon", "a packaged gift set for a holiday"),
    '_other': ('a photograph of a person', 'an abstract picture',
               'a building exterior', 'a printed image on a shirt'),
}

ANIMAL_TOY_PROMPTS = {
    'обезьяна': ('a plush monkey toy with round ears', 'a stuffed monkey soft toy'),
    'заяц': ('a plush rabbit toy with long ears', 'a stuffed bunny soft toy'),
    'медведь': ('a stuffed teddy bear toy', 'a plush bear soft toy'),
    'кот': ('a plush cat toy', 'a stuffed kitten toy'),
    'собака': ('a plush dog toy', 'a stuffed puppy toy'),
    'лиса': ('a plush orange fox toy', 'a stuffed fox soft toy'),
    'слон': ('a plush elephant toy with a long trunk', 'a stuffed elephant animal toy'),
    'жираф': ('a yellow plush giraffe with a long neck', 'a stuffed giraffe toy'),
    'лев': ('a plush lion toy with a mane', 'a stuffed lion cub soft toy'),
    'тигр': ('a plush tiger toy with striped fur', 'a stuffed tiger soft toy'),
    'панда': ('a black and white plush panda bear', 'a stuffed panda soft toy'),
    'единорог': ('a plush unicorn toy with a horn', 'a stuffed unicorn soft toy'),
    'динозавр': ('a plush dinosaur toy', 'a stuffed dinosaur soft toy'),
    'пингвин': ('a black and white plush penguin toy', 'a stuffed penguin soft toy'),
    'лягушка': ('a green plush frog toy', 'a stuffed frog soft toy'),
    '_other': ('a toy car', 'a shirt with an animal print', 'a human portrait'),
}


@lru_cache(maxsize=2)
def _candidate_vectors(group):
    import open_clip
    prompts = VISUAL_LEAF_PROMPTS if group == 'leaf' else ANIMAL_TOY_PROMPTS
    model, _, torch = _model_bundle()
    entries = [(kind, prompt) for kind, texts in prompts.items() for prompt in texts]
    encoded = open_clip.get_tokenizer(MODEL_ARCH)([p for _, p in entries])
    with torch.inference_mode():
        vectors = model.encode_text(encoded).float()
        vectors = vectors / vectors.norm(dim=-1, keepdim=True).clamp(min=1e-12)
    return [(entry[0], vector) for entry, vector in zip(entries, vectors.cpu().tolist())]


def _candidate_vote(vector, group, min_score, margin):
    if len(vector) != DIM or not all(math.isfinite(x) for x in vector):
        return None
    norm = math.sqrt(sum(x*x for x in vector))
    if norm < 1e-12:
        return None
    scores = {}
    for name, candidate in _candidate_vectors(group):
        score = sum(a*b for a, b in zip(vector, candidate)) / norm
        scores[name] = max(score, scores.get(name, -1.0))
    ranked = sorted(scores.items(), key=lambda row: row[1], reverse=True)
    if len(ranked) < 2 or ranked[0][0] == '_other':
        return None
    winner, strength = ranked[0]
    if strength < min_score or strength - ranked[1][1] < margin:
        return None
    return winner


def visual_leaf_vote(vector):
    """Conservative fine-grained category; abstains on ambiguous photos."""
    return _candidate_vote(vector, 'leaf', .28, .035)


def toy_object_vote(vector):
    """Specific toy species only, never a category for animal-pattern clothing."""
    return _candidate_vote(vector, 'animal', .29, .04)


ROOT_TO_LEGACY = {
    'clothing': 'Одежда', 'shoes': 'Обувь', 'bags': 'Сумки',
    'toys': 'Игрушки', 'jewelry': 'Украшения',
    'beauty': 'Красота и уход', 'home': 'Товары для дома',
    'electronics': 'Электроника', 'kids': 'Детские товары',
    'sport': 'Спорт и отдых', 'pets': 'Зоотовары',
    'office': 'Канцтовары', 'tools': 'Инструменты и ремонт',
    'seasonal': 'Сезонные товары',
}


def legacy_for_leaf(leaf):
    if leaf == 'clothing-dresses':
        return 'Платья'
    if leaf in ('clothing-jackets', 'clothing-coats', 'clothing-kids-jackets'):
        return 'Верхняя одежда'
    return ROOT_TO_LEGACY.get(path_ids(leaf)[0]) if leaf in BY_ID else None


def sync_taxonomy(db, product, state, photo_leaf=None, photo_objects=(), preserve_photo_tags=False):
    """Refresh the precise category without changing offer publication or review state."""
    leaf = resolve_leaf(product.title)
    if leaf is None and photo_leaf in BY_ID:
        leaf = photo_leaf
    legacy = LEGACY.get(product.category)
    # Keep explicit seller categories authoritative when a known legacy mapping exists.
    if state.source == 'manual':
        # Preserve a precise existing descendant when its manually selected
        # legacy category is only a broad parent (e.g. "Верхняя одежда").
        previous = db.get(ProductCategoryAssignment, product.id)
        previous_leaf = previous.category_id if previous else None
        leaf = (previous_leaf if previous_leaf in BY_ID and legacy
                and legacy in path_ids(previous_leaf) else legacy)
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
        sync_search_facets(db, product, None, preserve_photos=preserve_photo_tags)
        return
    if assignment is None:
        assignment = ProductCategoryAssignment(product_id=product.id,
                                               category_id=leaf,
                                               source=state.source)
        db.add(assignment)
    else:
        assignment.category_id = leaf
        assignment.source = state.source
    # Preserve manual/legacy labels; an inferred leaf provides the correct
    # broad label for older buyer clients without inventing a product title.
    if is_unassigned(product.category):
        product.category = legacy_for_leaf(leaf) or BY_ID[path_ids(leaf)[0]][2]
        state.assigned = product.category
        if state.status in ('needs_review', 'photo_model_disabled', 'photo_index_missing'):
            state.source = 'photo' if photo_leaf else 'title'
            state.status = 'assigned'
        assignment.source = state.source
    sync_search_facets(db, product, leaf, photo_objects=photo_objects,
                       preserve_photos=preserve_photo_tags)


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
    sync_taxonomy(db, product, state, preserve_photo_tags=True)
    return state


def assign_category(db, product, supplied=None):
    state = db.get(ProductCategoryState, product.id)
    if (state is None and not is_unassigned(product.category)) or (
        state is not None and product.category != state.assigned
        and not is_unassigned(product.category)
    ):
        return mark_manual(db, product)
    if state is not None and state.source == 'manual' and not is_unassigned(product.category):
        sync_taxonomy(db, product, state, preserve_photo_tags=True)
        return state
    if state is None:
        state = ProductCategoryState(product_id=product.id)
        db.add(state)

    state.score, state.suggestion = 0.0, ''
    title_leaf = resolve_leaf(product.title)
    title_category = resolve_category(product.title)
    category = title_category
    photo_leaf = None
    photo_objects = set()
    photo_classified = False
    preserve_photo_tags = False
    state.source = 'title' if not is_unassigned(title_category) else 'unknown'
    state.status = 'assigned' if not is_unassigned(title_category) else 'needs_review'

    if product.images and SEARCH_BACKEND == 'clip':
        try:
            embeddings = [db.get(ImageMLEmbedding, (im.id, MODEL_ID))
                          for im in product.images]
            available = [row.embedding for row in embeddings if row is not None]
            if not available:
                state.status = 'photo_index_missing'
                preserve_photo_tags = True
            else:
                # Weak/out-of-frame photos do not cancel a confident first
                # image. Competing confident classes still cause abstention.
                votes = []
                for vector in available:
                    broad, score, confident = photo_vote(vector)
                    leaf = None
                    try:
                        if confident and broad == 'Игрушки':
                            leaf = toy_leaf_vote(vector)
                            if leaf is None:
                                leaf = visual_leaf_vote(vector)
                        else:
                            # Fine-grained vote has its own conservative
                            # absolute and runner-up thresholds. It can rescue
                            # a clear ring/skirt when the broad model abstains.
                            leaf = visual_leaf_vote(vector)
                    except (ImportError, RuntimeError):
                        # Optional fine classifier must not break an otherwise
                        # valid broad classification or a title assignment.
                        log.debug('Fine-grained OpenCLIP unavailable',
                                  exc_info=True)
                    if leaf is not None and confident:
                        inferred_broad = legacy_for_leaf(leaf)
                        compatible = (inferred_broad == broad or
                            (broad == 'Одежда' and inferred_broad in
                             ('Платья', 'Верхняя одежда', 'Одежда')) or
                            (inferred_broad == 'Одежда' and broad in
                             ('Платья', 'Верхняя одежда')))
                        if not compatible:
                            leaf = None
                    if leaf is not None or confident:
                        votes.append((leaf or LEGACY.get(broad), score))
                values = [name for name, _ in votes if name]
                ranked = Counter(values).most_common()
                state.score = max((score for _, score in votes), default=0.0)
                if ranked and (len(ranked) == 1 or ranked[0][1] > ranked[1][1]):
                    winner, count = ranked[0]
                    # Only meaningful votes count; blurry/unrecognised photos
                    # must not veto one clear, correctly recognised image.
                    if count >= math.ceil(len(votes) / 2):
                        photo_classified = True
                        photo_leaf = winner if winner in BY_ID else None
                        candidate_category = legacy_for_leaf(winner) if photo_leaf else winner
                        state.suggestion = candidate_category or ''
                        if title_leaf and photo_leaf and path_ids(title_leaf)[0] != path_ids(photo_leaf)[0]:
                            # Retain the explicit named product instead of
                            # replacing it with an unrelated predicted item.
                            state.status = 'conflict'
                        elif (not is_unassigned(title_category)
                              and candidate_category != title_category):
                            state.status = 'conflict'
                        else:
                            category = candidate_category or title_category
                            state.source = 'title_and_photo' if not is_unassigned(title_category) else 'photo'
                            state.status = 'assigned'
                            # Species detection only for confidently recognised
                            # plush toys, never a motif on clothes or bags.
                            if photo_leaf == 'toys-plush':
                                try:
                                    objects = [toy_object_vote(vector) for vector in available]
                                    valid = [o for o in objects if o]
                                    if valid and len(set(valid)) == 1:
                                        photo_objects.add(valid[0])
                                except Exception:
                                    # Species is optional; a prompt/encoder
                                    # failure cannot erase a valid category.
                                    log.warning('Toy species facet unavailable for %s',
                                                product.id, exc_info=True)
                else:
                    state.status = 'needs_review'
                if len(available) < len(product.images):
                    preserve_photo_tags = True
        except Exception:
            log.exception('Category inference unavailable for product %s', product.id)
            state.status = 'model_unavailable'
            preserve_photo_tags = True
    elif product.images:
        preserve_photo_tags = True
        if is_unassigned(category):
            state.status = 'photo_model_disabled'

    # Keep a previous automatic photo classification during an index outage.
    # A model restart must not remove products from their old category/search.
    if (preserve_photo_tags and product.images and not title_leaf
        and is_unassigned(category) and product.category_assignment is not None):
        photo_leaf = product.category_assignment.category_id
        category = product.category
        state.source = state.source if state.source not in ('unknown', 'title') else 'photo'

    # Never delete a confident title category because a weaker photo was
    # uncertain or ML temporarily failed.
    if not photo_classified and title_leaf:
        category = title_category if not is_unassigned(title_category) else (
            legacy_for_leaf(title_leaf) or UNASSIGNED)
    if title_leaf and photo_leaf and path_ids(title_leaf)[0] == path_ids(photo_leaf)[0]:
        # An explicit, precise product name outranks a generic photo label.
        photo_leaf = title_leaf
    if state.status == 'conflict':
        # The photo may suggest a useful alternate classification but is not
        # strong enough to replace the title or its category path.
        photo_leaf = None
        photo_objects.clear()
    product.category = category
    state.assigned = category
    sync_taxonomy(db, product, state, photo_leaf=photo_leaf,
                  photo_objects=photo_objects, preserve_photo_tags=preserve_photo_tags)
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
            # Manual taxonomy stays authoritative; keep auxiliary search
            # words populated without revisiting the category.
            sync_taxonomy(db, product, state, preserve_photo_tags=True)
            continue
        # Read the actual identity-map/DB row. A previously loaded
        # relationship may still cache None after the first insertion.
        previous = db.get(ProductCategoryAssignment, product.id)
        before = previous.category_id if previous else None
        assign_category(db, product)
        db.flush()
        assigned = db.get(ProductCategoryAssignment, product.id)
        if (assigned.category_id if assigned else None) != before:
            changed += 1
    db.commit()
    log.info('Reclassified %s of %s indexed products', changed, len(products))
    return changed
