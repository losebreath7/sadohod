"""Versioned embeddings. Existing 96D table and old PostgreSQL volume are preserved."""
import math
from sqlalchemy import text
from sqlalchemy.orm import Session
from .config import MEDIA
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM, embed_image

INDEX_BATCH_SIZE = 64


def index_catalog(session: Session, embed=embed_image, media=MEDIA, model_id=MODEL_ID):
    changed = 0
    while True:
        processed, embedded = index_catalog_batch(session, embed, media, model_id)
        changed += embedded
        if processed < INDEX_BATCH_SIZE:
            return changed


def index_catalog_batch(session, embed=embed_image, media=MEDIA, model_id=MODEL_ID, batch_size=INDEX_BATCH_SIZE):
    postgres = session.get_bind().dialect.name == 'postgresql'
    mirror_join = ''
    missing_mirror = ''
    if postgres:
        # Serialize startup indexers, including concurrent API worker starts.
        session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
                        {'key': 'photo-index:' + model_id})
        mirror_join = """LEFT JOIN product_image_ml_vectors v
            ON v.image_id = i.id AND v.model_id = :model"""
        missing_mirror = 'OR v.image_id IS NULL'

    session.flush()
    candidates = session.execute(text(f"""
        SELECT i.id, i.filename, e.image_id AS indexed_id,
               json_array_length(e.embedding) AS dimensions
        FROM product_images i
        LEFT JOIN image_ml_embeddings e ON e.image_id = i.id AND e.model_id = :model
        {mirror_join}
        WHERE e.image_id IS NULL OR json_array_length(e.embedding) <> :dim
              {missing_mirror}
        ORDER BY i.id LIMIT :batch_size
    """), {'model': model_id, 'dim': DIM, 'batch_size': batch_size}).all()
    changed = 0
    for image_id, filename, indexed_id, dimensions in candidates:
        if indexed_id is None:
            vector = embed((media / filename).read_bytes())
            if len(vector) != DIM or not all(math.isfinite(float(v)) for v in vector):
                raise RuntimeError('ML-вектор должен содержать 512 конечных чисел')
            session.add(ImageMLEmbedding(image_id=image_id, model_id=model_id, embedding=vector))
            changed += 1
        elif dimensions != DIM:
            raise RuntimeError('В базе некорректная размерность ML-вектора; нужна переиндексация')
        else:
            vector = session.get(ImageMLEmbedding, (image_id, model_id)).embedding
        if postgres:
            literal = '[' + ','.join(f'{v:.9f}' for v in vector) + ']'
            session.execute(text("""
                INSERT INTO product_image_ml_vectors (image_id, model_id, embedding)
                VALUES (:image_id, :model_id, CAST(:embedding AS vector))
                ON CONFLICT (image_id, model_id) DO UPDATE SET embedding = EXCLUDED.embedding
            """), {'image_id': image_id, 'model_id': model_id, 'embedding': literal})
    session.commit()
    return len(candidates), changed


def nearest_ml_images(session: Session, data: bytes, limit=12, embed=embed_image, model_id=MODEL_ID, category=None, category_ids=None):
    from .search import ranked_images
    return ranked_images(session, embed(data), limit, category, model_id,
                         category_ids=category_ids)
