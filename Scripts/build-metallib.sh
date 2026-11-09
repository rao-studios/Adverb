#!/usr/bin/env bash
# WHAT: Install MLX's mlx.metallib next to every binary in this package's .build
#       (executables and .xctest bundles), and optionally inside an assembled app.
# PIN:  A DELEGATE, NOT AN IMPLEMENTATION. Frigate owns the .metal sources and the
#       compile; this script only finds Frigate's canonical build-metallib.sh and
#       points it at this package. `swift build` has NO Metal step, so without this the
#       first GPU op aborts with "Failed to load the default metallib".
#       MLX probes `mlx.metallib` beside the RUNNING binary first; Frigate's resource
#       bundle (Frigate_Cmlx.bundle) is never probed, so this file is the only rung.
#       CODESIGN TREATS ANY FILE UNDER Contents/MacOS AS NESTED CODE. The canonical
#       script writes mlx.metallib and Resources/default.metallib there; unsigned, they
#       make the next `swift build --build-tests` fail re-signing the .xctest bundle.
#       So every installed metallib is ad-hoc signed and each test bundle re-sealed.
#       An assembled app gets its metallibs signed too; make-app.sh signs the app after.
#
#       FRIGATE IS WHEREVER SWIFTPM PUT IT: the checkout under .build/checkouts, or the
#       folder `swift package edit Frigate --path …` points at. Read from SwiftPM's
#       workspace state, so the shaders always match the sources the binary was built from.
#
#       Lifted from Craft (Scripts/build/build-metallib.sh), unchanged but for the paths.
#
#   ./Scripts/build-metallib.sh [debug|release] [--app build/Adverb.app]
#   FRIGATE_DIR=/path/to/Frigate ./Scripts/build-metallib.sh release
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The Frigate this package resolved: an edited one first, else its checkout.
resolved_frigate() {
    python3 -I - "$REPO_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
try:
    deps = json.load(open(os.path.join(root, ".build", "workspace-state.json")))["object"]["dependencies"]
except (OSError, ValueError, KeyError):
    sys.exit(1)
for dep in deps:
    ref = dep["packageRef"]
    if ref["identity"] != "frigate":
        continue
    state, sub = dep.get("state", {}), dep.get("subpath", "Frigate")
    if state.get("name") == "edited":
        print(state.get("path") or os.path.join(root, "Packages", sub))
    elif ref.get("kind") == "fileSystem":
        print(ref["location"])
    else:
        print(os.path.join(root, ".build", "checkouts", sub))
    sys.exit(0)
sys.exit(1)
PY
}

FRIGATE_DIR="${FRIGATE_DIR:-$(resolved_frigate || true)}"
CANONICAL="${FRIGATE_DIR:+$FRIGATE_DIR/scripts/build-metallib.sh}"

if [ -z "$CANONICAL" ] || [ ! -x "$CANONICAL" ]; then
    echo "build-metallib: cannot find Frigate's build-metallib.sh${CANONICAL:+ at $CANONICAL}" >&2
    echo "  Resolve the package first (swift package resolve), or set FRIGATE_DIR." >&2
    exit 1
fi

CONFIG="debug"
APP=""
while [ $# -gt 0 ]; do
    case "$1" in
        debug|release) CONFIG="$1"; shift ;;
        --app) APP="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "build-metallib: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

# PIN: WRITABLE FIRST. `swift package update` leaves an updated checkout's files read-only, the last build's
#      mlx.metallib in Frigate's stage among them, and the link then failed "Failed to write … mlx.metallib" (2026-11-07).
[ -d "$FRIGATE_DIR/.build" ] && chmod -R u+w "$FRIGATE_DIR/.build"

if [ -n "$APP" ]; then
    "$CANONICAL" "$CONFIG" --package "$REPO_ROOT" --app "$APP"
else
    "$CANONICAL" "$CONFIG" --package "$REPO_ROOT"
fi

sign_metallibs() {  # dir → ad-hoc sign every metallib under it (xattrs stripped first)
    find "$1" \( -name mlx.metallib -o -name default.metallib \) -type f | while read -r lib; do
        xattr -c "$lib" 2>/dev/null || true
        codesign --force --sign - "$lib" 2>/dev/null || true
    done
}

BUILD_DIR="$(cd "$REPO_ROOT/.build/$CONFIG" 2>/dev/null && pwd -P || true)"
if [ -n "$BUILD_DIR" ]; then
    sign_metallibs "$BUILD_DIR"
    find "$BUILD_DIR" -maxdepth 1 -name '*.xctest' -type d | while read -r bundle; do
        codesign --force --sign - "$bundle" 2>/dev/null \
            || echo "build-metallib: could not re-seal $(basename "$bundle")" >&2
    done
fi
if [ -n "$APP" ]; then
    sign_metallibs "$APP/Contents/MacOS"
fi
echo "build-metallib: signed metallibs, re-sealed test bundles"
