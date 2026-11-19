#!/usr/bin/env python3
"""Finalize and validate approved Figma app-icon raster exports.

Every iOS size is taken directly from the original Figma raster export, not
redrawn or scaled by this script. The only modification is removing the alpha
channel (compositing against the already-approved solid background).
"""
import argparse
import json
import struct
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
APPS = {"buyer_app": (255, 255, 255), "seller_app": (95, 15, 16)}
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def png_size(path):
    with path.open("rb") as handle:
        header = handle.read(26)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", f"Not PNG: {path}"
    return struct.unpack(">II", header[16:24]), header[25]


def main(fix=False):
    errors = []
    for app, background in APPS.items():
        base = ROOT / app
        iconset = base / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        spec = json.loads((iconset / "Contents.json").read_text(encoding="utf-8"))
        expected = set()
        for entry in spec["images"]:
            name = entry.get("filename")
            if not name:
                continue
            expected.add(name)
            sz = int(round(float(entry["size"].split("x")[0]) * float(entry["scale"].replace("x", ""))))
            path = iconset / name
            if not path.is_file():
                errors.append(f"Missing: {path}")
                continue
            with Image.open(path) as image:
                if image.size != (sz, sz):
                    errors.append(f"Wrong iOS size: {path} => {image.size}, expected {sz}")
                if fix:
                    # Preserve original RGB pixel values; all raster files from Figma
                    # have an opaque approved background, so no visual change.
                    if image.mode in ("RGBA", "LA"):
                        alpha = image.getchannel("A")
                        if alpha.getextrema() != (255, 255):
                            errors.append(f"Unexpected transparent pixels: {path}")
                    image.convert("RGB").save(path, "PNG", optimize=True)
            if not fix:
                _, ctype = png_size(path)
                if ctype not in (2, 3):
                    errors.append(f"iOS icon has alpha channel: {path} (PNG color type {ctype})")
        assert "Icon-App-1024x1024@1x.png" in expected

        master = base / "assets/icons/app_store_1024.png"
        play = base / "assets/icons/google_play_512.png"
        foreground = base / "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
        for file, size in ((master, 1024), (play, 512), (foreground, 432)):
            if not file.is_file():
                errors.append(f"Missing: {file}")
                continue
            actual, _ = png_size(file)
            if actual != (size, size):
                errors.append(f"Wrong raster dimensions: {file}: {actual}")
        for density, size in DENSITIES.items():
            file = base / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
            if not file.is_file() or png_size(file)[0] != (size, size):
                errors.append(f"Missing/bad mipmap: {file}")
        root = base / "android/app/src/main/res"
        for rel in ("mipmap-anydpi-v26/ic_launcher.xml",
                    "drawable/ic_launcher_monochrome.xml", "values/icon_colors.xml"):
            if not (root / rel).is_file():
                errors.append(f"Missing Android adaptive asset: {root / rel}")
        if not (base / "assets/icons/source.svg").is_file():
            errors.append(f"Missing original vector source: {app}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise SystemExit(1)
    print("OK: both app iconsets, Android adaptive assets, dimensions and iOS opacity")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fix", action="store_true", help="Strip alpha from opaque iOS PNGs")
    main(parser.parse_args().fix)
