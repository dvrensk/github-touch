#!/bin/bash
# Rebuild GitHub Touch and refresh the app bundle in ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=.build/release/GitHubTouch

APP="GitHub Touch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitHubTouch"
if [ -f icons/AppIcon.icns ]; then
  cp icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if ls icons/MenuIconTemplate*.png >/dev/null 2>&1; then
  cp icons/MenuIconTemplate*.png "$APP/Contents/Resources/"
fi
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>GitHub Touch</string>
	<key>CFBundleDisplayName</key><string>GitHub Touch</string>
	<key>CFBundleIdentifier</key><string>se.vrensk.github-touch</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleExecutable</key><string>GitHubTouch</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHumanReadableCopyright</key><string>Local tool</string>
</dict>
</plist>
EOF
codesign -s - --force --deep "$APP"

rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
echo "Built, signed, and installed to ~/Applications/$APP"
