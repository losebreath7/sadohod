"""Search regression: broad categories must not return unrelated products."""
from types import SimpleNamespace

from backend.app.search_relevance import (
    category_query_root, product_root, ranked_product_ids,
)


def item(pid, category="Без категории", title="", leaf=None):
    assigned = SimpleNamespace(category_id=leaf) if leaf else None
    return SimpleNamespace(id=pid, title=title, category=category,
                           category_assignment=assigned)


def test_tools_is_broad_category_request():
    assert category_query_root("инструменты") == "tools"
    assert category_query_root("Инструменты и ремонт") == "tools"


def test_other_broad_categories_are_derived_from_taxonomy():
    assert category_query_root("электроника") == "electronics"
    assert category_query_root("игрушки") == "toys"
    assert category_query_root("канцтовары") == "office"


def test_unrelated_items_never_pad_tools_results():
    rows = {
        "bag": item("bag", category="Сумки"),
        "pen": item("pen", category="Канцтовары"),
        "ring": item("ring", category="Украшения"),
        "case": item("case", category="Электроника"),
        "kit": item("kit", category="Инструменты и ремонт"),
    }
    ids = ranked_product_ids(
        text_ids=["kit"],
        clip_ids=["bag", "pen", "ring", "case", "kit"],
        caption_ids=["ring", "kit"],
        product_by_id=rows, query="инструменты", limit=60)
    assert ids == ["kit"]


def test_untitled_unclassified_kit_uses_two_models():
    rows = {
        "untyped": item("untyped"),
        "unrelated": item("unrelated", category="Украшения"),
        "weak": item("weak"),
    }
    ids = ranked_product_ids(
        text_ids=[], clip_ids=["unrelated", "untyped", "weak"],
        caption_ids=["untyped"], product_by_id=rows,
        query="инструменты", limit=60)
    assert ids == ["untyped"]


def test_authoritative_category_above_weak_semantic_hit():
    rows = {
        "confirmed": item("confirmed", leaf="tools-hand"),
        "uncertain": item("uncertain"),
    }
    ids = ranked_product_ids(
        text_ids=["confirmed"], clip_ids=["uncertain", "confirmed"],
        caption_ids=["uncertain"], product_by_id=rows,
        query="инструменты", limit=60)
    assert ids[0] == "confirmed"


def test_unknown_query_keeps_open_vocabulary_search():
    rows = {"unknown": item("unknown")}
    ids = ranked_product_ids(
        text_ids=[], clip_ids=[], caption_ids=["unknown"],
        product_by_id=rows, query="редкая деталь станка", limit=60)
    assert ids == ["unknown"]


def test_explicit_title_category_can_recover_missing_taxonomy():
    rows = {"kit": item("kit", title="Набор инструментов")}
    ids = ranked_product_ids(
        text_ids=["kit"], clip_ids=[], caption_ids=[],
        product_by_id=rows, query="инструменты", limit=60)
    assert ids == ["kit"]
