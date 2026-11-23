"""Coverage checks use a disposable SQLite database; no production data."""
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from backend.app.database import Base
from backend.app.models import ImageMLEmbedding, Product, ProductImage
from backend.tools.audit_photo_index import index_coverage


def test_index_coverage_tracks_missing_and_present_vectors():
    engine = create_engine(
        "sqlite://", poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine, tables=[
        Product.__table__, ProductImage.__table__, ImageMLEmbedding.__table__,
    ])
    try:
        with Session(engine) as session:
            session.add(Product(
                id="p", title="test", category="test", description="",
                colors=[], is_demo=False,
            ))
            session.flush()
            for image_id in ("one", "two"):
                session.add(ProductImage(
                    id=image_id, product_id="p", filename=image_id + ".jpg",
                    descriptor=[0.0] * 96,
                ))
            session.add(ImageMLEmbedding(
                image_id="one", model_id="test-model",
                embedding=[0.0] * 512,
            ))
            session.commit()
            report = index_coverage(session, model_id="test-model")
            assert report["catalog_images"] == 2
            assert report["portable_embeddings"] == 1
            assert report["missing_embeddings"] == 1
            assert report["coverage"] == .5
            assert "pgvector_mirror" not in report
    finally:
        engine.dispose()
