#!/bin/bash
# WHAT: Every suite in one `swift test` (Core, Render, Agents, App). Optional filter.
#
#   ./Scripts/test.sh
#   ./Scripts/test.sh BeatTrackerTests
#
set -e
cd "$(dirname "$0")/.."
if [ -n "${1:-}" ]; then swift test --filter "$1"; else swift test; fi
