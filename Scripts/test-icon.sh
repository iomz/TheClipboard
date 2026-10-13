#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/TheClipboard/$VERSION/The Clipboard.app"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-icon-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
"$ROOT/Scripts/generate-icon.sh" "$WORK/AppIcon-first.icns"
"$ROOT/Scripts/generate-icon.sh" "$WORK/AppIcon-second.icns"
cmp "$WORK/AppIcon-first.icns" "$WORK/AppIcon-second.icns"
cmp "$WORK/AppIcon-first.icns" "$APP/Contents/Resources/AppIcon.icns"
iconutil --convert iconset --output "$WORK/AppIcon.iconset" "$WORK/AppIcon-first.icns"
swift "$ROOT/Tests/IconChecks.swift" "$ROOT" "$WORK/AppIcon.iconset" "$APP"
echo "Repeated icon generation matches byte-for-byte, including signed bundle resource."
