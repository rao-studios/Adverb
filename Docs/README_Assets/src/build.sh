#!/bin/zsh
# Rebuilds the README images and the app icon: HTML rendered by Google Chrome through Playwright
# (pip install playwright; it drives the installed Chrome). Writes Docs/README_Assets/{hero,icon}.png
# and Support/AppIcon/icon_1024.png (+ AppIcon.icon/Assets/icon_1024.png). Name targets to rebuild
# only those (e.g. `build.sh hero`).
set -euo pipefail
repo=${0:A:h:h:h:h}
cd "$repo"
python3 -I Docs/README_Assets/src/build.py Docs/README_Assets "$@"
