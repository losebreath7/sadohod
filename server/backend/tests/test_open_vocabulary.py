"""Open-vocabulary retrieval regressions without downloading model weights."""
from io import BytesIO
from PIL import Image

from backend.app import open_vocabulary as ov


def _photo():
    image = Image.new("RGB", (64, 64), "white")
    buffer = BytesIO()
    image.save(buffer, format="JPEG")
    return buffer.getvalue()


def test_caption_embedding_uses_caption_not_fixed_taxonomy(monkeypatch):
    calls = []
    monkeypatch.setattr(ov, "describe_image",
                        lambda _data: "an unfamiliar object on a table")
    monkeypatch.setattr(ov, "embed_text",
                        lambda query: calls.append(query) or [0.0] * ov.DIM)
    vector = ov.caption_embedding(_photo())
    assert len(vector) == 512
    assert calls == ["a product photo of an unfamiliar object on a table"]


def test_unknown_russian_query_is_not_rejected_by_taxonomy(monkeypatch):
    monkeypatch.setattr(ov, "english_query",
                        lambda q: "unusual replacement part for a machine")
    prompts = []
    monkeypatch.setattr(ov, "embed_text",
                        lambda s: prompts.append(s) or [0.0] * ov.DIM)
    assert ov.open_query_vector("необычная запчасть для станка") is not None
    assert prompts == ["a product photo of unusual replacement part for a machine"]


def test_blank_query_has_no_embedding(monkeypatch):
    assert ov.english_query("   ") == ""
    assert ov.open_query_vector("") is None


def test_versioned_caption_model_does_not_replace_original_image_index():
    from backend.app.ml_clip import MODEL_ID
    assert ov.CAPTION_MODEL_ID != MODEL_ID
    assert len(ov.CAPTION_MODEL_ID) <= 140

def test_english_unknown_product_phrase_needs_no_translation_weights():
    assert ov.english_query("an unusual machine spare part") == "an unusual machine spare part"
