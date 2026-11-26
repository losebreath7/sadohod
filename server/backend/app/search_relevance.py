"""Relevance gates for buyer text search.

Known category searches must never be filled with unrelated neighbours from
an embedding index. Untitled products without a category can still enter when
two independent retrieval paths agree; the ranker does not fabricate labels.
"""
from .catalog_taxonomy import BY_ID, LEGACY, path_ids, resolve_leaf
from .product_semantics import normalize, _stem_label, query_terms


_GENERIC_TOKENS = {"товары", "товар", "для", "и", "по", "ремонт", "уход", "аксессуары"}


def category_query_root(query: str) -> str | None:
    """Resolve only unambiguous broad catalog labels, not arbitrary phrases."""
    value = normalize(query)
    if not value:
        return None
    roots = [(key, title) for key, parent, title in BY_ID.values()
             if parent is None]
    # Full labels (including their word forms) precede single-label tokens.
    terms = query_terms(value)
    exact = [key for key, title in roots if normalize(title) in terms]
    if len(exact) == 1:
        return exact[0]
    if len(value.split()) != 1 or len(value) < 4:
        return None
    root_matches = []
    for key, title in roots:
        tokens = [token for token in normalize(title).split()
                  if token not in _GENERIC_TOKENS and len(token) >= 4]
        if any(_stem_label(value) == _stem_label(token) for token in tokens):
            root_matches.append(key)
    return root_matches[0] if len(root_matches) == 1 else None


def product_root(product) -> str | None:
    assignment = getattr(product, "category_assignment", None)
    category_id = getattr(assignment, "category_id", None)
    if category_id not in BY_ID:
        category_id = LEGACY.get(getattr(product, "category", ""))
    if category_id not in BY_ID:
        category_id = resolve_leaf(getattr(product, "title", ""))
    if category_id in BY_ID:
        return path_ids(category_id)[0]
    return None


def root_matches(product, root: str | None) -> bool | None:
    """True: known compatible; False: known conflicting; None: uncertain."""
    if root is None:
        return None
    actual = product_root(product)
    return actual == root if actual else None


def ranked_product_ids(text_ids, clip_ids, caption_ids, product_by_id, query,
                       limit: int):
    """Priority: verified category/exact text, then two-model agreement.

    For a broad category query, items in unrelated *known* categories never
    appear. Unclassified items require agreement across both visual models,
    rather than just a weak nearest-neighbour score.
    """
    root = category_query_root(query)
    positions = {
        "text": {pid: n for n, pid in enumerate(text_ids)},
        "clip": {pid: n for n, pid in enumerate(clip_ids)},
        "caption": {pid: n for n, pid in enumerate(caption_ids)},
    }
    results = []
    for pid, product in product_by_id.items():
        has_text = pid in positions["text"]
        has_clip = pid in positions["clip"]
        has_caption = pid in positions["caption"]
        known = root_matches(product, root)
        if root and known is False:
            continue
        if root and known is None and not (has_text or (has_clip and has_caption)):
            continue
        if not (has_text or has_clip or has_caption):
            continue
        # Prefer authoritative taxonomy and textual matches. Rank among
        # semantic candidates by reciprocal rank fusion, not concatenation.
        score = (
            (1000 if root and known is True else 0)
            + (300 if has_text else 0)
            + (35 if has_clip and has_caption else 0)
            + sum(24 / (8 + pos[pid]) for pos in positions.values() if pid in pos)
        )
        results.append((-score, str(pid), pid))
    results.sort()
    return [pid for _, _, pid in results[:limit]]
