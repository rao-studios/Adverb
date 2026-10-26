"""python render.py page.html P|L video out.mp4
   python render.py page.html P|L stills t1 t2 ...   -> stills/<page>-<P|L>_<t>.jpg
Duration from window.DUR. Orientation is forced with ?o=P|L."""
import sys, subprocess, pathlib, glob, os
from playwright.sync_api import sync_playwright
HERE = pathlib.Path(__file__).parent.resolve(); FPS = 30
def chrome():
    if sys.platform == "darwin" and not os.environ.get("CHROME") and os.path.exists("/Applications/Google Chrome.app"):
        return {"channel": "chrome"}
    c = os.environ.get("CHROME") or next(iter(sorted(glob.glob("/opt/pw-browsers/chromium-*/chrome-linux64/chrome"))), None)
    return {"executable_path": c} if c else {}
def main():
    page, orient, mode = sys.argv[1], sys.argv[2].upper(), sys.argv[3]
    W, H = (1080, 1920) if orient == "P" else (1920, 1080)
    with sync_playwright() as p:
        b = p.chromium.launch(**chrome())
        pg = b.new_page(viewport={"width": W, "height": H})
        pg.goto((HERE / page).as_uri() + f"?o={orient}")
        pg.wait_for_function("typeof window.seek==='function'"); pg.wait_for_timeout(300)
        dur = pg.evaluate("window.DUR")
        if mode == "stills":
            out = HERE / "stills"; out.mkdir(exist_ok=True)
            for t in sys.argv[4:]:
                pg.evaluate(f"seek({float(t)})")
                pg.screenshot(path=str(out / f"{pathlib.Path(page).stem}-{orient}_{float(t):05.2f}.jpg"), type="jpeg", quality=90)
        else:
            ff = subprocess.Popen(["ffmpeg","-y","-loglevel","error","-f","image2pipe","-c:v","mjpeg","-framerate",str(FPS),"-i","-",
                "-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-c:v","libx264","-preset","veryfast","-crf","17","-pix_fmt","yuv420p",
                "-profile:v","high","-movflags","+faststart","-c:a","aac","-b:a","128k","-shortest",sys.argv[4]], stdin=subprocess.PIPE)
            for i in range(int(FPS * dur)):
                pg.evaluate(f"seek({i / FPS})"); ff.stdin.write(pg.screenshot(type="jpeg", quality=93))
            ff.stdin.close(); ff.wait()
        b.close()
main()
