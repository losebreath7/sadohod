"""Upgrade only a disposable restored database; compare every existing row."""
import argparse
import hashlib
import re

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url
from .migrations import upgrade_database


def snapshot(engine, column_scope=None):
    """Hash original columns even when an additive migration adds new ones.

    The old rehearsal compared row_to_json(table) wholesale, which incorrectly
    treated a new nullable/defaulted column as corruption of existing rows.
    Keep hashing inside PostgreSQL (private attachments never leave the DB).
    """
    result = {}
    with engine.connect() as connection:
        inspector = inspect(connection)
        quote = connection.dialect.identifier_preparer.quote
        for table in sorted(inspector.get_table_names()):
            if table == 'alembic_version':
                continue
            if column_scope is not None and table not in column_scope:
                continue
            columns = (column_scope[table] if column_scope is not None else
                       tuple(c['name'] for c in inspector.get_columns(table)))
            projection = ', '.join(quote(col) for col in columns)
            digest = hashlib.sha256()
            count = 0
            rows = connection.execution_options(stream_results=True).execute(text(
                f'SELECT md5(row_to_json(t)::text) AS h '
                f'FROM (SELECT {projection} FROM {quote(table)}) t ORDER BY h'))
            for row in rows:
                digest.update(row[0].encode('ascii'))
                count += 1
            result[table] = (columns, count, digest.hexdigest())
    return result


def rehearse(engine):
    if engine.dialect.name != 'postgresql' or not re.fullmatch(
            r'sadohod_verify_[0-9a-f]{32}', engine.url.database or ''):
        raise RuntimeError('Rehearsal is allowed only on an isolated verification database')
    before = snapshot(engine)
    upgrade_database(engine)
    before_columns = {table: data[0] for table, data in before.items()}
    after = snapshot(engine, before_columns)
    if after != before:
        raise RuntimeError('Existing data changed during migration rehearsal')
    upgraded_snapshot = snapshot(engine)
    upgrade_database(engine)
    if snapshot(engine) != upgraded_snapshot:
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
