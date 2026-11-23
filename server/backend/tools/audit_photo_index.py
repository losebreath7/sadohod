"""Read-only index coverage audit for current OpenCLIP model.

Run from server/: python -m backend.tools.audit_photo_index
Use on a staging copy of the database, not the production write path.
"""
import json
from sqlalchemy import func, select, text
from backend.app.database import SessionLocal
from backend.app.models import ImageMLEmbedding, ProductImage
from backend.app.ml_clip import MODEL_ID


def index_coverage(session, model_id=MODEL_ID):
    total = session.scalar(select(func.count()).select_from(ProductImage)) or 0
    embedded = session.scalar(select(func.count()).select_from(
        ImageMLEmbedding).where(ImageMLEmbedding.model_id == model_id)) or 0
    missing = session.scalar(select(func.count()).select_from(ProductImage).where(
        ~select(ImageMLEmbedding.image_id).where(
            ImageMLEmbedding.image_id == ProductImage.id,
            ImageMLEmbedding.model_id == model_id).exists())) or 0
    result = {
        "model": model_id,
        "catalog_images": total,
        "portable_embeddings": embedded,
        "missing_embeddings": missing,
        "coverage": (total - missing) / total if total else None,
    }
    if session.bind.dialect.name == "postgresql":
        result["pgvector_mirror"] = session.execute(text("""
            SELECT count(*) FROM product_image_ml_vectors
            WHERE model_id = :model
        """), {"model": model_id}).scalar_one()
        result["missing_pgvector_vectors"] = session.execute(text("""
            SELECT count(*) FROM product_images i
            WHERE NOT EXISTS (
                SELECT 1 FROM product_image_ml_vectors v
                WHERE v.image_id = i.id AND v.model_id = :model)
        """), {"model": model_id}).scalar_one()
        result["orphan_pgvector_vectors"] = session.execute(text("""
            SELECT count(*) FROM product_image_ml_vectors v
            WHERE v.model_id = :model AND NOT EXISTS (
                SELECT 1 FROM product_images i WHERE i.id = v.image_id)
        """), {"model": model_id}).scalar_one()
    return result


def main():
    with SessionLocal() as session:
        result = index_coverage(session)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["missing_embeddings"] or result.get("missing_pgvector_vectors", 0):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
