"""Builds Adverb's README images and app icon from HTML, rendered by the installed Google Chrome
through Playwright.

    Docs/README_Assets/src/build.sh [target …]   # runs this; targets are the function names below

Inputs:  this folder's rr-mark.png; Playfair Display Italic from ~/Library/Fonts (AII's hero face, so
         the READMEs read as one family); the kit's Instrument Serif and the Rao seal from
         Sources/AdverbCore/Resources/Kit.
Outputs: hero.png (2400×1260) and icon.png (a 512 px preview) in argv[1]; Support/AppIcon/icon_1024.png
         and Support/AppIcon/AppIcon.icon/Assets/icon_1024.png.
"""

import os
import shutil
import sys
import tempfile

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.abspath(sys.argv[1])
KIT = os.path.join(REPO, "Sources", "AdverbCore", "Resources", "Kit")
PLAYFAIR = os.path.expanduser("~/Library/Fonts/PlayfairDisplay-Italic-VariableFont_wght.ttf")
INSTRUMENT_ITALIC = os.path.join(KIT, "fonts", "instrument-serif-latin-400-italic.woff2")
SEAL = os.path.join(KIT, "assets", "rao-hero.png")

# AII's hero palette (AII/Docs/README_Assets/src/build.py), so the READMEs read as one family.
HERO_GOLD, HERO_LINE = "#c7a659", "#cbc8c0"
# The kit's gold (rao-motion-assets §1).
GOLD, GOLD_HI, GOLD_DEEP = "#B8914A", "#E2C887", "#86652B"


def shoot(browser, page_html, path, viewport=(1200, 630), scale=2):
    """Writes `page_html` beside the inputs (so relative URLs resolve) and screenshots it."""
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=HERE, delete=False, encoding="utf-8") as f:
        f.write(page_html)
        name = f.name
    try:
        page = browser.new_page(device_scale_factor=scale, viewport={"width": viewport[0], "height": viewport[1]})
        page.goto("file://" + name)
        page.evaluate("document.fonts.ready")
        page.wait_for_timeout(200)
        page.screenshot(path=path)
        page.close()
    finally:
        os.unlink(name)


def brush_path(w, h, seed, rough=None):
    """The kit's brushstroke (kit.js brushPath): a seeded ragged band, wider than it is tall.
    `rough` fixes how ragged the long edges are, in pixels; by default it grows with the height,
    as the kit's does, which is right for a stroke under a line of text and too rough for a tall one."""
    state = [seed]

    def r():
        state[0] = (state[0] * 16807) % 2147483647
        return state[0] / 2147483647

    n, top, bot = 14, [], []
    for i in range(n + 1):
        x = i / n * w
        top.append([x + (r() - .5) * 6, h * .16 + (r() - .5) * (rough if rough is not None else h * .16)])
        bot.append([x + (r() - .5) * 6, h * .9 + (r() - .5) * (rough if rough is not None else h * .14)])
    top[0][0], bot[0][0], top[n][0], bot[n][0] = -6, -2, w + 4, w + 8
    d = f"M{top[0][0]},{top[0][1]}"
    for x, y in top[1:]:
        d += f" L{x:.1f},{y:.1f}"
    d += f" Q{w + 16},{h * .5} {bot[n][0]},{bot[n][1]}"
    for x, y in reversed(bot):
        d += f" L{x:.1f},{y:.1f}"
    return d + f" Q-14,{h * .5} {top[0][0]},{top[0][1]} Z"


# MARK: The hero

# A month reads left to right: thirty days as cells, the posting days in gold. Under them the song,
# a platinum waveform whose beats tick under every day; on a posting day the tick is gold and the
# cut lands on it. Every block's first ink sits on the leading edge of the title's "A" (x 54.5).
X0, CELLS, CELL_W, CELL_GAP = 54.5, 30, 28, 7.2
CELL_Y, CELL_H = 418, 40
WAVE_Y = 496
POSTING = {0, 2, 4, 7, 9, 11, 14, 16, 18, 21, 23, 25, 28}


def cell_x(i):
    return X0 + i * (CELL_W + CELL_GAP)


