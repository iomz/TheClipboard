#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP="$ROOT/build/releases/TheClipboard/$VERSION/The Clipboard.app"
if [ -e "$APP" ]; then
  echo "Refusing to overwrite $APP. Move the previous candidate aside first." >&2
  exit 1
fi
swift build --build-system native -c release --arch arm64
FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$FRAMEWORK"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/TheClipboard "$APP/Contents/MacOS/TheClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
"$ROOT/Scripts/generate-icon.sh" "$APP/Contents/Resources/AppIcon.icns"
"$ROOT/Scripts/compile-finder-icon.sh" "$APP/Contents/Resources/Assets.car"

# Prefer a stable local Apple Development identity when one is unambiguous.
# An optional local selector accepts only its SHA-1 identity hash; never commit it.
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
APPLE_DEV_HASHES=$(printf '%s\n' "$IDENTITIES" | awk '/^[[:space:]]*[0-9]+\)/ && /"Apple Development:/ {print tolower($2)}')
IDENTITY_COUNT=$(printf '%s\n' "$APPLE_DEV_HASHES" | awk 'NF {count++} END {print count+0}')
SELECTED_IDENTITY=${THECLIPBOARD_SIGNING_IDENTITY:-}

if [ -n "$SELECTED_IDENTITY" ]; then
  SELECTED_IDENTITY=$(printf '%s' "$SELECTED_IDENTITY" | tr '[:upper:]' '[:lower:]')
  MATCH_COUNT=$(printf '%s\n' "$APPLE_DEV_HASHES" | awk -v selected="$SELECTED_IDENTITY" '$0 == selected {count++} END {print count+0}')
  if [ "$MATCH_COUNT" -ne 1 ]; then
    echo "THECLIPBOARD_SIGNING_IDENTITY must match exactly one installed Apple Development identity." >&2
    exit 1
  fi
  SIGNING_IDENTITY="$SELECTED_IDENTITY"
  echo "Selected local Apple Development identity."
elif [ "$IDENTITY_COUNT" -eq 1 ]; then
  SIGNING_IDENTITY="$APPLE_DEV_HASHES"
  echo "Selected the sole installed Apple Development identity."
elif [ "$IDENTITY_COUNT" -eq 0 ]; then
  SIGNING_IDENTITY=-
  echo "No Apple Development identity found; explicitly using ad-hoc signing."
else
  echo "Multiple Apple Development identities found; refusing ambiguous selection." >&2
  echo "Set THECLIPBOARD_SIGNING_IDENTITY to the intended local identity SHA-1." >&2
  exit 1
fi

# Sign inside-out, retaining Sparkle helper identifiers/entitlements/runtime flags.
# Do not use --deep to sign, and do not change the outer app's runtime policy.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for NESTED in "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" "$SPARKLE"; do
  codesign --force --sign "$SIGNING_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$NESTED"
done
codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
