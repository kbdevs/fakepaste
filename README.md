# fakepaste

`fakepaste` is a native macOS menu bar app that types your clipboard text like a fast human: variable rhythm, occasional mistakes, and automatic backspace fixes.

- Hotkey: `Option + Cmd + V`
- Press once to start typing clipboard contents
- Press again to stop mid-stream
- Trigger waits for key release + 100ms before acting
- Menu bar icon (keyboard symbol) for settings and quit

## Download

Grab the latest `.dmg` from [GitHub Releases](../../releases).

## Why fakepaste

- Natural-feeling typing instead of instant paste
- Adjustable speed and humanization settings from the menu bar
- Word-boundary pauses (not random mid-word stops)
- Lightweight always-on utility

## Settings (Menu Bar)

Click the menu bar icon to adjust:

- Speed (WPM presets)
- Typo profile
- Word pause profile

## Install From Source

```bash
swift test
./build_app.sh
./install_launchagent.sh
```

This installs `FakePaste.app` to `/Applications/FakePaste.app` and runs it via LaunchAgent.

## Permissions (macOS)

To type into other apps, macOS requires permissions for `FakePaste.app`:

- `Privacy & Security` -> `Accessibility`
- `Privacy & Security` -> `Input Monitoring`

## Keep Permissions Stable Across Rebuilds

macOS can reset permissions if the app signature changes. Use a consistent signing identity:

```bash
security find-identity -v -p codesigning
export FAKEPASTE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
./build_app.sh
./install_launchagent.sh
```

If `FAKEPASTE_CODESIGN_IDENTITY` is unset, install falls back to ad-hoc signing.

## Stop Auto-Start

```bash
launchctl unload ~/Library/LaunchAgents/com.fakepaste.typer.plist
```
