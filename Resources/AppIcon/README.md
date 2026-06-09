# MacStream App Icon

Source artwork lives in `MacStream-AppIcon-Source.png` — a deep indigo→violet
squircle with a play glyph inside concentric broadcast arcs and a coral "live"
dot, the streaming-studio identity of MacStream.

Generated macOS resources:

- `MacStream.iconset/` contains the standard PNG sizes expected by `iconutil`.
- `MacStream.icns` is generated from that iconset.
- `preview/MacStream-AppIcon-1024.png` is the masked 1024 px render.

## Regenerating

After updating `MacStream-AppIcon-Source.png`, run:

```sh
python3 script/generate_app_icon.py
```

The script trims the near-white background around the squircle, squares the
crop, resizes to 1024 px, applies a rounded-rectangle alpha mask for clean
transparent corners, then writes the iconset, `MacStream.icns`, and the preview.
Requires Pillow (`python3 -m pip install pillow`).

`script/package_macos_app.sh` copies `MacStream.icns` into the app bundle and
`Resources/Info.plist` declares `CFBundleIconFile` with value `MacStream`.
