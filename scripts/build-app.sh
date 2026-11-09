#!/bin/zsh
# Builds dist/Drift Scorecard.app and a zip of it for sharing.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product DriftScorecardApp
APP="dist/Drift Scorecard.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DriftScorecardApp "$APP/Contents/MacOS/DriftScorecardApp"
ICONS="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONS"
swift scripts/make-icon.swift "$ICONS"
iconutil -c icns "$ICONS" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Drift Scorecard</string>
<key>CFBundleDisplayName</key><string>Drift Scorecard</string>
<key>CFBundleIdentifier</key><string>com.levifactora.drift-scorecard</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>DriftScorecardApp</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
(cd dist && ditto -c -k --keepParent "Drift Scorecard.app" "Drift-Scorecard-Mac.zip")
echo "Built $APP and dist/Drift-Scorecard-Mac.zip"
