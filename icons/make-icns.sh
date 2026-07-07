#!/bin/bash
# Render the chosen SVG into AppIcon.icns and the menu bar template PNGs.
set -euo pipefail
cd "$(dirname "$0")"
CHOSEN=a-print-key.svg

rm -rf AppIcon.iconset app-1024.png
qlmanage -t -s 1024 -o . "$CHOSEN" >/dev/null
mv "$CHOSEN.png" app-1024.png

mkdir AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size app-1024.png --out "AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double app-1024.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset app-1024.png

qlmanage -t -s 36 -o . menubar.svg >/dev/null
mv menubar.svg.png MenuIconTemplate@2x.png
sips -z 18 18 MenuIconTemplate@2x.png --out MenuIconTemplate.png >/dev/null
echo "AppIcon.icns and MenuIconTemplate PNGs written."
