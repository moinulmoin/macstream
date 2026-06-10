#!/usr/bin/env python3
"""Generate the MacStream play mark following Apple's macOS 26 icon guidance.

Apple's Liquid Glass icons want FLAT, crisp-edged vector layers with no baked
blur/shadow/specular/gloss and no pre-applied corner mask — the system renders
depth at runtime. So this emits:

  - Resources/AppIcon/icon-composer/MacStream-Foreground.svg
        a flat, transparent, full-canvas play triangle (the foreground layer to
        drop into Icon Composer; set the gradient background there).
  - Resources/AppIcon/MacStream-AppIcon-Source.png  (+ README hero)
        a clean FLAT composite (gradient background + play + rounded-corner mask)
        used to build the legacy .icns for SwiftPM packaging / older releases.

Usage: python3 script/generate_logo.py   (requires Pillow)
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SS = 4

# Brand background gradient (set in Icon Composer for the real glass icon).
INDIGO = (108, 124, 250)   # top    #6C7CFA
VIOLET = (52, 38, 128)     # bottom #342680
WHITE = (255, 255, 255)

# Play triangle geometry on a 1024 canvas (kept well within the canvas — Apple
# says don't fill it). Optically centered for a right-pointing triangle.
A = (385.0, 282.0)   # top-left
B = (765.0, 512.0)   # right tip
C = (385.0, 742.0)   # bottom-left
CORNER = 50.0


def _unit(p, q):
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy)
    return (dx / d, dy / d)


def _rounded_triangle_points(verts, r, samples=24):
    n = len(verts)
    out = []
    for i in range(n):
        prev = verts[(i - 1) % n]
        v = verts[i]
        nxt = verts[(i + 1) % n]
        uin = _unit(v, prev)          # from vertex back toward prev
        uout = _unit(v, nxt)          # from vertex toward next
        t1 = (v[0] + uin[0] * r, v[1] + uin[1] * r)
        t2 = (v[0] + uout[0] * r, v[1] + uout[1] * r)
        for s in range(samples + 1):
            t = s / samples
            mt = 1 - t
            x = mt * mt * t1[0] + 2 * mt * t * v[0] + t * t * t2[0]
            y = mt * mt * t1[1] + 2 * mt * t * v[1] + t * t * t2[1]
            out.append((x, y))
    return out


def _svg_path(verts, r):
    cmds = []
    for i in range(len(verts)):
        prev = verts[(i - 1) % len(verts)]
        v = verts[i]
        nxt = verts[(i + 1) % len(verts)]
        uin = _unit(v, prev)
        uout = _unit(v, nxt)
        t1 = (v[0] + uin[0] * r, v[1] + uin[1] * r)
        t2 = (v[0] + uout[0] * r, v[1] + uout[1] * r)
        cmds.append(f"{'M' if i == 0 else 'L'} {t1[0]:.2f} {t1[1]:.2f}")
        cmds.append(f"Q {v[0]:.2f} {v[1]:.2f} {t2[0]:.2f} {t2[1]:.2f}")
    cmds.append("Z")
    return " ".join(cmds)


def write_svg():
    path = _svg_path([A, B, C], CORNER)
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 1024 1024">\n'
        f'  <path d="{path}" fill="#FFFFFF"/>\n'
        "</svg>\n"
    )
    out = ROOT / "Resources" / "AppIcon" / "icon-composer" / "MacStream-Foreground.svg"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg)
    print(f"wrote {out.relative_to(ROOT)}")


def vertical_gradient(size, top, bottom):
    mask = Image.linear_gradient("L").resize((size, size))
    return Image.composite(
        Image.new("RGB", (size, size), bottom),
        Image.new("RGB", (size, size), top),
        mask,
    )


def superellipse_alpha(size, n=4.8):
    m = Image.new("L", (size, size), 0)
    a = size / 2
    pts = []
    for i in range(1600):
        th = 2 * math.pi * i / 1600
        ct, st = math.cos(th), math.sin(th)
        x = a + a * math.copysign(abs(ct) ** (2 / n), ct)
        y = a + a * math.copysign(abs(st) ** (2 / n), st)
        pts.append((x, y))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def render_flat_png():
    size = 1024 * SS
    bg = vertical_gradient(size, INDIGO, VIOLET).convert("RGBA")
    bg.putalpha(superellipse_alpha(size))
    play = _rounded_triangle_points([A, B, C], CORNER)
    play = [(x * SS, y * SS) for x, y in play]
    ImageDraw.Draw(bg).polygon(play, fill=WHITE + (255,))
    icon = bg.resize((1024, 1024), Image.LANCZOS)
    for p in (
        ROOT / "Resources" / "AppIcon" / "MacStream-AppIcon-Source.png",
        ROOT / ".github" / "assets" / "macstream-logo.png",
    ):
        p.parent.mkdir(parents=True, exist_ok=True)
        icon.save(p)
        print(f"wrote {p.relative_to(ROOT)}")


if __name__ == "__main__":
    write_svg()
    render_flat_png()
