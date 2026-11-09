#!/bin/bash
# WHAT: Every suite in one `swift test` (Core, Render, Agents, Voice, App). Optional filter.
# PIN:  The tests are built first and mlx.metallib installed beside them (build-metallib.sh), so a
#       suite that touches MLX finds its kernels. No suite downloads a model or needs one: those
#       checks run in adverb-model-probe.
#
#   ./Scripts/test.sh
#   ./Scripts/test.sh BeatTrackerTests
#
set -e
cd "$(dirname "$0")/.."
swift build --build-tests
Scripts/build-metallib.sh debug
if [ -n "${1:-}" ]; then swift test --skip-build --filter "$1"; else swift test --skip-build; fi
