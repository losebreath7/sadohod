"""Open-vocabulary photo captions and Russian-to-English search queries.

This is a separate, versioned image index. It never changes seller titles,
manually chosen categories, publication status, or moderation decisions.
Captions are encoded into the existing CLIP vector space for pgvector search.
"""
from functools import lru_cache
from io import BytesIO
import math
import re

from PIL import Image, ImageOps

from .image_features import InvalidImage
from .ml_clip import DIM, MODEL_ID as CLIP_MODEL_ID, embed_text

CAPTION_CHECKPOINT = "Salesforce/blip-image-captioning-base"
TRANSLATION_CHECKPOINT = "Helsinki-NLP/opus-mt-ru-en"
CAPTION_MODEL_ID = f"{CLIP_MODEL_ID}-caption-blip-base-v1"


@lru_cache(maxsize=1)
def _caption_bundle():
    import torch
    from transformers import BlipForConditionalGeneration, BlipProcessor

    processor = BlipProcessor.from_pretrained(CAPTION_CHECKPOINT)
    model = BlipForConditionalGeneration.from_pretrained(CAPTION_CHECKPOINT)
    model.eval()
    return processor, model, torch


def describe_image(data: bytes) -> str:
    """Describe a real image, with no predefined product/category vocabulary."""
    try:
        with Image.open(BytesIO(data)) as source:
            if source.format not in ("JPEG", "PNG", "WEBP"):
                raise InvalidImage("Поддерживаются JPEG, PNG и WebP")
            photo = ImageOps.exif_transpose(source).convert("RGB")
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        raise InvalidImage("Не удалось прочитать фотографию") from exc
    if min(photo.size) < 24:
        raise InvalidImage("Слишком маленькое изображение")
    processor, model, torch = _caption_bundle()
    batch = processor(images=photo, return_tensors="pt")
    with torch.inference_mode():
        tokens = model.generate(**batch, max_new_tokens=48, num_beams=3)
    caption = processor.decode(tokens[0], skip_special_tokens=True).strip()
    if not caption:
        raise RuntimeError("Caption model returned an empty description")
    return caption


def caption_embedding(data: bytes) -> list[float]:
    """Produce the same 512D embedding as the existing CLIP query index."""
    caption = describe_image(data)
    vector = embed_text("a product photo of " + caption)
    if len(vector) != DIM or not all(math.isfinite(x) for x in vector):
        raise RuntimeError("Invalid caption embedding")
    return vector


@lru_cache(maxsize=1)
def _translator_bundle():
    from transformers import MarianMTModel, MarianTokenizer

    tokenizer = MarianTokenizer.from_pretrained(TRANSLATION_CHECKPOINT)
    model = MarianMTModel.from_pretrained(TRANSLATION_CHECKPOINT)
    model.eval()
    return tokenizer, model


@lru_cache(maxsize=256)
def english_query(query: str) -> str:
    """Translate arbitrary Russian item descriptions, not just known labels."""
    cleaned = " ".join(query.strip().split())[:80]
    if not cleaned:
        return ""
    if not re.search(r"[а-яё]", cleaned, re.IGNORECASE):
        return cleaned
    tokenizer, model = _translator_bundle()
    encoded = tokenizer([cleaned], return_tensors="pt", truncation=True,
                        max_length=96)
    import torch
    with torch.inference_mode():
        output = model.generate(**encoded, max_new_tokens=96, num_beams=2)
    translated = tokenizer.batch_decode(output, skip_special_tokens=True)[0].strip()
    if not translated:
        raise RuntimeError("Translation model returned an empty query")
    return translated


def open_query_vector(query: str) -> list[float] | None:
    translated = english_query(query)
    return embed_text("a product photo of " + translated) if translated else None


def open_vocabulary_image_ids(session, query: str, limit: int = 30,
                              min_score: float = 0.24) -> list[str]:
    """Retrieve any recognised photo by its caption, without taxonomy gates."""
    from sqlalchemy import select
    from .models import ProductImage
    from .search import ranked_images

    vector = open_query_vector(query)
    if vector is None:
        return []
    matches = ranked_images(session, vector, limit=limit * 4,
                            model_id=CAPTION_MODEL_ID)
    relevant = [(iid, score) for iid, score in matches if score >= min_score]
    if not relevant:
        return []
    product_ids = dict(session.execute(
        select(ProductImage.id, ProductImage.product_id).where(
            ProductImage.id.in_([iid for iid, _ in relevant]))).all())
    found = []
    seen = set()
    for iid, _score in relevant:
        pid = product_ids.get(iid)
        if pid is not None and pid not in seen:
            found.append(pid)
            seen.add(pid)
        if len(found) == limit:
            break
    return found
