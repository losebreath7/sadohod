"""Compatibility entrypoint; implementation lives inside backend image."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from backend.manage_review_accounts import provision, revoke, validate_seller, main

if __name__ == '__main__':
    main()
