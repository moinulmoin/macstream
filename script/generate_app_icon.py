#!/usr/bin/env python3
"""Regenerate MacStream.icns + iconset from the source artwork.

Trims the near-white background around the source squircle, squares the crop,
resizes to 1024 px, and applies a rounded-rectangle alpha mask so the
Dock/Finder icon has clean transparent corners.

Usage:
    python3 script/generate_app_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon"
SOURCE = ROOT / "MacStream-AppIcon-Source.png"
RADIUS = 210  # squircle corner radius at 1024 px
WHITE_CUTOFF = 240  # pixels brighter than this count as background

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
    source = Image.open(SOURCE).convert("RGBA")

    # Find the artwork bounds by trimming the near-white background.
    gray = source.convert("RGB").convert("L")
    binary = gray.point(lambda value: 255 if value < WHITE_CUTOFF else 0)
    bbox = binary.getbbox() or (0, 0, source.width, source.height)
    left, top, right, bottom = bbox

    # Center a square crop on the artwork.
    cx = (left + right) / 2
    cy = (top + bottom) / 2
    half = max(right - left, bottom - top) / 2
    crop = source.crop(
        (round(cx - half), round(cy - half), round(cx + half), round(cy + half))
    )

    icon = crop.resize((1024, 1024), Image.Resampling.LANCZOS).convert("RGBA")

    mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=RADIUS, fill=255)
    icon.putalpha(mask)

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
    print(f"Regenerated MacStream.icns + iconset from {SOURCE.name}")


if __name__ == "__main__":
    main()
