"""Upgrade only a disposable restored database; compare every existing row."""
import argparse
import hashlib
import re

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url
from .migrations import upgrade_database


def snapshot(engine):
    result = {}
    with engine.connect() as connection:
        quote = connection.dialect.identifier_preparer.quote
        for table in sorted(inspect(connection).get_table_names()):
            if table == 'alembic_version':
                continue
            digest = hashlib.sha256()
            count = 0
            # Hash within PostgreSQL: attachments are never copied to the client.
            rows = connection.execution_options(stream_results=True).execute(text(
                f'SELECT md5(row_to_json(t)::text) AS h FROM {quote(table)} t ORDER BY h'))
            for row in rows:
                digest.update(row[0].encode('ascii'))
                count += 1
            result[table] = (count, digest.hexdigest())
    return result


def rehearse(engine):
    if engine.dialect.name != 'postgresql' or not re.fullmatch(
            r'sadohod_verify_[0-9a-f]{32}', engine.url.database or ''):
        raise RuntimeError('Rehearsal is allowed only on an isolated verification database')
    before = snapshot(engine)
    upgrade_database(engine)
    after = snapshot(engine)
    if any(after.get(table) != values for table, values in before.items()):
        raise RuntimeError('Existing data changed during migration rehearsal')
    upgrade_database(engine)
    if snapshot(engine) != after:
        raise RuntimeError('Repeated migration changed data')
    print(f'Migration rehearsal passed: {len(before)} existing tables preserved.')


def main():
    from .config import DATABASE_URL
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-database', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'sadohod_verify_[0-9a-f]{32}', args.verify_database):
        parser.error('Invalid verification database name')
    url = make_url(DATABASE_URL)
    if url.get_backend_name() != 'postgresql':
        parser.error('PostgreSQL is required')
    engine = create_engine(url.set(database=args.verify_database))
    try:
        rehearse(engine)
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
