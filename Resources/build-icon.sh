#!/usr/bin/env bash
# Regenerate AppIcon.icns from AppIcon.svg. The SVG is the source of truth; the
# .icns is committed only so the app builds without rsvg-convert installed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v rsvg-convert >/dev/null || { echo "needs rsvg-convert (brew install librsvg)"; exit 1; }
rm -rf AppIcon.iconset && mkdir -p AppIcon.iconset
for s in 16 32 64 128 256 512 1024; do rsvg-convert -w $s -h $s AppIcon.svg -o "/tmp/nakasha_icon_$s.png"; done
cp /tmp/nakasha_icon_16.png   AppIcon.iconset/icon_16x16.png
cp /tmp/nakasha_icon_32.png   AppIcon.iconset/icon_16x16@2x.png
cp /tmp/nakasha_icon_32.png   AppIcon.iconset/icon_32x32.png
cp /tmp/nakasha_icon_64.png   AppIcon.iconset/icon_32x32@2x.png
cp /tmp/nakasha_icon_128.png  AppIcon.iconset/icon_128x128.png
cp /tmp/nakasha_icon_256.png  AppIcon.iconset/icon_128x128@2x.png
cp /tmp/nakasha_icon_256.png  AppIcon.iconset/icon_256x256.png
cp /tmp/nakasha_icon_512.png  AppIcon.iconset/icon_256x256@2x.png
cp /tmp/nakasha_icon_512.png  AppIcon.iconset/icon_512x512.png
cp /tmp/nakasha_icon_1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
echo "AppIcon.icns rebuilt"
