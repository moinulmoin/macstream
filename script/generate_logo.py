#!/usr/bin/env python3
"""Render the MacStream brand mark (play + record dot) at 1024 px.

Draws a smooth superellipse plate with an indigo->violet gradient, a glossy
rounded play triangle, and a coral "live" dot. Writes the master artwork used
by the app icon (`Resources/AppIcon/MacStream-AppIcon-Source.png`) and the
README logo (`.github/assets/macstream-logo.png`).

Usage:
    python3 script/generate_logo.py
Requires Pillow (`python3 -m pip install pillow`).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SS = 4
S = 1024 * SS

INDIGO = (120, 132, 250)   # top
VIOLET = (52, 38, 128)     # bottom
CORAL = (255, 99, 95)
WHITE = (255, 255, 255)


def vertical_gradient(size, top, bottom):
    mask = Image.linear_gradient("L").resize((size, size))  # 0 top -> 255 bottom
    return Image.composite(
        Image.new("RGB", (size, size), bottom),
        Image.new("RGB", (size, size), top),
        mask,
    )


def squircle_alpha(size, n=4.8):
    m = Image.new("L", (size, size), 0)
    a = size / 2
    pts = []
    steps = 1600
    for i in range(steps):
        th = 2 * math.pi * i / steps
        ct, st = math.cos(th), math.sin(th)
        x = a + a * math.copysign(abs(ct) ** (2.0 / n), ct)
        y = a + a * math.copysign(abs(st) ** (2.0 / n), st)
        pts.append((x, y))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def base_plate(size):
    grad = vertical_gradient(size, INDIGO, VIOLET).convert("RGBA")

    sheen = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sheen).ellipse(
        (-size * 0.35, -size * 0.85, size * 1.05, size * 0.42), fill=255
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(size * 0.07))
    layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    layer.putalpha(sheen.point(lambda v: int(v * 0.14)))
    grad = Image.alpha_composite(grad, layer)

    vig = Image.new("L", (size, size), 0)
    ImageDraw.Draw(vig).ellipse((-size * 0.3, size * 0.62, size * 1.3, size * 1.55), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(size * 0.09))
    dark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dark.putalpha(vig.point(lambda v: int(v * 0.24)))
    grad = Image.alpha_composite(grad, dark)

    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(edge).line(
        [(size * 0.12, size * 0.03), (size * 0.88, size * 0.03)],
        fill=(255, 255, 255, 60), width=int(size * 0.01),
    )
    edge = edge.filter(ImageFilter.GaussianBlur(size * 0.01))
    grad = Image.alpha_composite(grad, edge)

    grad.putalpha(squircle_alpha(size))
    return grad


def shadow_of(layer, blur, alpha, dy):
    a = layer.split()[3].point(lambda v: int(v * alpha))
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(sh, (0, dy), sh)
    return out


def mark_play(size):
    m = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    cx, cy = size * 0.53, size * 0.5
    w, h = size * 0.26, size * 0.31
    pts = [(cx - w * 0.5, cy - h * 0.5), (cx - w * 0.5, cy + h * 0.5), (cx + w * 0.62, cy)]
    r = size * 0.078
    d.polygon(pts, fill=WHITE + (255,))
    d.line(pts + [pts[0], pts[1]], fill=WHITE + (255,), width=int(r), joint="curve")
    # subtle top->bottom sheen on the mark
    grad = vertical_gradient(size, (255, 255, 255), (206, 214, 255)).convert("RGBA")
    grad.putalpha(m.split()[3])
    return grad


def render(size):
    plate = base_plate(size)
    mark = mark_play(size)
    out = Image.alpha_composite(plate, shadow_of(mark, size * 0.02, 0.34, int(size * 0.012)))
    out = Image.alpha_composite(out, mark)
    d = ImageDraw.Draw(out)
    rr = size * 0.045
    cxr, cyr = size * 0.70, size * 0.30
    d.ellipse((cxr - rr, cyr - rr, cxr + rr, cyr + rr), fill=CORAL + (255,))
    return out.resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    icon = render(S)
    targets = [
        ROOT / "Resources" / "AppIcon" / "MacStream-AppIcon-Source.png",
        ROOT / ".github" / "assets" / "macstream-logo.png",
    ]
    for path in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        icon.save(path)
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
