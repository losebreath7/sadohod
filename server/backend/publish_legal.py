"""Manually publish *approved* legal text atomically; drafts never publish by accident.

Example (future VPS, after reviewer approval):
 python tools/publish_legal.py --source approved/privacy.md --slug privacy \
  --version 2026-12-01 --effective-date 2026-12-01 \
  --reviewed-by 'approved person' --destination /secure/legal_published

The actual published source must be outside the repository drafts directory.
"""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sys

SLUGS = frozenset(("privacy", "buyer-terms", "seller-terms",
                   "content-rules", "data-consent", "data-deletion"))
BLOCKED_MARKERS = ("[УКАЗАТЬ", "[ПОДТВЕРД", "[ЗАПОЛНИ", "[СОГЛАСОВ", "[УТВЕРД",
                   "[ТРЕБУЕТ", "[ПРОВЕР", "[ПОДГОТОВ", "ПРОЕКТ —",
                   "ПРОЕКТ ФОРМУЛИРОВКИ", "НЕ ПУБЛИКОВАТЬ",
                   "YOUR_DOMAIN", "example.com", "example.org")


def prepare(text: str, slug: str, version: str, effective_date: str, reviewed_by: str) -> dict:
    if slug not in SLUGS:
        raise ValueError("Unknown legal slug")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}(?:\.\d+)?", version):
        raise ValueError("Invalid document version")
    if date.fromisoformat(effective_date) < date(2024, 1, 1):
        raise ValueError("Invalid effective date")
    if len(text) < 500 or len(text) > 200000:
        raise ValueError("Document length outside safe bounds")
    if any(marker.casefold() in text.casefold() for marker in BLOCKED_MARKERS):
        raise ValueError("Draft placeholders remain: publishing is blocked")
    if not reviewed_by.strip() or len(reviewed_by.strip()) < 3:
        raise ValueError("An approving reviewer must be identified")
    title = text.splitlines()[0].strip().removeprefix("#").strip()
    if not title or len(title) > 180:
        raise ValueError("Missing document heading")
    return dict(
        slug=slug, title=title, version=version,
        effective_date=effective_date, body=text,
        sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
        approved=True, reviewed_by=reviewed_by.strip(),
    )


def publish(payload: dict, destination: Path):
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True, mode=0o750)
    current = destination / (payload["slug"] + ".json")
    if current.is_symlink():
        raise ValueError("Refusing symlinked published document")
    if current.exists():
        old = json.loads(current.read_text("utf-8"))
        archive = destination / "archive" / payload["slug"]
        archive.mkdir(parents=True, exist_ok=True)
        old_target = archive / (old["version"] + ".json")
        if old_target.exists() and old_target.read_bytes() != current.read_bytes():
            raise ValueError("Conflicting archive revision")
        if not old_target.exists():
            shutil.copyfile(current, old_target)
    tmp = destination / (".pending-" + secrets.token_hex(12))
    try:
        with tmp.open("x", encoding="utf-8") as writer:
            json.dump(payload, writer, ensure_ascii=False, indent=2)
            writer.flush()
            os.fsync(writer.fileno())
        tmp.chmod(0o640)
        os.replace(tmp, current)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--slug", choices=sorted(SLUGS), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--effective-date", required=True)
    parser.add_argument("--reviewed-by", required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.source.resolve().is_relative_to(
            (Path(__file__).resolve().parents[2] / "docs" / "legal" / "drafts").resolve()
        ):
            raise ValueError("Cannot publish repository draft files directly")
        payload = prepare(args.source.read_text(encoding="utf-8"), args.slug,
                          args.version, args.effective_date, args.reviewed_by)
        publish(payload, args.destination)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        parser.exit(1, f"Legal publication refused: {exc}\n")
    print(f"Published {args.slug} version {args.version}; archive preserved")

if __name__ == "__main__":
    main()
