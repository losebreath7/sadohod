"""Public versioned legal content. Never serve source drafts or invented consents.

Only operator-published JSON files from an isolated writable directory are read.
The same data backs the public HTML pages and both mobile clients.
"""
import hashlib
import html
import json
import os
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse

router = APIRouter()
LEGAL_SLUGS = frozenset((
    "privacy", "buyer-terms", "seller-terms",
    "content-rules", "data-consent", "data-deletion",
))


def published_dir() -> Path:
    return Path(os.environ.get("SADOHOD_LEGAL_DIR", "/app/legal_published"))


def read_document(slug: str) -> dict:
    if slug not in LEGAL_SLUGS:
        raise HTTPException(404, "Unknown legal document")
    path = published_dir() / (slug + ".json")
    if not path.is_file() or path.is_symlink():
        raise HTTPException(503, "Legal document not published")
    try:
        if path.stat().st_size > 256000:
            raise ValueError("Document exceeds size limit")
        payload = json.loads(path.read_text(encoding="utf-8"))
        if (
            payload.get("slug") != slug
            or payload.get("approved") is not True
            or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}(?:\.[0-9]+)?", payload["version"])
            or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", payload["effective_date"])
            or len(payload["body"]) < 150
            or hashlib.sha256(payload["body"].encode()).hexdigest() != payload["sha256"]
        ):
            raise ValueError("Invalid document metadata")
        return {key: payload[key] for key in (
            "slug", "title", "version", "effective_date", "body", "sha256"
        )}
    except (ValueError, KeyError, TypeError, UnicodeError):
        raise HTTPException(503, "Legal document is not available") from None


@router.get("/api/v1/legal/{slug}")
def document_json(slug: str):
    response = JSONResponse(read_document(slug))
    response.headers["Cache-Control"] = "no-cache, must-revalidate"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@router.get("/legal/{slug}", response_class=HTMLResponse)
def document_html(slug: str):
    payload = read_document(slug)
    title = html.escape(payload["title"])
    body = html.escape(payload["body"])
    version = html.escape(payload["version"])
    effective = html.escape(payload["effective_date"])
    page = f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — Садоход</title>
<style>
body {{max-width:820px;margin:0 auto;padding:32px 20px;font:15px/1.65 system-ui,sans-serif;color:#222}}
main {{white-space:pre-wrap;overflow-wrap:anywhere}}
footer {{margin-top:28px;color:#666}}
</style></head><body><h1>{title}</h1><main>{body}</main>
<footer>Редакция {version} · действует с {effective}</footer></body></html>"""
    response = HTMLResponse(page)
    response.headers["Cache-Control"] = "no-cache, must-revalidate"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
    return response
