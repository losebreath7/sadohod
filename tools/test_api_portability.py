"""Offline checks: provider-independent API connection and store release address.

CI runs this without live DNS, a VPS, credentials or changing client behavior.
"""
from pathlib import Path
import re

from build_store_release import APPS, PLATFORMS, PUBLIC_API_URL, build_command

ROOT = Path(__file__).resolve().parents[1]
LITERAL_IP_URL = re.compile(r"https?://(?:(?:\d{1,3}\.){3}\d{1,3}|\[[0-9a-fA-F:]+\])")


def run_checks() -> None:
    assert PUBLIC_API_URL == "https://api.sadohod.ru"
    shared = (ROOT / "shared/flutter_core/lib/api_base_url.dart").read_text()
    assert "kReleaseMode && !kIsWeb" in shared
    assert "isPublicHttpsApiEndpoint(value)" in shared
    assert "RegExp(r'^[0-9.]+$')" in shared
    assert "host.contains(':')" in shared

    clients = {
        "buyer_app": ROOT / "buyer_app/lib/data/api.dart",
        "seller_app": ROOT / "seller_app/lib/api.dart",
    }
    for app, file in clients.items():
        text = file.read_text()
        assert "String.fromEnvironment('API_BASE_URL')" in text, app
        assert "sadohodApiBaseUrl(" in text, app

        # No published app should have an IPv4/IPv6 literal endpoint hidden
        # in a feature screen. Development loopback stays ONLY in shared helper.
        for dart in (ROOT / app / "lib").rglob("*.dart"):
            source = dart.read_text()
            match = LITERAL_IP_URL.search(source)
            assert not match, (dart.relative_to(ROOT), match.group(0))

    buyer_photos = (ROOT / "buyer_app/lib/data/catalog.dart").read_text()
    assert "rawImage.startsWith('/')" in buyer_photos
    assert "'$baseUrl$rawImage'" in buyer_photos
    server_products = (ROOT / "server/backend/app/api.py").read_text()
    assert 'f"/media/products/' in server_products

    compose = (ROOT / "docker-compose.production.yml").read_text()
    caddy = (ROOT / "https/Caddyfile.production").read_text()
    assert "API_DOMAIN: " in compose and "api:8000" in caddy
    assert "{$API_DOMAIN}" in caddy
    assert "\n    ports:" not in compose.split("\n  api:", 1)[1].split("\n  https:", 1)[0]

    for app in APPS:
        for platform, artifact in PLATFORMS.items():
            assert build_command(app, platform) == [
                "flutter", "build", artifact, "--release",
                "--dart-define=API_BASE_URL=https://api.sadohod.ru",
            ]
    for app, platform in (("unknown_app", "android"), ("buyer_app", "web")):
        try:
            build_command(app, platform)
        except ValueError:
            pass
        else:
            raise AssertionError((app, platform, "unexpectedly allowed"))


if __name__ == "__main__":
    run_checks()
    print("API portability / store build endpoint checks: OK")
