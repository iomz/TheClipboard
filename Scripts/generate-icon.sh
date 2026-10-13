#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/icons/AppIcon.icns"}
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [output.icns]" >&2
  exit 1
fi
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
mkdir -p "$(dirname -- "$OUT")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
swift "$ROOT/Scripts/generate-icon.swift" "$ROOT/Resources/Artwork/AppIcon.png" "$WORK/AppIcon.iconset"
iconutil --convert icns --output "$WORK/AppIcon.icns" "$WORK/AppIcon.iconset"
cp -n "$WORK/AppIcon.icns" "$OUT"
cmp "$WORK/AppIcon.icns" "$OUT"
echo "Generated $OUT from approved sRGB/alpha master."
