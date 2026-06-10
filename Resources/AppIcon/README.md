# MacStream App Icon

The active icon source is `MacStream-AppIcon-Source.png` — a 1024 px squircle
with transparent corners. The current mark is the **play + live-dot** variant.

Generated macOS resources:

- `MacStream.iconset/` — standard PNG sizes for `iconutil`.
- `MacStream.icns` — assembled from the iconset.
- `preview/MacStream-AppIcon-1024.png` — 1024 px preview.

## Variants

Three brand marks live in `.github/assets/logo-variants/`:

- `play.png` — play triangle in a live ring (active).
- `waveform.png` — audio level bars with a coral live bar.
- `lens.png` — glossy camera lens.

## Switching / regenerating

To make a variant the app icon:

```sh
cp .github/assets/logo-variants/<name>.png Resources/AppIcon/MacStream-AppIcon-Source.png
cp .github/assets/logo-variants/<name>.png .github/assets/macstream-logo.png   # README hero
python3 script/generate_app_icon.py
./script/package_macos_app.sh
```

`script/generate_app_icon.py` resizes the source into the iconset + `.icns`
(requires Pillow). `script/package_macos_app.sh` copies `MacStream.icns` into the
bundle; `Resources/Info.plist` declares `CFBundleIconFile` = `MacStream`.
