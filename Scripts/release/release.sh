#!/bin/bash
# WHAT: A Developer ID release of Adverb: the next version after the last release tag (0.0.0 when
#       there is none) → the app → a signed .pkg → notarized and stapled → a tag on the commit it
#       was built from, pushed → a GitHub release with the .pkg attached.
# IN:   Keychain identities "Developer ID Application" and "Developer ID Installer"; a notarytool
#       profile (NOTARY_PROFILE, default rao-notary):
#         xcrun notarytool store-credentials rao-notary --apple-id <id> --team-id TA6WK7F4P8
#       The GitHub CLI signed in with push access to this repository. A clean checkout of main,
#       not behind origin/main. Every package by URL (Frigate, Granite), never by path.
# OUT:  build/Adverb-<version>.pkg — installs /Applications/Adverb.app (mlx.metallib beside the
#       binary), quitting a running Adverb first and opening the new one.
#       build/Adverb-<version>-manifest.txt — the commits it was built from.
#       A commit "Adverb <version> (<build>)" holding Support/Info.plist, the tag v<version> on it,
#       both pushed, and the release v<version> on GitHub with the .pkg attached.
#       build/ is ignored by git: nothing the run builds is committed.
# PIN:  THE VERSION COMES FROM THE TAGS. The highest vN.N.N tag (origin's included) plus one patch
#       release, or 0.0.0 for the first; --minor, --major or an explicit N.N.N instead. The build
#       number is the last release's plus one (1 for the first), so it only ever grows.
# PIN:  Nothing is tagged, pushed or published until Apple has notarized the .pkg. A run that stops
#       earlier leaves at most the local version commit, and the next run picks it up as it is.
# PIN:  arm64 and macOS 26 only (MLX, and the app's floor), which Support/Pkg/Distribution.xml says
#       to the installer and this script holds to Support/Info.plist.
#
#   ./Scripts/release/release.sh                 # the next patch release (0.0.0 first)
#   ./Scripts/release/release.sh --minor         # 0.3.7 → 0.4.0
#   ./Scripts/release/release.sh --major         # 0.3.7 → 1.0.0
#   ./Scripts/release/release.sh 1.2.0           # exactly this version (above the last one)
#   SKIP_NOTARIZE=1 ./Scripts/release/release.sh # stop at the signed .pkg: no tag, no release
#   ALLOW_DIRTY=1 SKIP_NOTARIZE=1 ./Scripts/release/release.sh   # a dry run from uncommitted work
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$REPO_ROOT/build"
APP="$BUILD/Adverb.app"
PLIST="$REPO_ROOT/Support/Info.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-rao-notary}"
TEAM_ID="TA6WK7F4P8"
GITHUB_REPO="${GITHUB_REPO:-rao-studios/Adverb}"
cd "$REPO_ROOT"

fail() { echo "error: $*" >&2; exit 1; }
DRY=0
if [ "${SKIP_NOTARIZE:-0}" = "1" ] || [ "${ALLOW_DIRTY:-0}" = "1" ]; then DRY=1; fi

# MARK: - Arguments

BUMP=patch
EXPLICIT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --patch) BUMP=patch; shift ;;
        --minor) BUMP=minor; shift ;;
        --major) BUMP=major; shift ;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        -*) fail "unknown option $1 (see --help)" ;;
        *) [ -z "$EXPLICIT" ] || fail "one version at most"; EXPLICIT="$1"; shift ;;
    esac
