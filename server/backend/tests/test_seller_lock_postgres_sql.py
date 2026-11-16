"""Regression for FOR UPDATE on Seller.pavilion joined eager relationship."""
import inspect

from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from backend.app.merchant import Seller, request_pavilion, resubmit_pavilion, decide_pavilion


def test_postgresql_lock_targets_sellers_not_nullable_pavilions():
    stmt = select(Seller).where(Seller.id == 'seller').with_for_update(of=Seller)
    sql = str(stmt.compile(dialect=postgresql.dialect(),
                           compile_kwargs={'literal_binds': True}))
    assert 'LEFT OUTER JOIN pavilions' in sql
    assert 'FOR UPDATE OF sellers' in sql
    for endpoint in (request_pavilion, resubmit_pavilion, decide_pavilion):
        src = inspect.getsource(endpoint)
        assert '.with_for_update(of=Seller)' in src, endpoint.__name__
        assert 'select(Seller).where(Seller.id ==' in src, endpoint.__name__
