"""The same Alembic entry point is used by API startup and the update rehearsal."""
import argparse
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url


def migration_config():
    return Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))


def upgrade_database(engine):
    config = migration_config()
    with engine.connect() as connection:
        config.attributes['connection'] = connection
        command.upgrade(config, 'head')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-database', help='Only sadohod_verify_<32 hex digits> is accepted')
    args = parser.parse_args()
    from .config import DATABASE_URL
    url = make_url(DATABASE_URL)
    if args.verify_database:
        import re
        if url.get_backend_name() != 'postgresql' or not re.fullmatch(
                r'sadohod_verify_[0-9a-f]{32}', args.verify_database):
            parser.error('Expected an isolated PostgreSQL verification database')
        url = url.set(database=args.verify_database)
    engine = create_engine(url)
    try:
        upgrade_database(engine)
        print('Database migrations completed.')
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
