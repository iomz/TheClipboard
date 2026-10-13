#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/TheClipboard/$VERSION/The Clipboard.app"}
mkdir -p "$ROOT/build/tests"
swiftc "$ROOT/Sources/TheClipboard/ApplicationIconController.swift" "$ROOT/Tests/ApplicationIconChecks.swift" \
  -o "$ROOT/build/tests/application-icon-checks"
"$ROOT/build/tests/application-icon-checks" "$APP"
# Real launch/event-loop probe, without production bundle ID/defaults, history,
# hotkeys, updater, Manager windows, or installed-app changes.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-icon-launch.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
FIXTURE="$WORK/Icon Launch Probe.app"
mkdir -p "$FIXTURE/Contents/MacOS" "$FIXTURE/Contents/Resources"
cp "$APP/Contents/Resources/AppIcon.icns" "$FIXTURE/Contents/Resources/"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.iomz.TheClipboard.Test.IconLaunch</string>
<key>CFBundleExecutable</key><string>IconLaunchProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc "$ROOT/Sources/TheClipboard/ApplicationIconController.swift" "$ROOT/Tests/ApplicationIconLifecycleChecks.swift" \
  -o "$FIXTURE/Contents/MacOS/IconLaunchProbe"
for CHOICE in fresh dustlight lagoon; do
  "$FIXTURE/Contents/MacOS/IconLaunchProbe" "$CHOICE"
done
