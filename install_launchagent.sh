#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_BIN="$(command -v swift || true)"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.fakepaste.typer.plist"
LOG_DIR="$HOME/Library/Logs"
SOURCE_APP_PATH="$PROJECT_DIR/FakePaste.app"
TARGET_APP_PATH="/Applications/FakePaste.app"
BINARY_PATH="$TARGET_APP_PATH/Contents/MacOS/FakePaste"
CODESIGN_IDENTITY="${FAKEPASTE_CODESIGN_IDENTITY:-}"

if [ -z "$SWIFT_BIN" ]; then
  printf "Error: swift not found in PATH.\n" >&2
  exit 1
fi

"$PROJECT_DIR/build_app.sh" >/dev/null

if ! /usr/bin/ditto "$SOURCE_APP_PATH" "$TARGET_APP_PATH"; then
  printf "Error: failed to copy app into /Applications.\n" >&2
  printf "Try running: sudo %s/install_launchagent.sh\n" "$PROJECT_DIR" >&2
  exit 1
fi

/usr/bin/xattr -cr "$TARGET_APP_PATH"

if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '/\"/{print $2; exit}')"
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
  /usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" "$TARGET_APP_PATH"
  printf "App signed with identity: %s\n" "$CODESIGN_IDENTITY"
else
  /usr/bin/codesign --force --deep --sign - "$TARGET_APP_PATH"
  printf "Warning: ad-hoc signature used; privacy permissions may reset on rebuild.\n"
  printf "Set FAKEPASTE_CODESIGN_IDENTITY to a persistent cert name to avoid resets.\n"
fi

if [ ! -x "$BINARY_PATH" ]; then
  printf "Error: expected binary missing at %s\n" "$BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$PLIST_DIR"
mkdir -p "$LOG_DIR"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.fakepaste.typer</string>

  <key>ProgramArguments</key>
  <array>
    <string>$BINARY_PATH</string>
  </array>

  <key>WorkingDirectory</key>
  <string>$PROJECT_DIR</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$LOG_DIR/fakepaste.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/fakepaste.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

printf "Installed and started LaunchAgent: %s\n" "$PLIST_PATH"
printf "Logs: %s/fakepaste.log and %s/fakepaste.err.log\n" "$LOG_DIR" "$LOG_DIR"
