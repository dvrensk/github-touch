#!/bin/bash
# Render the chosen SVG designs into AppIcon.icns and the menu bar template PNGs.
#
# Rendering is done by render-icons.swift (native CoreGraphics), not
# qlmanage: qlmanage -t rasterizes SVGs against an opaque white QuickLook
# canvas, which bakes an opaque white background into the PNG and breaks
# both the app icon's rounded-corner transparency and the menu bar
# template image's alpha-based rendering.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf AppIcon.iconset app-1024.png MenuIconTemplate.png MenuIconTemplate@2x.png
swift render-icons.swift

mkdir AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size app-1024.png --out "AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double app-1024.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset app-1024.png

echo "AppIcon.icns and MenuIconTemplate PNGs written."
