# OpenCue App Icon

Source artwork lives in `OpenCue-AppIcon-Source.png`. This is the chosen glassy camera/cue concept for the app icon.

Generated macOS resources:

- `OpenCue.iconset/` contains the standard PNG sizes expected by `iconutil`.
- `OpenCue.icns` is generated from that iconset.
- `preview/OpenCue-AppIcon-1024.png` is a preview render of the source art.

To regenerate the PNGs after updating the source image:

```sh
/usr/bin/sips -z 1024 1024 Resources/AppIcon/OpenCue-AppIcon-Source.png --out Resources/AppIcon/preview/OpenCue-AppIcon-1024.png
/usr/bin/sips -z 16 16 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_16x16.png
/usr/bin/sips -z 32 32 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_16x16@2x.png
/usr/bin/sips -z 32 32 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_32x32.png
/usr/bin/sips -z 64 64 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_32x32@2x.png
/usr/bin/sips -z 128 128 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_128x128.png
/usr/bin/sips -z 256 256 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_128x128@2x.png
/usr/bin/sips -z 256 256 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_256x256.png
/usr/bin/sips -z 512 512 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_256x256@2x.png
/usr/bin/sips -z 512 512 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_512x512.png
/usr/bin/sips -z 1024 1024 Resources/AppIcon/preview/OpenCue-AppIcon-1024.png --out Resources/AppIcon/OpenCue.iconset/icon_512x512@2x.png
```

`script/package_macos_app.sh` copies `OpenCue.icns` into the app bundle and `Resources/Info.plist` declares `CFBundleIconFile` with value `OpenCue`.
