# MacStream App Icon

MacStream uses the selected **Broadcast Core** icon: a capture frame, camera lens,
broadcast arcs, and live-status dot on a dark Liquid Glass-style tile.

## Source of truth

- `MacStream-AppIcon-Original.png` — the original OpenAI-generated master image
  chosen for the product identity.
- `MacStream-AppIcon-Source.png` — normalized 1024 px transparent app-icon
  source generated from the master.
- `.github/assets/macstream-logo.png` — README/logo copy generated from the same
  source.
- `MacStream.icns` + `MacStream.iconset/` — packaged app icon output.

## Regenerate

```bash
python3 script/generate_logo.py
python3 script/generate_app_icon.py
```

`generate_logo.py` removes only the light edge-connected generation background,
keeps glass highlights inside the mark, and writes the normalized transparent
source used by both the app bundle and README.

## Packaging

`Resources/Info.plist` declares `CFBundleIconFile` = `MacStream`. The packaging
script includes `MacStream.icns` in `dist/MacStream.app`.
