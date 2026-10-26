#!/bin/bash
# WHAT: Assemble build/Adverb.app from a release build.
# OUT:  build/Adverb.app — binary, Info.plist (stamped with AdverbBuildCommit and AdverbBuildDate,
#       which Settings › About shows), the resource bundles (the motion kit, the prompts, the UI
#       faces), Assets.car (the macOS 26 layered icon) and AppIcon.icns.
#       build/app-metadata.json — version, build, commit, date, signer and the executable's MD5.
# PIN:  Package.swift and Support/Info.plist must agree on the minimum OS.
#       Sign inside-out; never --deep. A stable identity when there is one, else ad-hoc.
#       ONE ICON COMPILE AT A TIME across every Rao checkout (/tmp/rao-actool.lock): two actool
#       runs at once once handed one app the other's renditions (Ambient, 2026-10-15).
#
#   ./Scripts/make-app.sh            → build/Adverb.app
#   SIGN_IDENTITY="Developer ID Application: …" ./Scripts/make-app.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/build/Adverb.app"
METADATA="$REPO_ROOT/build/app-metadata.json"
CONFIG=release
cd "$REPO_ROOT"

PKG_OS="$(sed -nE 's/.*\.macOS\("([0-9.]+)"\).*/\1/p' Package.swift | head -1)"
PLIST_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Support/Info.plist)"
if [ "$PKG_OS" != "$PLIST_OS" ]; then
    echo "make-app: Package.swift says macOS $PKG_OS but Support/Info.plist says $PLIST_OS" >&2
    exit 1
fi

echo "▸ swift build -c $CONFIG --product Adverb"
swift build -c $CONFIG --product Adverb

echo "▸ assembling $APP_DIR"
rm -rf "$APP_DIR" "$METADATA"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/$CONFIG/Adverb" "$APP_DIR/Contents/MacOS/Adverb"
cp "Support/Info.plist" "$APP_DIR/Contents/Info.plist"

commit="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
[ -z "$(git status --porcelain 2>/dev/null)" ] || commit="$commit-dirty"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/libexec/PlistBuddy -c "Add :AdverbBuildCommit string $commit" -c "Add :AdverbBuildDate string $built_at" "$APP_DIR/Contents/Info.plist"
echo "▸ stamped AdverbBuildCommit $commit, AdverbBuildDate $built_at"

copied=0
for bundle in ".build/$CONFIG"/Adverb_*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    copied=$((copied + 1))
done
[ "$copied" -ge 2 ] || { echo "error: expected the Adverb_AdverbCore and Adverb_AdverbApp resource bundles, found $copied" >&2; exit 1; }
echo "▸ copied $copied resource bundles"

ICON_LOCK="/tmp/rao-actool.lock"
for _ in $(seq 1 150); do
    mkdir "$ICON_LOCK" 2>/dev/null && break
    echo "▸ waiting for another icon compile to finish ($ICON_LOCK)"; sleep 2
done
[ -d "$ICON_LOCK" ] || { echo "error: could not take $ICON_LOCK" >&2; exit 1; }
trap 'rmdir "$ICON_LOCK" 2>/dev/null' EXIT
ACTOOL_OUT="$(xcrun actool "Support/AppIcon/AppIcon.icon" --compile "$APP_DIR/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$PKG_OS" --app-icon AppIcon \
    --include-all-app-icons --output-partial-info-plist "$REPO_ROOT/build/AppIcon-partial.plist" \
    --output-format human-readable-text 2>&1)"
if echo "$ACTOOL_OUT" | grep -q -i "error" || [ ! -f "$APP_DIR/Contents/Resources/Assets.car" ]; then
    echo "error: actool failed to compile Support/AppIcon/AppIcon.icon" >&2
    echo "$ACTOOL_OUT" >&2
    exit 1
fi
echo "▸ compiled AppIcon.icon → Assets.car"
rmdir "$ICON_LOCK"; trap - EXIT
ICONSET="$REPO_ROOT/build/AppIcon.iconset"
"$REPO_ROOT/Scripts/make-iconset.sh" "Support/AppIcon/icon_1024.png" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    IDENTITY="$SIGN_IDENTITY"
    FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY")
    echo "▸ codesign (release: $IDENTITY, hardened runtime)"
else
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Mary Dev Signing/ {print $2; exit}')"
    if [ -n "$IDENTITY" ]; then echo "▸ codesign (stable identity: $IDENTITY)"; else IDENTITY="-"; echo "▸ codesign (ad-hoc)"; fi
    FLAGS=(--force --sign "$IDENTITY")
fi
codesign "${FLAGS[@]}" --entitlements Support/Adverb.entitlements "$APP_DIR"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
md5="$(md5 -q "$APP_DIR/Contents/MacOS/Adverb")"
cat > "$METADATA" <<JSON
{
  "version": "$version",
  "build": "$build_number",
  "commit": "$commit",
  "builtAt": "$built_at",
  "signedBy": "$IDENTITY",
  "executable": "Adverb.app/Contents/MacOS/Adverb",
  "md5": "$md5"
}
JSON
echo "▸ wrote $METADATA (md5 $md5)"
echo "Done: $APP_DIR"
