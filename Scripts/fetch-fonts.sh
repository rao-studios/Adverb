#!/bin/zsh
# WHAT: The kit's six woff2 faces from npm's @fontsource packages (OFL), per the rao-motion-assets
#       skill §5: Instrument Serif 400 normal/italic, Newsreader 400 normal/italic, JetBrains Mono
#       400/500.
# OUT:  Sources/AdverbCore/Resources/Kit/fonts/*.woff2; committed.
# PIN:  npm pack only downloads; nothing is installed. Needs node/npm on PATH.
#
#   Scripts/fetch-fonts.sh
#
set -euo pipefail
repo=${0:A:h:h}
out="$repo/Sources/AdverbCore/Resources/Kit/fonts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
cd "$work"
npm pack --silent @fontsource/instrument-serif @fontsource/newsreader @fontsource/jetbrains-mono >/dev/null
for t in *.tgz; do mkdir -p "${t%.tgz}"; tar -xzf "$t" -C "${t%.tgz}"; done
for f in instrument-serif-latin-400-normal instrument-serif-latin-400-italic \
         newsreader-latin-400-normal newsreader-latin-400-italic \
         jetbrains-mono-latin-400-normal jetbrains-mono-latin-500-normal; do
  cp */package/files/$f.woff2 "$out/"
done
ls "$out"

# The same faces as TrueType for the app's own UI (CoreText registers TTF, not WOFF2), from the
# packages' zlib WOFF files. Needs fontTools (pip install fonttools); skipped without it.
ui="$repo/Sources/AdverbApp/Resources/Fonts"
mkdir -p "$ui"
python3 -I - "$work" "$ui" <<'PY' || echo "fontTools missing: the UI fonts were not refreshed"
import sys, glob, os
from fontTools.ttLib import TTFont
src, out = sys.argv[1], sys.argv[2]
names = {"instrument-serif-latin-400-normal": "InstrumentSerif-Regular", "instrument-serif-latin-400-italic": "InstrumentSerif-Italic",
         "newsreader-latin-400-normal": "Newsreader-Regular", "newsreader-latin-400-italic": "Newsreader-Italic",
         "jetbrains-mono-latin-400-normal": "JetBrainsMono-Regular", "jetbrains-mono-latin-500-normal": "JetBrainsMono-Medium"}
for stem, name in names.items():
    f = TTFont(glob.glob(f"{src}/*/package/files/{stem}.woff")[0]); f.flavor = None
    f.save(os.path.join(out, name + ".ttf"))
print("UI fonts:", ", ".join(sorted(os.listdir(out))))
PY
