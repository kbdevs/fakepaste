#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_BIN="$(command -v swift || true)"
RELEASE_BIN="$PROJECT_DIR/.build/release/FakePasteApp"
APP_DIR="$PROJECT_DIR/FakePaste.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if [ -z "$SWIFT_BIN" ]; then
  printf "Error: swift not found in PATH.\n" >&2
  exit 1
fi

"$SWIFT_BIN" build -c release --package-path "$PROJECT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp -X "$RELEASE_BIN" "$MACOS_DIR/FakePaste"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>FakePaste</string>
  <key>CFBundleIdentifier</key>
  <string>com.fakepaste.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>FakePaste</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

/usr/bin/xattr -cr "$APP_DIR"

printf "Built app bundle at %s\n" "$APP_DIR"
