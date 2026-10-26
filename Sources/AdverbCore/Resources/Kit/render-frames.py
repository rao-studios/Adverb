"""Adverb's Chrome renderer: a kit page through Playwright, frames streamed to Adverb.

    python3 -I render-frames.py page.html P|L <frames|stills> [--times t1,t2,...] [--warp p:r,p:r,...] [--cues N] [--scale 1|2]

Writes to stdout a stream of records, each one byte of kind, four bytes of big-endian length, then
the payload:  I = JSON page info (dur, dpr, scenes),  F = one PNG frame (lossless),  C = JSON caption
sample (t, items),  E = JSON error. Adverb encodes the frames itself (H.264 + AAC), so ffmpeg is not
needed; the skill's own render.py remains beside this file for its pipeline exactly.
The page is sought at i/30 — the same value render.py computes — or through the warp's knots.
"""
import json, struct, sys, pathlib, os
from playwright.sync_api import sync_playwright

FPS = 30
HARNESS = os.environ.get("ADVERB_HARNESS", "")
CUES = os.environ.get("ADVERB_CUES_JS", "")


def out(kind, payload):
    sys.stdout.buffer.write(kind + struct.pack(">I", len(payload)) + payload)
    sys.stdout.buffer.flush()


def warp_time(t, knots):
    if not knots:
        return t
    if t <= knots[0][1]:
        return knots[0][0] + (t - knots[0][1])
    if t >= knots[-1][1]:
        return knots[-1][0] + (t - knots[-1][1])
    for (p0, r0), (p1, r1) in zip(knots, knots[1:]):
        if r0 <= t <= r1:
            return p0 if r1 == r0 else p0 + (t - r0) / (r1 - r0) * (p1 - p0)
    return t


def main():
    page_path, orient, mode = sys.argv[1], sys.argv[2].upper(), sys.argv[3]
    args = sys.argv[4:]
    def opt(name, default=None):
        return args[args.index(name) + 1] if name in args else default
    scale = int(opt("--scale", "1"))
    cues_every = int(opt("--cues", "0"))
    knots = [tuple(map(float, k.split(":"))) for k in opt("--warp", "").split(",") if k]
    W, H = (1080, 1920) if orient == "P" else (1920, 1080)
    with sync_playwright() as p:
        launch = {"channel": "chrome"} if sys.platform == "darwin" and os.path.exists("/Applications/Google Chrome.app") else {}
        browser = p.chromium.launch(**launch)
        page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=scale)
        if HARNESS:
            page.add_init_script(HARNESS)
        page.goto(pathlib.Path(page_path).resolve().as_uri() + f"?o={orient}")
        page.wait_for_function("typeof window.seek==='function' && document.fonts.status==='loaded'", timeout=20000)
        page.evaluate("document.fonts.ready")
        page.wait_for_timeout(150)
        info = page.evaluate("({dur:Number(window.DUR||0),dpr:window.devicePixelRatio,scenes:(window.SCENES||[]).map(Number)})")
        out(b"I", json.dumps(info).encode())
        if mode == "stills":
            for t in [float(x) for x in opt("--times", "").split(",") if x]:
                page.evaluate(f"seek({warp_time(t, knots)})")
                out(b"F", page.screenshot(type="png"))
        else:
            total = int(round(FPS * info["dur"]))
            for i in range(total):
                t = i / FPS
                seek = f"{i}/{FPS}" if not knots else repr(warp_time(t, knots))
                page.evaluate(f"seek({seek})")
                out(b"F", page.screenshot(type="png"))
                if cues_every and CUES and i % cues_every == 0:
                    items = page.evaluate(CUES)
                    out(b"C", json.dumps({"t": t, "items": json.loads(items)}).encode())
        browser.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 - reported to Adverb, which shows it
        out(b"E", json.dumps({"error": str(e)}).encode())
        sys.exit(1)
