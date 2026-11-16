from alembic import context
from sqlalchemy import text

from backend.app.database import Base, engine
from backend.app import models, account, buyer_extras, merchant_models, buyer_reviews_v082, telegram_bridge, moderation_models  # noqa: F401


def include_object(obj, name, type_, reflected, compare_to):
    # These PostgreSQL-only tables have explicit DDL in the baseline revision.
    return not (type_ == 'table' and name in {
        'product_image_vectors', 'product_image_ml_vectors'})


def run(connection):
    with connection.begin():
        if connection.dialect.name == 'postgresql':
            connection.execute(text("SET LOCAL lock_timeout = '30s'"))
            connection.execute(text('SELECT pg_advisory_xact_lock(8247111508)'))
        elif connection.dialect.name == 'sqlite':
            # Python sqlite otherwise leaves DDL outside the SQLAlchemy transaction.
            connection.exec_driver_sql('BEGIN IMMEDIATE')
        else:
            raise RuntimeError('Only PostgreSQL and SQLite migrations are supported')
        context.configure(connection=connection, target_metadata=Base.metadata,
                          compare_type=True, include_object=include_object,
                          transactional_ddl=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    raise RuntimeError('Online connection required: existing schema must be validated')
shared = context.config.attributes.get('connection')
if shared is not None:
    run(shared)
else:
    with engine.connect() as connection:
        run(connection)
