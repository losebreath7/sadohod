from sqlalchemy import select, text, or_, bindparam
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm import Session

from .models import ProductImage, ProductDetails, Product, ImageMLEmbedding
from .merchant_models import ProductCategoryAssignment
from .image_features import descriptor_from_bytes, similarity


class SearchCapacityError(RuntimeError):
    pass


def ranked_images(session, query, limit, category=None, model_id=None, category_ids=None):
    """Rank eligible images before hydrating product cards."""
    if session.get_bind().dialect.name == 'postgresql':
        # Only these fixed table/column fragments enter SQL. Query data stays bound.
        table = 'product_image_ml_vectors' if model_id else 'product_image_vectors'
        model_filter = 'AND v.model_id = :model_id' if model_id else ''
        category_filter = ''
        if category and category_ids:
            category_filter = '''
                AND (p.category = :category OR EXISTS (
                    SELECT 1 FROM product_category_assignments a
                    WHERE a.product_id = p.id AND a.category_id IN :category_ids))
            '''
        elif category:
            category_filter = 'AND p.category = :category'
        distance = 'v.embedding <=> CAST(:vector AS vector)'
        params = {'vector': '[' + ','.join(f'{v:.9f}' for v in query) + ']',
                  'limit': limit, 'category': category, 'model_id': model_id}
        if category_ids:
            params['category_ids'] = category_ids
        session.execute(text("SET LOCAL statement_timeout = '2500ms'"))
        session.execute(text("SELECT set_config('hnsw.ef_search', :ef, true)"),
                        {'ef': str(max(40, min(limit, 1000)))})
        try:
            statement = text(f'''
                SELECT v.image_id, 1 - ({distance}) AS score
                FROM {table} v
                JOIN product_images i ON i.id = v.image_id
                JOIN products p ON p.id = i.product_id
                WHERE NOT EXISTS (SELECT 1 FROM product_details d
                                  WHERE d.product_id = p.id AND d.active = false)
                      {model_filter} {category_filter}
                ORDER BY {distance}
                LIMIT :limit
            ''')
            if category_ids:
                statement = statement.bindparams(bindparam('category_ids', expanding=True))
            rows = session.execute(statement, params).all()
        except DBAPIError as exc:
            if getattr(exc.orig, 'sqlstate', None) != '57014':
                raise
            session.rollback()
            raise SearchCapacityError('Поиск занят. Повторите запрос позже.') from exc
        return [(row.image_id, float(row.score)) for row in rows]

    vector = ImageMLEmbedding.embedding if model_id else ProductImage.descriptor
    stmt = select(ProductImage.id, vector).select_from(ProductImage).join(
        Product, Product.id == ProductImage.product_id).where(
            ~select(ProductDetails.product_id).where(
                ProductDetails.product_id == Product.id, ProductDetails.active.is_(False)).exists())
    if model_id:
        stmt = stmt.join(ImageMLEmbedding, ImageMLEmbedding.image_id == ProductImage.id).where(
            ImageMLEmbedding.model_id == model_id)
    if category:
        if category_ids:
            stmt = stmt.where(or_(Product.category == category,
                Product.id.in_(select(ProductCategoryAssignment.product_id).where(
                    ProductCategoryAssignment.category_id.in_(category_ids)))))
        else:
            stmt = stmt.where(Product.category == category)
    rows = session.execute(stmt.limit(2049)).all()
    if len(rows) > 2048:
        raise SearchCapacityError('Для поиска по такому каталогу запустите сервер с PostgreSQL.')
    scored = [(image_id, similarity(query, stored)) for image_id, stored in rows]
    return sorted(scored, key=lambda item: item[1], reverse=True)[:limit]


def nearest_images(session: Session, data: bytes, limit: int = 12, category=None, category_ids=None):
    return ranked_images(session, descriptor_from_bytes(data), limit, category, category_ids=category_ids)
