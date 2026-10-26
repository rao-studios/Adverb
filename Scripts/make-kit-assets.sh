#!/bin/zsh
# WHAT: The kit's two images from the Rao seal: assets/rao-hero.png (the seal, square, 1024 px)
#       and assets/rao-tex.jpg (the background texture: 1080 px, Gaussian blur 28), per the
#       rao-motion-assets skill §4 step 3.
# IN:   SEAL (default ~/Documents/rao/marketing/products/rao-seal-melted-large.png).
# OUT:  Sources/AdverbCore/Resources/Kit/assets/{rao-hero.png,rao-tex.jpg}; committed, so a build
#       never needs the seal on disk.
# PIN:  Run once, or again when the seal changes. Pillow only (python3 -I).
#
#   Scripts/make-kit-assets.sh
#
set -euo pipefail
repo=${0:A:h:h}
SEAL="${SEAL:-$HOME/Documents/rao/marketing/products/rao-seal-melted-large.png}"
OUT="$repo/Sources/AdverbCore/Resources/Kit/assets"
mkdir -p "$OUT"
python3 -I - "$SEAL" "$OUT" <<'PY'
import sys
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
side = min(im.size)
left, top = (im.width - side) // 2, (im.height - side) // 2
sq = im.crop((left, top, left + side, top + side))
sq.resize((1024, 1024), Image.LANCZOS).save(f"{out}/rao-hero.png", optimize=True)
tex = sq.resize((1080, 1080), Image.LANCZOS).filter(ImageFilter.GaussianBlur(28))
tex.save(f"{out}/rao-tex.jpg", quality=90)
print("rao-hero.png 1024², rao-tex.jpg 1080²")
PY
