#!/usr/bin/env python3
"""Build MacStream.icns + iconset from the master brand artwork.

The source (`Resources/AppIcon/MacStream-AppIcon-Source.png`) is already a
finished 1024 px squircle with transparent corners (produced by
`script/generate_logo.py`), so this just resizes it into the standard iconset
sizes and assembles the `.icns`.

Usage:
    python3 script/generate_app_icon.py
Requires Pillow (`python3 -m pip install pillow`).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon"
SOURCE = ROOT / "MacStream-AppIcon-Source.png"

ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def main() -> None:
    icon = Image.open(SOURCE).convert("RGBA")
    if icon.size != (1024, 1024):
        icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)

    (ROOT / "preview").mkdir(exist_ok=True)
    icon.save(ROOT / "preview" / "MacStream-AppIcon-1024.png")

    iconset = ROOT / "MacStream.iconset"
    iconset.mkdir(exist_ok=True)
    for name, size in ICONSET_SIZES.items():
        icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)

    icon.save(
        ROOT / "MacStream.icns",
        format="ICNS",
        sizes=[(16, 16), (32, 32), (128, 128), (256, 256), (512, 512), (1024, 1024)],
    )
    print(f"Built MacStream.icns + iconset from {SOURCE.name}")


if __name__ == "__main__":
    main()
