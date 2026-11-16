"""Local installation's persistent admin secret; not included in distributed archives."""
import os
import secrets
from pathlib import Path
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from .config import ROOT

bearer = HTTPBearer(auto_error=False)


def admin_token():
    configured = os.environ.get('ADMIN_TOKEN')
    if configured:
        return configured
    state = Path(os.environ.get('ADMIN_STATE_DIR', str(ROOT / 'state')))
    state.mkdir(parents=True, exist_ok=True)
    path = state / 'admin-token.txt'
    if not path.exists():
        try:
            with path.open('x') as f:
                f.write(secrets.token_urlsafe(32))
            path.chmod(0o600)
        except FileExistsError:
            pass
    return path.read_text().strip()


def require_admin(auth: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if auth is None or not secrets.compare_digest(auth.credentials, admin_token()):
        raise HTTPException(401, 'Неверный код доступа', headers={'WWW-Authenticate': 'Bearer'})
