"""Optional CPU OpenCLIP encoder. Only active with SEARCH_BACKEND=clip.

Weights must be downloaded from the designated pretrained checkpoint on first use.
Never silently substitute random initialization or the classic descriptor.
"""
from functools import lru_cache
from io import BytesIO
import math
import os

from PIL import Image, ImageOps
from .image_features import InvalidImage

MODEL_ARCH = 'ViT-B-32'
MODEL_WEIGHTS = 'laion2b_s34b_b79k'
MODEL_ID = f'openclip-{MODEL_ARCH}-{MODEL_WEIGHTS}'
DIM = 512


@lru_cache(maxsize=1)
def _model_bundle():
    try:
        import torch
        import open_clip
    except ImportError as exc:
        raise RuntimeError('Не установлен OpenCLIP: используйте RUN_ML_SEARCH.bat или requirements-ml.txt') from exc
    torch.set_num_threads(max(1, min(4, os.cpu_count() or 2)))
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_ARCH, pretrained=MODEL_WEIGHTS, device='cpu')
    model.eval()
    return model, preprocess, torch


def embed_image(data: bytes) -> list[float]:
    try:
        with Image.open(BytesIO(data)) as src:
            if src.format not in ('JPEG', 'PNG', 'WEBP'):
                raise InvalidImage('Поддерживаются JPEG, PNG и WebP')
            image = ImageOps.exif_transpose(src).convert('RGB')
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        raise InvalidImage('Не удалось прочитать фотографию') from exc
    if min(image.size) < 24:
        raise InvalidImage('Слишком маленькое изображение')
    model, preprocess, torch = _model_bundle()
    with torch.inference_mode():
        tensor = preprocess(image).unsqueeze(0)
        vector = model.encode_image(tensor).float().squeeze(0)
        vector = vector / vector.norm().clamp(min=1e-12)
        values = vector.cpu().tolist()
    if len(values) != DIM or not all(math.isfinite(v) for v in values):
        raise RuntimeError('Модель выдала некорректный вектор')
    return values
