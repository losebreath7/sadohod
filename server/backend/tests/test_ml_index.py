"""ML integration contract without a heavyweight pretrained checkpoint in CI.

This deliberately checks indexing, model IDs, and retrieval wiring using a
predictable 512D test encoder. It does NOT validate real OpenCLIP accuracy.
"""
from io import BytesIO
from PIL import Image, ImageEnhance
import numpy as np
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.config import MEDIA
from backend.app.database import Base
from backend.app.image_features import descriptor_from_bytes
from backend.app.ml_index import index_catalog, nearest_ml_images
from backend.app.models import ImageMLEmbedding, Product, ProductImage
from backend.app.seed import seed_demo


def stub_image_embedding(data: bytes):
    # 96D deterministic feature zero-padded to 512D, for integration only.
    return descriptor_from_bytes(data) + [0.0] * 416


def test_ml_index_is_versioned_idempotent_and_retrievable():
    engine = create_engine('sqlite://', poolclass=StaticPool, connect_args={'check_same_thread': False})
    Base.metadata.create_all(engine)
    sess = sessionmaker(engine, expire_on_commit=False)()
    try:
        seed_demo(sess)
        changed = index_catalog(sess, embed=stub_image_embedding, model_id='test-v1')
        assert changed == 12
        assert index_catalog(sess, embed=stub_image_embedding, model_id='test-v1') == 0
        assert index_catalog(sess, embed=stub_image_embedding, model_id='test-v2') == 12
        assert len(sess.scalars(select(ImageMLEmbedding)).all()) == 24
        nearest = nearest_ml_images(sess, (MEDIA / 'p02.jpg').read_bytes(), embed=stub_image_embedding, model_id='test-v1')
        assert nearest[0][0] == 'i-p02'
        assert abs(nearest[0][1] - 1) < 0.0001
        assert len(nearest_ml_images(sess, (MEDIA / 'p02.jpg').read_bytes(), embed=stub_image_embedding, model_id='unindexed')) == 0
        # A draft/paused listing may retain indexed photos; those must never
        # reach a buyer through similarity search without an active offer.
        sess.add(Product(id='unpublished', title='Unpublished', category='Сумки',
                         description='', colors=[], is_demo=False))
        sess.add(ProductImage(id='i-unpublished', product_id='unpublished',
                              filename='p02.jpg', descriptor=descriptor_from_bytes(
                                  (MEDIA / 'p02.jpg').read_bytes())))
        sess.commit()
        assert index_catalog(sess, embed=stub_image_embedding, model_id='test-v1') == 1
        results = nearest_ml_images(
            sess, (MEDIA / 'p02.jpg').read_bytes(),
            embed=stub_image_embedding, model_id='test-v1', limit=50)
        assert 'i-unpublished' not in [image_id for image_id, _ in results]

    finally:
        sess.close()
        engine.dispose()
