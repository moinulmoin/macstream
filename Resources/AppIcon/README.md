# MacStream App Icon

Source artwork lives in `MacStream-AppIcon-Source.png`. This is the chosen glassy camera/cue concept for the app icon. The generated icon crops the source inward before resizing so the color plate fills the Dock/Finder icon without an extra pale outer shell.

Generated macOS resources:

- `MacStream.iconset/` contains the standard PNG sizes expected by `iconutil`.
- `MacStream.icns` is generated from that iconset.
- `preview/MacStream-AppIcon-1024.png` is a preview render of the source art.

To regenerate the PNGs after updating the source image, crop the source around the non-black artwork and resize that crop to 1024px before producing the iconset sizes:

```sh
python3 - <<'PY'
from PIL import Image, ImageDraw
from pathlib import Path

root = Path("Resources/AppIcon")
source = Image.open(root / "MacStream-AppIcon-Source.png").convert("RGB")
bbox = source.point(lambda value: 255 if value > 8 else 0).getbbox()
left, top, right, bottom = bbox
cx = (left + right) / 2
cy = (top + bottom) / 2
side = 1010
base = source.crop((
    round(cx - side / 2),
    round(cy - side / 2),
    round(cx + side / 2),
    round(cy + side / 2),
)).resize((1024, 1024), Image.Resampling.LANCZOS).convert("RGBA")

mask = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=204, fill=255)
base.putalpha(mask)
base.save(root / "preview/MacStream-AppIcon-1024.png")

sizes = {
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

for name, size in sizes.items():
    base.resize((size, size), Image.Resampling.LANCZOS).save(root / "MacStream.iconset" / name)

base.save(root / "MacStream.icns", format="ICNS", sizes=[
    (16, 16), (32, 32), (128, 128), (256, 256), (512, 512), (1024, 1024),
])
PY
```

`script/package_macos_app.sh` copies `MacStream.icns` into the app bundle and `Resources/Info.plist` declares `CFBundleIconFile` with value `MacStream`.
