"""Build buyer/seller store artifacts with the same stable production API origin.

This is a build helper, not a store submission or signing service. Run it on
the operator's trusted build machine with the usual signing credentials.
Do not substitute VPS IPs or an intermediate hosting provider's domain.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_API_URL = "https://api.sadohod.ru"
APPS = ("buyer_app", "seller_app")
PLATFORMS = {"android": "appbundle", "ios": "ipa"}


def build_command(app: str, platform: str) -> list[str]:
    if app not in APPS or platform not in PLATFORMS:
        raise ValueError("Invalid app/platform combination")
    return [
        "flutter", "build", PLATFORMS[platform], "--release",
        f"--dart-define=API_BASE_URL={PUBLIC_API_URL}",
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, choices=APPS)
    parser.add_argument("--platform", required=True, choices=tuple(PLATFORMS))
    args = parser.parse_args()

    print(f"Building {args.app} for {args.platform}: API={PUBLIC_API_URL}", flush=True)
    subprocess.run(["flutter", "pub", "get"], cwd=ROOT / args.app, check=True)
    subprocess.run(build_command(args.app, args.platform), cwd=ROOT / args.app, check=True)


if __name__ == "__main__":
    main()
