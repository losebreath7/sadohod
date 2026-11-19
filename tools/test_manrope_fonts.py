#!/usr/bin/env python3
"""Regression gate for the exact user-approved Manrope font binaries."""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
FONTS = ROOT / "shared/flutter_core/assets/fonts"
EXPECTED = {"ExtraLight":"f582541204bdc68b51de3c2fe50b99ec20c3c0319692177cbf427719929aa916","Light":"d846bf4ff042a2d9ff27109aeaf64228c94d88ab6cf7ba4ac6bacff018e73f34","Regular":"6383bd9f81e56d61139884d8e42cb7b2146a11dde4efde55c8bff1e4c2c0bbe8","Medium":"88d3f8ef004b53483a202772d09acaab17ca99dd41905d9b4ab07ac635632378","SemiBold":"abbefa1f58c7355b663c19f29ffe4cd7fc8c93a9e5f8b68f08d1e9ba2bc4ba0d","Bold":"4aed5d180a4f41ed21f07e678486f889bb40eb0ddf5f473769b6302f507d1e36","ExtraBold":"5be6d9b21d23981ab520f0bfc7800c434c9d093467ef24b85b16877e7709b03b"}
WEIGHTS = {"ExtraLight": 200, "Light": 300, "Regular": 400,
           "Medium": 500, "SemiBold": 600, "Bold": 700, "ExtraBold": 800}
errors: list[str] = []

manifest = (ROOT / "shared/flutter_core/pubspec.yaml").read_text(encoding="utf-8")
design_tokens = (ROOT / "shared/flutter_core/lib/design_tokens.dart").read_text(encoding="utf-8")
for weight, digest in EXPECTED.items():
    filename = "Manrope-" + weight + ".ttf"
    path = FONTS / filename
    if not path.is_file():
        errors.append(f"Missing approved font asset: {path}")
        continue
    real = hashlib.sha256(path.read_bytes()).hexdigest()
    if real != digest:
        errors.append(f"Incorrect Manrope {weight}: {real} != {digest}")
    declaration = re.compile(
        r"- asset: assets/fonts/" + re.escape(filename)
        + r"\s+weight:\s*" + str(WEIGHTS[weight]) + r"\b"
    )
    if not declaration.search(manifest):
        errors.append(f"Incorrect font family/weight declaration: {filename}")

if not re.search(r"family:\s*Manrope\b", manifest):
    errors.append("Missing shared Manrope family declaration")
if "packages/sadohod_shared_core/Manrope" not in design_tokens:
    errors.append("Shared SadohodFont.family does not refer to bundled Manrope")
if not re.search(r"static const fallback = <String>\[\];", design_tokens):
    errors.append("Unexpected fallback font families: explicit fallback must be empty")

for app in ("buyer_app", "seller_app"):
    dart_dir = ROOT / app / "lib"
    for path in dart_dir.rglob("*.dart"):
        content = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\bfontFamily\s*:\s*(['\"])(.*?)\1", content):
            if match.group(2) not in ("Manrope", "packages/sadohod_shared_core/Manrope"):
                errors.append(f"Unexpected font family in {path.relative_to(ROOT)}: {match.group(2)}")
        if re.search(r"\b(?:Arial|Roboto)\b", content):
            errors.append(f"Fallback font reference in {path.relative_to(ROOT)}")
    if not (ROOT / app / "pubspec.yaml").is_file():
        errors.append(f"Missing {app} Flutter manifest")

# Optional post-build check: validate actual font files packaged for the browser.
# This guards against a valid source asset being silently replaced during Flutter build.
parser = argparse.ArgumentParser()
parser.add_argument("--web-build", type=pathlib.Path)
args = parser.parse_args()
if args.web_build is not None:
    web_root = args.web_build.resolve()
    assets_root = web_root / "assets"
    for weight, digest in EXPECTED.items():
        filename = "Manrope-" + weight + ".ttf"
        matches = list(assets_root.rglob(filename)) if assets_root.is_dir() else []
        if not matches:
            errors.append(f"Flutter Web build missing {filename}: {web_root}")
        for path in matches:
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual != digest:
                errors.append(f"Flutter Web packaged a SUBSTITUTE font at {path}: {actual}")
    manifests = list(assets_root.rglob("FontManifest.json")) if assets_root.is_dir() else []
    if manifests:
        manifest_fonts = json.loads(manifests[0].read_text(encoding="utf-8"))
        manrope = [family for family in manifest_fonts
                   if family.get("family") == "packages/sadohod_shared_core/Manrope"]
        if not manrope:
            errors.append("Flutter Web FontManifest does not register the shared Manrope")
        elif not any(
            font.get("weight") == 500
            and font.get("asset", "").endswith("Manrope-Medium.ttf")
            for font in manrope[0].get("fonts", [])
        ):
            errors.append("Flutter Web FontManifest has no Manrope Medium 500 mapping")

if errors:
    for problem in errors:
        print("FAIL:", problem, file=sys.stderr)
    raise SystemExit(1)
print("PASS: 7 original Manrope TTF hashes and weights validated"
      + ("; browser build includes the same exact TTF binaries" if args.web_build else "") + ".")
