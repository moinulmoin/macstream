# MacStream App Icon

Designed to Apple's macOS 26 (Liquid Glass) guidance: a **simple, flat,
crisp-edged** play mark. No baked blur/shadow/specular/gloss — the system
renders depth at runtime. See HIG ▸ Foundations ▸ App icons.

## Source of truth

`python3 script/generate_logo.py` draws the mark and writes:

- `icon-composer/MacStream-Foreground.svg` — flat, transparent, full-canvas play
  triangle. This is the **foreground layer** for Icon Composer.
- `MacStream-AppIcon-Source.png` (+ `.github/assets/macstream-logo.png`) — a flat
  composite (gradient background + play + rounded-corner mask) for the legacy
  `.icns`.

`python3 script/generate_app_icon.py` resizes the source into `MacStream.iconset`
+ `MacStream.icns` + `preview/`. Both scripts need Pillow.

## Real Liquid Glass (macOS 26)

The legacy `.icns` (used by `script/package_macos_app.sh`) is flat. For the true
glass icon:

1. Open **Icon Composer** (Xcode ▸ Open Developer Tool ▸ Icon Composer).
2. Import `icon-composer/MacStream-Foreground.svg` as the foreground layer.
3. Set a **gradient background**: top `#6C7CFA` → bottom `#342680`.
4. Let Icon Composer apply specular / refraction / translucency; export `AppIcon.icon`.
5. Add the `.icon` to an Xcode target (replaces the asset catalog; Xcode
   generates flat fallbacks for older releases automatically).

`Resources/Info.plist` declares `CFBundleIconFile` = `MacStream` for the `.icns`.
