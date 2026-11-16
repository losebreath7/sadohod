"""Additive demo migration: never delete or overwrite an existing product."""
import json
from sqlalchemy import text
from .config import ROOT, MEDIA
from .models import Product, ProductImage, Offer, Seller, Pavilion
from .seed import SELLERS
from .image_features import descriptor_from_bytes


def seed_photos(session):
    manifest = ROOT / 'demo_data/photo_catalog.json'
    if not manifest.exists():
        raise RuntimeError('Missing demo_data/photo_catalog.json; use the complete v0.4 archive')
    rows = json.loads(manifest.read_text(encoding='utf-8'))
    for sid, name, code, zone in SELLERS:
        if session.get(Pavilion, sid) is None:
            session.add(Pavilion(id=sid, code=code, zone=zone))
        if session.get(Seller, sid) is None:
            session.add(Seller(id=sid, name=name, pavilion_id=sid))
    session.flush()
    count = 0
    for i, row in enumerate(r for r in rows if r['split'] == 'catalog'):
        pid = 'photo-' + row['image'].replace('-', '')[:24]
        if session.get(Product, pid) is not None:
            continue
        sid = SELLERS[i % len(SELLERS)][0]
        descriptor = descriptor_from_bytes((MEDIA / row['filename']).read_bytes())
        session.add(Product(id=pid, title=f"{row['category']} · образец {i+1:03d}",
                            category=row['category'], description='Реальная фотография из Clothing Dataset. Учебная карточка: продавец, цена и павильон вымышлены. Наличие на Садоводе не подтверждено.', colors=[], is_demo=True))
        session.flush()
        session.add(Offer(id='o-'+pid, product_id=pid, seller_id=sid, pavilion_id=sid, price=990+(i%12)*250))
        session.add(ProductImage(id='i-'+pid, product_id=pid, filename=row['filename'], descriptor=descriptor))
        session.flush()
        if session.bind.dialect.name == 'postgresql':
            vector = '[' + ','.join(f'{v:.9f}' for v in descriptor) + ']'
            session.execute(text('INSERT INTO product_image_vectors(image_id, embedding) VALUES (:id, CAST(:v AS vector))'), {'id':'i-'+pid, 'v':vector})
        count += 1
    session.commit()
    return count
