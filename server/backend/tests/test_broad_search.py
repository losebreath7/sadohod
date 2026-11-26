"""Regression tests for broad, untitled-product image retrieval.

Run from the server directory: python -m pytest backend/tests/test_broad_search.py
Tests do not download neural weights; they verify the routing of user text to
the model-backed retrieval path.
"""
from backend.app.text_search import visual_prompts, _broad_taxonomy_prompts


def test_tools_query_resolves_to_image_prompts():
    prompts = visual_prompts("инструменты")
    assert prompts
    assert any("tool" in prompt or "drill" in prompt for prompt in prompts)


def test_multiple_catalog_roots_are_supported():
    for query in ("одежда", "электроника", "канцтовары", "игрушки", "зоотовары"):
        assert _broad_taxonomy_prompts(query), query


def test_unknown_query_does_not_invent_a_category():
    assert _broad_taxonomy_prompts("неизвестное изделие") == ()


def test_specific_queries_remain_precise():
    prompts = visual_prompts("кольцо")
    assert any("ring" in prompt for prompt in prompts)
