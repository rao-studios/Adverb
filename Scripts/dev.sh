#!/bin/bash
# WHAT: Build + stable-sign + run the Mac app.
# PIN:  Not `swift run`: SwiftPM ad-hoc-signs, and the identity is the cdhash, which changes every
#       build (Ambient's dev.sh). A stable signature keeps file-access grants (~/Music) too.
#       MLX's mlx.metallib is installed beside the binary first (build-metallib.sh): `swift build`
#       compiles no Metal, and without it the first model call aborts.
#
#   ./Scripts/dev.sh
#   CONFIG=release ./Scripts/dev.sh
#
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
cd "$REPO_ROOT"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG" --product Adverb
"$REPO_ROOT/Scripts/build-metallib.sh" "$CONFIG"

BIN="$REPO_ROOT/.build/$CONFIG/Adverb"
"$REPO_ROOT/Scripts/sign-binary.sh" "$BIN"

CRASH_DIR="$HOME/Library/Logs/Adverb"
mkdir -p "$CRASH_DIR"
export SWIFT_BACKTRACE="${SWIFT_BACKTRACE:-enable=yes,interactive=no,output-to=$CRASH_DIR}"

exec "$BIN" "$@"
