from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import DATABASE_URL

is_postgres = DATABASE_URL.startswith("postgresql")
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {})
SessionLocal = sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def init_db():
    from .migrations import upgrade_database
    upgrade_database(engine)


def get_db() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session
