"""Deterministic, CPU-only visual descriptor. NOT semantic ML or an exact-match classifier.

Encodes 4x4 RGB layout (48), 8-bin/channel histograms (24), 4x4 edge energy
(16) and 8-bin edge orientation (8). Produces a unit-length 96D vector.
Photos of the SAME item under similar lighting often score closer; visually
similar but semantically different items can be confused. See README.
"""
from io import BytesIO

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError
from .config import FEATURE_DIM

Image.MAX_IMAGE_PIXELS = 20_000_000


class InvalidImage(ValueError):
    pass


def descriptor_from_bytes(data: bytes) -> list[float]:
    try:
        with Image.open(BytesIO(data)) as source:
            if source.format not in ("JPEG", "PNG", "WEBP"):
                raise InvalidImage("Поддерживаются только JPEG, PNG и WebP")
            image = ImageOps.exif_transpose(source).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise InvalidImage("Не удалось прочитать изображение JPEG, PNG или WebP") from exc
    if min(image.size) < 24:
        raise InvalidImage("Изображение слишком маленькое (минимум 24×24 пикселя)")
    a = np.asarray(image.resize((64, 64), Image.Resampling.LANCZOS), dtype=np.float32) / 255.0
    grid_rgb = a.reshape(4, 16, 4, 16, 3).mean(axis=(1, 3)).flatten() * 1.6
    hist = np.concatenate([np.histogram(a[..., c], bins=8, range=(0, 1))[0].astype(np.float32) / (64*64) for c in range(3)]) * 1.2
    gray = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    gy, gx = np.gradient(gray)
    magnitude = np.sqrt(gx**2 + gy**2)
    edge_grid = magnitude.reshape(4, 16, 4, 16).mean(axis=(1, 3)).flatten() * 12.0
    directions = np.arctan2(gy, gx)
    edge_hist = np.histogram(directions, bins=8, range=(-np.pi, np.pi), weights=magnitude)[0].astype(np.float32)
    edge_hist = edge_hist / max(float(edge_hist.sum()), 1e-8) * 1.2
    vec = np.concatenate([grid_rgb, hist, edge_grid, edge_hist]).astype(np.float32)
    assert vec.size == FEATURE_DIM, f"bad dimension: {vec.size}"
    vec /= max(float(np.linalg.norm(vec)), 1e-8)
    return vec.tolist()


def similarity(a: list[float], b: list[float]) -> float:
    return float(np.dot(np.asarray(a, dtype=np.float32), np.asarray(b, dtype=np.float32)))
