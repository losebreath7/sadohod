"""Offline operator command for App Store / Play reviewer identities.

Run manually on the isolated target server, NEVER in CI with real credentials:
    PYTHONPATH=server python tools/manage_review_accounts.py provision \
      --email reviewer@example.org --platform apple --role buyer
    PYTHONPATH=server python tools/manage_review_accounts.py revoke \
      --email reviewer@example.org

No reusable code appears in the repository, environment, or command-line args.
"""
import argparse
from getpass import getpass
import re
import secrets
import time

from sqlalchemy import delete, select
from backend.app.account import Buyer, BuyerSession, LoginCode, ReviewAccess, hash_code
from backend.app.database import SessionLocal
from backend.app.merchant_models import ShopMembership, ShopRecord


def _email(raw):
    clean = raw.strip().lower()
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', clean) or len(clean) > 254:
        raise ValueError('Invalid reviewer email')
    return clean


def provision(db, email, platform, role, code, expires):
    email = _email(email)
    if platform not in ('apple', 'google') or role not in ('buyer', 'seller'):
        raise ValueError('Reviewer platform and role must be explicit')
    if not re.fullmatch(r'\d{6}', code) or expires <= time.time():
        raise ValueError('Invalid six-digit code or expiry')
    existing = db.get(ReviewAccess, email)
    if existing is None:
        buyer = db.scalar(select(Buyer).where(Buyer.email == email))
        if buyer is not None:
            raise ValueError('Email is already used: do not convert a regular customer')
        buyer = Buyer(id=secrets.token_hex(16), email=email, name='Store review')
        db.add(buyer)
        db.flush()
        db.add(ReviewAccess(email=email, buyer_id=buyer.id, code_digest=hash_code(code),
                            platform=platform, role=role, expires=expires,
                            enabled=True, failed_total=0))
    else:
        if existing.platform != platform or existing.role != role:
            raise ValueError('Reviewer identity is immutable; use a new email')
        existing.code_digest = hash_code(code)
        existing.expires = expires
        existing.enabled = True
        existing.failed_total = 0
        buyer = db.scalar(select(Buyer).where(Buyer.email == email))
        if buyer is None or buyer.id != existing.buyer_id:
            raise ValueError('Reviewer identity mismatch; manual investigation required')
    # Rotate all previously issued sessions, including those from older codes.
    db.execute(delete(BuyerSession).where(BuyerSession.buyer == buyer.id))
    db.execute(delete(LoginCode).where(LoginCode.email == email))
    db.commit()


def revoke(db, email):
    email = _email(email)
    row = db.get(ReviewAccess, email)
    if row is None:
        raise ValueError('No reviewer with this email')
    row.enabled = False
    buyer = db.scalar(select(Buyer).where(Buyer.email == email))
    if buyer is not None:
        db.execute(delete(BuyerSession).where(BuyerSession.buyer == buyer.id))
    db.execute(delete(LoginCode).where(LoginCode.email == email))
    db.commit()


def validate_seller(db, email):
    buyer = db.scalar(select(Buyer).where(Buyer.email == _email(email)))
    if buyer is None:
        return False
    from backend.app.merchant_models import PavilionClaim
    membership = db.scalar(select(ShopMembership).where(
        ShopMembership.buyer_id == buyer.id, ShopMembership.role == 'owner'))
    return bool(membership and db.get(ShopRecord, membership.seller_id) and
                db.scalar(select(PavilionClaim).where(
                    PavilionClaim.seller_id == membership.seller_id)))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='operation', required=True)
    create = sub.add_parser('provision')
    create.add_argument('--email', required=True)
    create.add_argument('--platform', choices=('apple', 'google'), required=True)
    create.add_argument('--role', choices=('buyer', 'seller'), required=True)
    create.add_argument('--days', type=int, default=45)
    disable = sub.add_parser('revoke')
    disable.add_argument('--email', required=True)
    check = sub.add_parser('check-seller')
    check.add_argument('--email', required=True)
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.operation == 'provision':
            if not 1 <= args.days <= 90:
                parser.error('--days must be 1–90')
            code = getpass('Private six-digit review code (never logged): ')
            provision(db, args.email, args.platform, args.role, code,
                      time.time() + args.days * 86400)
            print('Reviewer provisioned. Transfer private code through store review fields only.')
            if args.role == 'seller':
                print('IMPORTANT: seller shop and pavilion are NOT auto-approved.')
                print('Use the existing moderator workflow, then run check-seller.')
        elif args.operation == 'revoke':
            revoke(db, args.email)
            print('Reviewer disabled and all current sessions revoked.')
        else:
            print('Seller approved with a claimed pavilion:' if validate_seller(db, args.email)
                  else 'Seller NOT READY: approve shop and pavilion via moderator.')
            if not validate_seller(db, args.email):
                raise SystemExit(1)


if __name__ == '__main__':
    main()