done
[ -z "$EXPLICIT" ] || [[ "$EXPLICIT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version $EXPLICIT is not N.N.N"

# MARK: - Preflight

identity() {
    security find-identity -v -p "$1" 2>/dev/null | awk -F'"' -v kind="$2" 'index($2, kind) == 1 {print $2; exit}'
}

echo "▸ preflight: identities"
APP_IDENTITY="$(identity codesigning "Developer ID Application")"
[ -n "$APP_IDENTITY" ] || fail "no \"Developer ID Application\" identity in the keychain"
INSTALLER_IDENTITY="$(identity basic "Developer ID Installer")"
[ -n "$INSTALLER_IDENTITY" ] || fail "no \"Developer ID Installer\" identity in the keychain"
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "no notarytool keychain profile '$NOTARY_PROFILE' (see the header)"
fi
if [ "$DRY" = "0" ]; then
    command -v gh >/dev/null || fail "the GitHub CLI is required (brew install gh)"
    gh auth status >/dev/null 2>&1 || fail "the GitHub CLI is not signed in (gh auth login)"
    gh repo view "$GITHUB_REPO" >/dev/null 2>&1 || fail "cannot see $GITHUB_REPO with the GitHub CLI"
fi

echo "▸ preflight: sources"
if grep -Eq '^[[:space:]]*\.package\(path:' Package.swift; then
    fail "Package.swift takes a package by path: a release builds only what URLs and commits name"
fi
[ ! -s .swiftpm/configuration/mirrors.json ] || fail ".swiftpm/configuration/mirrors.json redirects a package"
PLIST_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
grep -q "<os-version min=\"$PLIST_OS\"/>" Support/Pkg/Distribution.xml \
    || fail "Support/Pkg/Distribution.xml does not require macOS $PLIST_OS, as Support/Info.plist does"
for script in preinstall postinstall; do
    [ -x "Support/Pkg/scripts/$script" ] || fail "Support/Pkg/scripts/$script is missing or not executable"
done
if [ "$DRY" = "0" ]; then
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "releases are made from main"
fi
dirty="$(git status --porcelain --untracked-files=normal)"
if [ -n "$dirty" ]; then
    if [ "${ALLOW_DIRTY:-0}" = "1" ]; then
        echo "  warning: uncommitted changes (ALLOW_DIRTY=1)"
    else
        echo "$dirty" | head -20 >&2
        fail "uncommitted changes: commit them, or ALLOW_DIRTY=1 SKIP_NOTARIZE=1 for a dry run"
    fi
fi
git fetch --quiet --tags origin
if [ "$DRY" = "0" ]; then
    behind="$(git rev-list --count HEAD..origin/main)"
    [ "$behind" = "0" ] || fail "main is $behind commit(s) behind origin/main: pull first"
fi

# MARK: - Version

LAST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
if [ -n "$LAST_TAG" ]; then
    IFS=. read -r MAJOR MINOR PATCH <<< "${LAST_TAG#v}"
    case "$BUMP" in
        major) NEXT="$((MAJOR + 1)).0.0" ;;
        minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
        *) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    esac
    LAST_BUILD="$(git show "$LAST_TAG:Support/Info.plist" | plutil -extract CFBundleVersion raw -o - - 2>/dev/null || echo 0)"
else
    NEXT="0.0.0"
    LAST_BUILD=0
