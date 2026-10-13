#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 output-Assets.car" >&2
  exit 1
fi
OUT=$1
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
# Keep SwiftPM's selected toolchain unchanged. Only this subprocess needs full
# Xcode; honor an explicit DEVELOPER_DIR, otherwise use the installed Xcode.
if ! xcrun --find actool >/dev/null 2>&1 && [ -z "${DEVELOPER_DIR:-}" ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi
xcrun --find actool >/dev/null
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-finder-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/AppIcon.icon/Assets" "$WORK/compiled" "$(dirname -- "$OUT")"
cp "$ROOT/Resources/AppIcon.icon/icon.json" "$WORK/AppIcon.icon/icon.json"
# Import exact approved master; no recoloring, alpha filtering or source edits.
cp "$ROOT/Resources/Artwork/AppIcon.png" "$WORK/AppIcon.icon/Assets/AppIcon.png"
cmp "$ROOT/Resources/Artwork/AppIcon.png" "$WORK/AppIcon.icon/Assets/AppIcon.png"
xcrun actool "$WORK/AppIcon.icon" --app-icon AppIcon \
  --compile "$WORK/compiled" --output-partial-info-plist "$WORK/generated.plist" \
  --minimum-deployment-target 26.0 --platform macosx --target-device mac
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$WORK/generated.plist")" = AppIcon
# Keep deterministic ICNS for the running app and fallback.
# Do not ship actool's generated replacement ICNS or the authoring document.
cp -n "$WORK/compiled/Assets.car" "$OUT"
cmp "$WORK/compiled/Assets.car" "$OUT"
echo "Compiled modern Finder icon catalog from unchanged AppIcon master."