def hero_band():
    parts = []
    for i in range(CELLS):
        x = cell_x(i)
        if i in POSTING:
            parts.append(f'<rect x="{x}" y="{CELL_Y}" width="{CELL_W}" height="{CELL_H}" rx="5" fill="url(#gold)"/>')
            # A tiny frame inside: portrait on even weeks, landscape on odd, the asset that day ships.
            if (i // 7) % 2 == 0:
                parts.append(f'<rect x="{x + 9}" y="{CELL_Y + 8}" width="10" height="24" rx="1.5" fill="none" stroke="#1b1a17" stroke-width="1.6" opacity=".55"/>')
            else:
                parts.append(f'<rect x="{x + 4}" y="{CELL_Y + 13}" width="20" height="14" rx="1.5" fill="none" stroke="#1b1a17" stroke-width="1.6" opacity=".55"/>')
        else:
            parts.append(f'<rect x="{x + .75}" y="{CELL_Y + .75}" width="{CELL_W - 1.5}" height="{CELL_H - 1.5}" rx="5" fill="none" stroke="#3a3936" stroke-width="1.5"/>')
    # The song: an RMS waveform, louder on each beat (one beat under each day).
    bars, x, k = [], X0, 0
    end = cell_x(CELLS - 1) + CELL_W
    import math
    while x <= end:
        beat_phase = ((x - X0 - CELL_W / 2) % (CELL_W + CELL_GAP)) / (CELL_W + CELL_GAP)
        pulse = math.exp(-((min(beat_phase, 1 - beat_phase)) * 9) ** 2)
        swell = .55 + .45 * math.sin(k * .061) * math.sin(k * .023 + 1.2)
        amp = 4 + 22 * (0.35 * abs(math.sin(k * 1.7) * math.sin(k * .43)) + .65 * pulse) * (.6 + .4 * swell)
        bars.append(f'<rect x="{x:.1f}" y="{WAVE_Y - amp / 2:.1f}" width="2.2" height="{amp:.1f}" rx="1.1" fill="{HERO_LINE}" opacity=".55"/>')
        x += 3.6
        k += 1
    ticks = []
    for i in range(CELLS):
        cx = cell_x(i) + CELL_W / 2
        if i in POSTING:
            ticks.append(f'<line x1="{cx}" y1="{CELL_Y + CELL_H + 6}" x2="{cx}" y2="{WAVE_Y + 26}" stroke="{HERO_GOLD}" stroke-width="2.4" stroke-linecap="round"/>')
        else:
            ticks.append(f'<line x1="{cx}" y1="{WAVE_Y - 18}" x2="{cx}" y2="{WAVE_Y + 18}" stroke="#5a5955" stroke-width="1.2" stroke-linecap="round"/>')
    return "".join(bars) + "".join(ticks) + "".join(parts)


def hero(browser):
    band = hero_band()
    # The brushstroke under the payoff phrase, as the kit draws it under a credited phrase.
    stroke = brush_path(296, 34, 77)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "Playfair"; font-style: italic; font-weight: 400 900; src: url("file://{PLAYFAIR}") format("truetype"), local("Playfair Display Italic"); }}
