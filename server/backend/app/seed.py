from pathlib import Path

from sqlalchemy import select, text
from sqlalchemy.orm import Session

from .config import MEDIA
from .database import is_postgres
from .image_features import descriptor_from_bytes
from .models import Pavilion, Seller, Product, Offer, OfferSaleModes, ProductImage

SELLERS = [
    ("s01", "Контур 01", "А-14", "Сектор А · линия 2"),
    ("s02", "Студия 08", "Б-08", "Сектор Б · линия 1"),
    ("s03", "Форма 17", "В-17", "Сектор В · линия 4"),
    ("s04", "Линия 05", "Г-05", "Сектор Г · линия 3"),
]
PRODUCTS = [
    ("p01", "Укороченная куртка", "Верхняя одежда", 3890, "s01", "Прямой силуэт, высокий воротник и молния по центру.", "Графит"),
    ("p02", "Сумка с короткими ручками", "Сумки", 2450, "s02", "Компактная сумка с основным отделением и внутренним карманом.", "Шоколад"),
    ("p03", "Футболка свободного кроя", "Одежда", 990, "s03", "Свободная посадка и плотный круглый ворот.", "Молочный"),
    ("p04", "Кроссовки на платформе", "Обувь", 2990, "s04", "Объёмная подошва, шнуровка, мягкая посадка.", "Песочный"),
    ("p05", "Худи с карманом", "Одежда", 2690, "s02", "Мягкая модель свободного кроя с капюшоном.", "Серый"),
    ("p06", "Прямые брюки", "Одежда", 1990, "s01", "Умеренно широкая посадка, прямые штанины.", "Тёмно-синий"),
    ("p07", "Платье миди", "Платья", 3190, "s03", "Мягко приталенная форма и свободный низ.", "Терракотовый"),
    ("p08", "Куртка с воротником", "Верхняя одежда", 4290, "s04", "Минималистичная верхняя одежда на каждый день.", "Оливковый"),
    ("p09", "Мини-сумка", "Сумки", 1890, "s02", "Небольшой размер, жёсткая форма и короткие ручки.", "Чёрный"),
    ("p10", "Кеды низкие", "Обувь", 2190, "s03", "Универсальная модель с контрастной подошвой.", "Графит"),
    ("p11", "Футболка базовая", "Одежда", 1190, "s01", "Прямой крой, базовая посадка.", "Хаки"),
    ("p12", "Брюки широкие", "Одежда", 2590, "s04", "Свободный прямой силуэт.", "Кофейный"),
]


def seed_demo(session: Session, media: Path = MEDIA) -> None:
    if session.scalar(select(Product.id).limit(1)) is not None:
        return
    for sid, name, code, zone in SELLERS:
        session.add(Pavilion(id=sid, code=code, zone=zone))
        session.add(Seller(id=sid, name=name, pavilion_id=sid))
    session.flush()
    for pid, title, cat, price, sid, desc, color in PRODUCTS:
        session.add(Product(id=pid, title=title, category=cat, description=desc, colors=[color], is_demo=True))
        session.add(Offer(id=f"o-{pid}", product_id=pid, seller_id=sid, pavilion_id=sid, price=price,
                          modes=OfferSaleModes(wholesale=pid in {'p01', 'p03', 'p04', 'p05', 'p08', 'p09'},
                                              retail=pid in {'p02', 'p03', 'p06', 'p07', 'p10', 'p11', 'p12'})))
        img_path = media / f"{pid}.jpg"
        descriptor = descriptor_from_bytes(img_path.read_bytes())
        session.add(ProductImage(id=f"i-{pid}", product_id=pid, filename=f"{pid}.jpg", descriptor=descriptor))
        session.flush()
        if is_postgres and session.bind.dialect.name == "postgresql":
            vector = "[" + ",".join(f"{v:.9f}" for v in descriptor) + "]"
            session.execute(text("INSERT INTO product_image_vectors(image_id, embedding) VALUES (:id, CAST(:v AS vector))"), {"id": f"i-{pid}", "v": vector})
    session.commit()


def ensure_legacy_demo_sale_modes(session: Session) -> None:
    """Add illustrative modes only for 12 known fictional seed offers.

    This does not change actual/custom sellers' offers, existing mode settings,
    or any of the imported photo dataset offers with unknown terms.
    """
    from sqlalchemy.orm import selectinload
    modes_for_demo = {
        'p01': (True, False), 'p02': (False, True), 'p03': (True, True),
        'p04': (True, False), 'p05': (True, False), 'p06': (False, True),
        'p07': (False, True), 'p08': (True, False), 'p09': (True, False),
        'p10': (False, True), 'p11': (False, True), 'p12': (False, True),
    }
    statement = select(Offer).options(selectinload(Offer.product), selectinload(Offer.modes))        .where(Offer.id.in_([f'o-{p}' for p in modes_for_demo]))
    changed = False
    for offer in session.scalars(statement):
        pid = offer.product_id
        if not offer.product.is_demo or offer.modes is not None:
            continue
        wholesale, retail = modes_for_demo[pid]
        offer.modes = OfferSaleModes(wholesale=wholesale, retail=retail)
        changed = True
    if changed:
        session.commit()


def ensure_demo_category_links(session: Session) -> int:
    """Backfill only unlinked demo records seeded after the Alembic migration.

    Real seller products are managed by merchant category inference; this routine
    neither overwrites existing links nor changes product publication/status.
    """
    from .merchant_models import ProductCategoryAssignment
    from .catalog_taxonomy import LEGACY, path_ids, resolve_leaf
    pending = session.scalars(select(Product).where(
        Product.is_demo.is_(True),
        ~Product.id.in_(select(ProductCategoryAssignment.product_id)))).all()
    count = 0
    for product in pending:
        leaf = resolve_leaf(product.title)
        legacy = LEGACY.get(product.category)
        if legacy and (leaf is None or
                       path_ids(legacy)[0] != path_ids(leaf)[0]):
            leaf = legacy
        if leaf:
            session.add(ProductCategoryAssignment(
                product_id=product.id, category_id=leaf, source='demo'))
            count += 1
    if count:
        session.commit()
    return count