fi
VERSION="${EXPLICIT:-$NEXT}"
if [ -n "$LAST_TAG" ]; then
    [ "$(printf '%s\n%s\n' "${LAST_TAG#v}" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] && [ "v$VERSION" != "$LAST_TAG" ] \
        || fail "version $VERSION is not above the last release, $LAST_TAG"
fi
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "the tag v$VERSION exists already"
if [ "$DRY" = "0" ] && gh release view "v$VERSION" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    fail "a GitHub release v$VERSION exists already"
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [ "$PLIST_VERSION" = "$VERSION" ] && [ "$PLIST_BUILD" -gt "$LAST_BUILD" ] 2>/dev/null; then
    BUILD_NUMBER="$PLIST_BUILD"          # a run that stopped before the tag: its commit stands
else
    BUILD_NUMBER="$((LAST_BUILD + 1))"
fi
echo "▸ version: Adverb $VERSION ($BUILD_NUMBER)${LAST_TAG:+, after $LAST_TAG}"
if [ "$PLIST_VERSION" != "$VERSION" ] || [ "$PLIST_BUILD" != "$BUILD_NUMBER" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
    echo "  Support/Info.plist: $PLIST_VERSION ($PLIST_BUILD) → $VERSION ($BUILD_NUMBER)"
    if [ "${ALLOW_DIRTY:-0}" = "1" ]; then
        echo "  not committed (ALLOW_DIRTY=1)"
    else
        git commit -q -m "Adverb $VERSION ($BUILD_NUMBER)" -- "$PLIST"
        echo "  committed $(git rev-parse --short HEAD) “Adverb $VERSION ($BUILD_NUMBER)”"
    fi
fi
PKG="$BUILD/Adverb-$VERSION.pkg"
MANIFEST="$BUILD/Adverb-$VERSION-manifest.txt"
COMMIT="$(git rev-parse HEAD)"

# MARK: - Manifest

pin() { python3 -I -c "import json,sys; print(next((p['state'].get('revision','') for p in json.load(sys.stdin)['pins'] if p['identity']==sys.argv[1]), ''))" "$1" < Package.resolved; }
FRIGATE="$(pin frigate)"
GRANITE="$(pin granite)"
[ -n "$FRIGATE" ] && [ -n "$GRANITE" ] || fail "Package.resolved pins no frigate or granite: swift package resolve first"
mkdir -p "$BUILD"
{
    echo "Adverb $VERSION"
    echo "build   $BUILD_NUMBER"
    echo "date    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "adverb  $COMMIT"
    echo "frigate $FRIGATE (Package.resolved)"
    echo "granite $GRANITE (Package.resolved)"
    echo "xcode   $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
    echo "dirty   ${ALLOW_DIRTY:-0}"
} > "$MANIFEST"
sed 's/^/  /' "$MANIFEST"

# MARK: - App

echo "▸ app"
SIGN_IDENTITY="$APP_IDENTITY" "$REPO_ROOT/Scripts/make-app.sh"

echo "▸ verify the app"
codesign --verify --deep --strict --verbose=2 "$APP"
signature="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$signature" == *"(runtime)"* ]] || fail "$APP lacks the hardened runtime"
[[ "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "$APP is not signed by team $TEAM_ID"
for nested in "$APP/Contents/MacOS/mlx.metallib" "$APP"/Contents/Resources/*.bundle; do
    codesign -dv --verbose=2 "$nested" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" || fail "$nested is not signed by team $TEAM_ID"
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
    || fail "the app's Info.plist does not say $VERSION"
stamp="$(/usr/libexec/PlistBuddy -c 'Print :AdverbBuildCommit' "$APP/Contents/Info.plist")"
if [[ "$stamp" == *-dirty ]] && [ "${ALLOW_DIRTY:-0}" != "1" ]; then fail "the app is stamped $stamp"; fi
echo "  AdverbBuildCommit $stamp"

# MARK: - Package

echo "▸ package"
rm -f "$BUILD/Adverb-component.pkg" "$PKG"
# From a staging root, with relocation off: a relocatable bundle lets the installer "upgrade"
# whatever copy of nyc.rao.adverb macOS last saw (build/Adverb.app on this Mac) instead of
# installing to /Applications. Version checking off as well: with it on, Installer skips the app
# when the installed copy's version is higher and still writes the receipt (Ambient, 2026-10-26).
STAGE="$BUILD/pkg-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Adverb.app"
pkgbuild --analyze --root "$STAGE" "$BUILD/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$BUILD/components.plist"
pkgbuild --root "$STAGE" \
    --component-plist "$BUILD/components.plist" \
    --install-location /Applications \
    --scripts "$REPO_ROOT/Support/Pkg/scripts" \
    --identifier nyc.rao.adverb.pkg \
    --version "$VERSION" \
    "$BUILD/Adverb-component.pkg"
rm -rf "$STAGE" "$BUILD/components.plist"
productbuild --distribution "$REPO_ROOT/Support/Pkg/Distribution.xml" \
    --package-path "$BUILD" \
    --sign "$INSTALLER_IDENTITY" --timestamp \
    "$PKG"
rm -f "$BUILD/Adverb-component.pkg"
pkgutil --check-signature "$PKG"
EXPANDED="$(mktemp -d)"
pkgutil --expand "$PKG" "$EXPANDED/pkg"
for script in preinstall postinstall; do
    [ -x "$EXPANDED/pkg/Adverb-component.pkg/Scripts/$script" ] || fail "$PKG carries no $script"
done
rm -rf "$EXPANDED"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "Skipped notarization: no tag, no release. Signed, unnotarized: $PKG"
    exit 0
fi

# MARK: - Notarize

echo "▸ notarize (Apple usually answers in a few minutes)"
RESULT="$(xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json 2>&1 || true)"
field() { echo "$RESULT" | python3 -I -c "import json,sys
try: print(json.loads(sys.stdin.read()).get(sys.argv[1], ''))
except Exception: print('')" "$1"; }
STATUS="$(field status)"
SUBMISSION="$(field id)"
[ -n "$SUBMISSION" ] || { echo "$RESULT" >&2; fail "notarytool could not submit $PKG"; }
if [ "$STATUS" != "Accepted" ]; then
    xcrun notarytool log "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "notarization came back $STATUS (submission $SUBMISSION): nothing was tagged or published"
fi
echo "  accepted ($SUBMISSION)"

echo "▸ staple"
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ assess"
codesign --verify --deep --strict "$APP"
spctl --assess --type install --verbose "$PKG"
spctl --assess --type exec --verbose "$APP"
SHA256="$(shasum -a 256 "$PKG" | awk '{print $1}')"
SIZE="$(du -h "$PKG" | awk '{print $1}')"
echo "notarized $SUBMISSION" >> "$MANIFEST"
echo "sha256  $SHA256" >> "$MANIFEST"

if [ "$DRY" = "1" ]; then
    echo "Dry run (ALLOW_DIRTY): notarized, not tagged or published: $PKG"
    exit 0
fi

# MARK: - Tag, push, publish

echo "▸ tag and push"
git tag -a "v$VERSION" -m "Adverb $VERSION ($BUILD_NUMBER)" "$COMMIT"
git push --quiet origin "HEAD:main"
git push --quiet origin "v$VERSION"
echo "  v$VERSION → $(git rev-parse --short "$COMMIT"), pushed"

echo "▸ GitHub release"
NOTES="$BUILD/Adverb-$VERSION-notes.md"
{
    echo "Adverb $VERSION (build $BUILD_NUMBER). Plans a month of social posts, writes each day to a contact sheet and renders it in portrait and landscape, with models that run on your Mac."
    echo
    echo "**Install:** open \`Adverb-$VERSION.pkg\`. It installs Adverb in /Applications and opens it. Needs a Mac with Apple silicon and macOS $PLIST_OS or later. Signed with Rao Studios' Developer ID and notarized by Apple."
    echo
    echo "**On first launch** Adverb offers the models for this Mac, downloaded from [huggingface.co/rao-studios](https://huggingface.co/rao-studios). It uses any it finds in ~/.rao/models first."
    echo
    if [ -n "$LAST_TAG" ]; then
        echo "**Changes since $LAST_TAG:**"
        git log --no-merges --format='- %s' "$LAST_TAG..$COMMIT" | grep -v "^- Adverb [0-9]*\.[0-9]*\.[0-9]* (" | head -60 || true
    else
        echo "**First release.** Its history:"
        git log --no-merges --format='- %s' "$COMMIT" | grep -v "^- Adverb [0-9]*\.[0-9]*\.[0-9]* (" | head -60 || true
    fi
    echo
    echo "| | |"
    echo "| --- | --- |"
    echo "| SHA-256 | \`$SHA256\` |"
    echo "| Commit | \`$COMMIT\` |"
    echo "| Frigate | \`$FRIGATE\` |"
    echo "| Granite | \`$GRANITE\` |"
} > "$NOTES"
gh release create "v$VERSION" "$PKG" \
    --repo "$GITHUB_REPO" \
    --verify-tag \
    --title "Adverb $VERSION" \
    --notes-file "$NOTES"
URL="$(gh release view "v$VERSION" --repo "$GITHUB_REPO" --json url -q .url)"

echo "Done: Adverb $VERSION ($BUILD_NUMBER), $SIZE"
echo "      $PKG"
echo "      $URL"