html, body {{ margin: 0; width: 1200px; height: 630px; overflow: hidden; }}
body {{ position: relative; font-family: "Playfair", Georgia, serif; font-style: italic;
       background: radial-gradient(ellipse 90% 100% at 22% 20%, #20201c 0%, #191917 45%, #121211 100%); }}
.mark {{ position: absolute; left: 46px; top: 52px; width: 72px; }}
.caption {{ position: absolute; left: 132px; top: 72px; letter-spacing: .3em; font-size: 16.5px; color: #8b8a84; font-variant-numeric: lining-nums; }}
.title {{ position: absolute; left: 34px; top: 112px; padding-left: 40px; font-size: 220px; line-height: 1; font-weight: 500; letter-spacing: .02em;
         background: linear-gradient(100deg, #8d9097 0%, #c8cad0 35%, #f2f3f6 58%, #b6b9c1 100%);
         -webkit-background-clip: text; background-clip: text; color: transparent; padding-right: 30px; }}
.sub {{ position: absolute; left: 53.5px; top: 334px; font-size: 45px; color: #9b9991; white-space: nowrap; }}
.sub .paid {{ position: relative; color: #e9e7e0; }}
.sub .paid svg {{ position: absolute; left: 0; top: 18px; z-index: -1; }}
.sub .paid span {{ position: relative; }}
svg.band {{ position: absolute; left: 0; top: 0; }}
.legend {{ position: absolute; left: 54.5px; top: 552px; width: 1091px; display: flex; gap: 34px; align-items: baseline; font-size: 24px; color: #8b8a84; white-space: nowrap; }}
.legend b {{ font-weight: 400; color: #e9e7e0; }}
.sw {{ display: inline-block; width: 13px; height: 17px; border-radius: 3px; margin-right: 10px; transform: translateY(1px); }}
.tick {{ display: inline-block; width: 3px; height: 19px; border-radius: 2px; margin-right: 12px; transform: translateY(2px); background: {HERO_GOLD}; }}
.tag {{ margin-left: auto; }}
</style></head><body>
<img class="mark" src="rr-mark.png">
<div class="caption">RAO STUDIOS · ADVERB</div>
<svg class="band" width="1200" height="630"><defs>
  <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{GOLD_HI}"/><stop offset=".55" stop-color="{HERO_GOLD}"/><stop offset="1" stop-color="{GOLD_DEEP}"/></linearGradient>
</defs>{band}</svg>
<div class="title">Adverb</div>
<div class="sub">a month of motion, planned and <span class="paid"><svg width="296" height="40" style="overflow:visible"><path d="{stroke}" fill="rgba(206,160,72,.42)"/></svg><span>beat-matched</span></span></div>
<div class="legend">
  <span><i class="sw" style="background:linear-gradient(135deg,{GOLD_HI},{HERO_GOLD})"></i><b>a posting day</b> · and its hour</span>
  <span><i class="tick"></i><b>a beat</b> · where the cut lands</span>
  <span class="tag">portrait and landscape, captioned</span>
</div>
</body></html>"""
    shoot(browser, page, os.path.join(OUT, "hero.png"), viewport=(1200, 630))


# MARK: The app icon

# An adverb tells how and when the verb happens; its mark is the "-ly". Italic gold "ly" in the kit's
# Instrument Serif on liquid platinum (the Rao seal, blurred, under the kit's page gradient), with the
# kit's gold brushstroke as a highlight across the letters' x-height, baseline to the top of the y. Full-bleed square: macOS masks it, and the Icon Composer layer
# (AppIcon.icon) scales it to the tile.
def icon(browser):
    stroke = brush_path(560, 451, 31, rough=18)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "Instrument Serif"; font-style: italic; src: url("file://{INSTRUMENT_ITALIC}") format("woff2"); }}
html, body {{ margin: 0; width: 1024px; height: 1024px; overflow: hidden; }}
body {{ position: relative; background: linear-gradient(175deg, #EFEEEA 0%, #E2E1DC 55%, #D3D2CC 100%); }}
.tex {{ position: absolute; inset: -60px; background: url("file://{SEAL}") center/cover; filter: blur(34px) saturate(.25) brightness(1.06);
        opacity: .55; mix-blend-mode: multiply; }}
.sheen {{ position: absolute; inset: 0; background: radial-gradient(70% 55% at 30% 18%, rgba(255,255,255,.55), transparent 70%); }}
.brush {{ position: absolute; left: 236px; top: 224px; }}
.ly {{ position: absolute; left: 0; width: 1024px; top: 70px; text-align: center; font-family: "Instrument Serif"; font-style: italic;
       font-size: 660px; line-height: 1; letter-spacing: -.02em; padding-right: 30px; padding-bottom: 220px; box-sizing: border-box;
       background: linear-gradient(160deg, #D9B66E 0%, {GOLD} 40%, #9C7535 70%, {GOLD_DEEP} 100%);
       -webkit-background-clip: text; background-clip: text; color: transparent;
       filter: drop-shadow(0 10px 14px rgba(90,70,30,.28)); }}
</style></head><body>
<div class="tex"></div><div class="sheen"></div>
<svg class="brush" width="560" height="451" style="overflow:visible"><path d="{stroke}" fill="rgba(206,160,72,.40)"/></svg>
<div class="ly">ly</div>
</body></html>"""
    master = os.path.join(REPO, "Support", "AppIcon", "icon_1024.png")
    shoot(browser, page, master, viewport=(1024, 1024), scale=1)
    layer = os.path.join(REPO, "Support", "AppIcon", "AppIcon.icon", "Assets")
    os.makedirs(layer, exist_ok=True)
    shutil.copyfile(master, os.path.join(layer, "icon_1024.png"))
    with Image.open(master) as im:
        im.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))


ALL = ["hero", "icon"]


def main():
    targets = sys.argv[2:] or ALL
    os.makedirs(OUT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        for target in targets:
            globals()[target](browser)
        browser.close()
    for path in [os.path.join(OUT, "hero.png"), os.path.join(OUT, "icon.png"), os.path.join(REPO, "Support", "AppIcon", "icon_1024.png")]:
        if os.path.exists(path):
            with Image.open(path) as im:
                print(f"{os.path.relpath(path, REPO)}: {im.size[0]}×{im.size[1]}, {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
