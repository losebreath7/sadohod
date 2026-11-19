"""Offline production preflight. No Docker connection, no network or secrets printed.

Usage: python tools/check_production_env.py --env .env.production
"""
import argparse
import ipaddress
from pathlib import Path
import re
from urllib.parse import urlsplit

BAD = ("example.", "change_me", "replace", "password", "localhost", "127.0.0.1", "10.0.2.2", ".invalid", ".test", ".localhost", ".local")


def parse_env(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise ValueError("Production env file is missing")
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("Invalid env file line")
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", key) or key in values:
            raise ValueError("Invalid or duplicate environment variable")
        values[key] = value.strip('"').strip("'")
    return values


def real_domain(value: str) -> bool:
    if not value or any(x in value.lower() for x in BAD):
        return False
    if not re.fullmatch(r"(?=.{4,253}$)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value):
        return False
    try:
        ipaddress.ip_address(value)
        return False
    except ValueError:
        return True


def validate(values: dict[str, str]) -> None:
    errors: list[str] = []

    def require(ok: bool, label: str) -> None:
        if not ok:
            errors.append(label)

    require(values.get("SADOHOD_ENV") == "production", "SADOHOD_ENV must be production")
    require(values.get("DEMO_SEED") == "0", "DEMO_SEED must equal 0")
    require(real_domain(values.get("API_DOMAIN", "")), "API_DOMAIN must be a real DNS hostname")
    require(bool(re.fullmatch(r"[A-Za-z0-9_-]{32,128}", values.get("POSTGRES_PASSWORD", ""))),
            "POSTGRES_PASSWORD needs 32+ URL-safe random characters")
    require(bool(re.fullmatch(r"[A-Za-z0-9_-]{32,256}", values.get("ADMIN_TOKEN", ""))),
            "ADMIN_TOKEN needs 32+ random characters")
    require(real_domain(values.get("SMTP_HOST", "")), "SMTP_HOST is missing or placeholder")
    require(values.get("SMTP_PORT") in ("465", "587"), "SMTP_PORT must be 465 or 587")
    require(bool(re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", values.get("SMTP_FROM", "")))
            and not any(x in values.get("SMTP_FROM", "").lower() for x in BAD),
            "SMTP_FROM must be a real sender")
    require(bool(values.get("SMTP_USER")) and
            not any(x in values.get("SMTP_USER", "").lower() for x in BAD),
            "SMTP_USER required")
    require(len(values.get("SMTP_PASSWORD", "")) >= 12 and
            not any(x in values.get("SMTP_PASSWORD", "").lower() for x in BAD),
            "SMTP_PASSWORD required (use an SMTP app password)")
    require(not values.get("SADOHOD_BIND"), "SADOHOD_BIND is forbidden")
    require(values.get("USE_LOCAL_DEMO", "").lower() not in ("1", "true"),
            "Demo clients are forbidden")
    require(not values.get("DATABASE_URL"), "DATABASE_URL is derived by production Compose")
    require(bool(values.get("PHOTO_SEARCH_MIN_SCORE", "0.20")) and
            _valid_score(values.get("PHOTO_SEARCH_MIN_SCORE", "0.20")), "Invalid ML score")
    require(bool(values.get("TELEGRAM_BOT_TOKEN")) == bool(values.get("TELEGRAM_GROUP_ID")),
            "Telegram bot and group must be configured together")
    for origin in values.get("ALLOWED_ORIGINS", "").split(","):
        if not origin.strip():
            continue
        try:
            uri = urlsplit(origin.strip())
            ok = (uri.scheme == "https" and real_domain(uri.hostname or "") and
                  not uri.username and not uri.password and not uri.path and
                  not uri.query and not uri.fragment)
        except ValueError:
            ok = False
        require(ok, "ALLOWED_ORIGINS must contain only exact public HTTPS origins")
    if errors:
        raise ValueError("; ".join(sorted(set(errors))))


def _valid_score(text: str) -> bool:
    try:
        value = float(text)
        return -1.0 <= value <= 1.0
    except ValueError:
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        validate(parse_env(arguments.env))
    except ValueError as exc:
        parser.exit(1, f"Production preflight failed: {exc}\n")
    print("Production preflight: OK (no secrets shown)")
