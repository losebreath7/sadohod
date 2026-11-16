"""Versioned embeddings. Existing 96D table and old PostgreSQL volume are preserved."""
import logging
import math
from sqlalchemy import select, text
from sqlalchemy.orm import Session
from .config import MEDIA
from .database import is_postgres
from .models import ProductImage, ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM, embed_image

log = logging.getLogger(__name__)


def index_catalog(session: Session, embed=embed_image, media=MEDIA, model_id=MODEL_ID):
    images = session.scalars(select(ProductImage).order_by(ProductImage.id)).all()
    changed = 0
    for img in images:
        row = session.get(ImageMLEmbedding, (img.id, model_id))
        if row is None:
            vector = embed((media / img.filename).read_bytes())
            if len(vector) != DIM or not all(math.isfinite(float(v)) for v in vector):
                raise RuntimeError('ML-вектор должен содержать 512 конечных чисел')
            session.add(ImageMLEmbedding(image_id=img.id, model_id=model_id, embedding=vector))
            changed += 1
        elif len(row.embedding) != DIM:
            raise RuntimeError('В базе некорректная размерность ML-вектора; нужна переиндексация')
        session.flush()
        if is_postgres and session.bind.dialect.name == 'postgresql':
            vec = row.embedding if row else vector
            literal = '[' + ','.join(f'{v:.9f}' for v in vec) + ']'
            session.execute(text('''
                INSERT INTO product_image_ml_vectors (image_id, model_id, embedding)
                VALUES (:image_id, :model_id, CAST(:embedding AS vector))
                ON CONFLICT (image_id, model_id)
                DO UPDATE SET embedding = EXCLUDED.embedding
            '''), {'image_id': img.id, 'model_id': model_id, 'embedding': literal})
    session.commit()
    log.info('ML index ready: %s images, %s newly embedded, model=%s', len(images), changed, model_id)
    return changed


def nearest_ml_images(session: Session, data: bytes, limit=12, embed=embed_image, model_id=MODEL_ID, category=None):
    from .search import ranked_images
    return ranked_images(session, embed(data), limit, category, model_id)
