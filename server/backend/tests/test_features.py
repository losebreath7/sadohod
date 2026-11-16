from io import BytesIO
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageEnhance

from backend.app.config import MEDIA
from backend.app.image_features import InvalidImage, descriptor_from_bytes, similarity


def test_descriptor_normalized():
    v = descriptor_from_bytes((MEDIA / "p01.jpg").read_bytes())
    assert len(v) == 96
    assert float(np.linalg.norm(v)) == pytest.approx(1.0, abs=1e-5)


def test_identical_image_scores_higher_than_different():
    image = Image.open(MEDIA / "p01.jpg").convert("RGB")
    altered = ImageEnhance.Brightness(image).enhance(1.08)
    out = BytesIO()
    altered.resize((200, 220)).save(out, format="JPEG", quality=83)
    q = descriptor_from_bytes(out.getvalue())
    a = descriptor_from_bytes((MEDIA / "p01.jpg").read_bytes())
    b = descriptor_from_bytes((MEDIA / "p02.jpg").read_bytes())
    assert similarity(q, a) > similarity(q, b)


def test_invalid_upload():
    with pytest.raises(InvalidImage):
        descriptor_from_bytes(b"not an image")
