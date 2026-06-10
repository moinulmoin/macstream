#!/usr/bin/env python3
"""Install the selected MacStream app icon across repo assets.

The source of truth is the OpenAI-generated production concept at
`Resources/AppIcon/MacStream-AppIcon-Original.png`. This script normalizes it
into the transparent 1024 px source used by SwiftPM packaging and the README.

Usage: python3 script/generate_logo.py   (requires Pillow)
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "AppIcon" / "MacStream-AppIcon-Original.png"
APP_ICON_SOURCE = ROOT / "Resources" / "AppIcon" / "MacStream-AppIcon-Source.png"
README_LOGO = ROOT / ".github" / "assets" / "macstream-logo.png"
PREVIEW = ROOT / "Resources" / "AppIcon" / "preview" / "MacStream-AppIcon-1024.png"
CANVAS_SIZE = 1024
PADDING = 20


def _is_edge_background(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return True
    # The generated master has an off-white studio background outside the icon.
    # Remove only light neutral pixels connected to the image edge so glass
    # highlights inside the mark remain intact.
    return (
        red >= 232
        and green >= 232
        and blue >= 232
        and abs(red - green) <= 10
        and abs(green - blue) <= 10
    )


def _remove_connected_edge_background(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        index = y * width + x
        if not visited[index] and _is_edge_background(pixels[x, y]):
            visited[index] = 1
            queue.append((x, y))

    for x in range(width):
        push(x, 0)
        push(x, height - 1)
    for y in range(height):
        push(0, y)
        push(width - 1, y)

    while queue:
        x, y = queue.popleft()
        if x > 0:
            push(x - 1, y)
        if x + 1 < width:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y + 1 < height:
            push(x, y + 1)

    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)

    return image


def _normalize_icon(image: Image.Image) -> Image.Image:
    alpha_bounds = image.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise RuntimeError("Selected icon has no visible pixels after background removal")

    icon = image.crop(alpha_bounds)
    max_dimension = CANVAS_SIZE - (PADDING * 2)
    scale = min(max_dimension / icon.width, max_dimension / icon.height)
    resized = icon.resize(
        (round(icon.width * scale), round(icon.height * scale)),
        Image.Resampling.LANCZOS,
    )

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((CANVAS_SIZE - resized.width) // 2, (CANVAS_SIZE - resized.height) // 2),
    )
    return canvas


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing selected icon source: {SOURCE.relative_to(ROOT)}")

    icon = _normalize_icon(_remove_connected_edge_background(Image.open(SOURCE)))
    for output in (APP_ICON_SOURCE, README_LOGO, PREVIEW):
        output.parent.mkdir(parents=True, exist_ok=True)
        icon.save(output)
        print(f"wrote {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
