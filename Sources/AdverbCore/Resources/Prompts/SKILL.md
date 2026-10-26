---
name: "rao-motion-assets"
description: "Make on-brand Rao motion assets (reels, intros, feature explainers, 15s/30s) for Ambient, AII, Craft, Veil or Rao, in the gold + platinum seal style; every asset ships as a portrait and a landscape version."
---

# Rao motion assets

Use this whenever the user asks for a video, reel, intro, explainer or social series for Rao Studios or any of its apps (Ambient, AII, Craft, Veil, or a new one). It fixes the brand, voice, layout, motion and accuracy rules, and ships the animation kit and renderer so every asset looks like part of one family.

**Every asset is delivered twice: one portrait (1080×1920) and one landscape (1920×1080) version, with the same copy, timing and story.** A request for "7 videos" means 7 topics × 2 orientations = 14 files. Only make a single orientation if the user explicitly asks for one.

Output is MP4 (H.264, 30 fps, silent AAC track so music can be added in-app) plus contact sheets. Each topic is one HTML page that lays itself out for either orientation, animated by a deterministic `seek(t)` and rendered frame by frame with Playwright + ffmpeg.

---

## 1. Brand system (do not deviate)

**Mood:** quiet, literate, premium, warm. Platinum paper, gold leaf, one wax seal. Never neon, never gradients-for-their-own-sake, never stock "AI" imagery (brains, circuits, robots, sparkles).

**Colour**
| Token | Value | Use |
|---|---|---|
| Platinum page | `#EFEEEA → #E2E1DC → #D3D2CC` (175° gradient) + liquid-platinum texture at 30% multiply | every background |
| Pearl card | `#FBFAF7 → #F1F0EC` | app surfaces, cards |
| Ink / ink-2 | `#1D1C1A` / `#64625C` | text |
| Gold | `#B8914A` (hi `#E2C887`, deep `#86652B`) | italic headline word, ticks, accents |
| Gold foil | `125deg #EED9A3 → #CFA85D → #A87F3B → #D9BB79 → #F1DFB0` | reserved for **Ambient Plus** / premium only |
| Brushstroke | `rgba(206,160,72,.45)` | the citation motif |
| App accents | Ambient = gold · Craft = night `#0B0D12` · Veil = deep teal `#2B4C53` · AII = gold index core | lane colours, app tiles |
| Code surfaces | night `#0E1015`; keywords `#C79BE0`, types `#8FB8E8`, strings `#E2C887`, numbers `#E9A178`, comments `#6B707C` | code cards, terminals |

No teal backgrounds. No orange. Teal appears only as Veil's accent.

**Type**
- Display: **Instrument Serif** (headlines; one *italic gold* phrase per headline).
- Body: **Newsreader** (reading text, answers, captions).
- System: **JetBrains Mono**, uppercase, letter-spaced (kickers, chips, dates, shortcuts, file names); also code and terminals (not uppercased).
- UI chrome: Inter / system sans (menu bars, buttons, inputs).

**Motifs (each has one meaning; never use them decoratively)**
- **Gold brushstroke** under a phrase = "this came from someone" (a source, a memory, an author). Draws left to right. Source chips appear after the stroke they cite. In code, the same idea is a soft gold marker sweep over the call being explained.
- **The seal** (RR on liquid platinum, soft radial fade) = Rao. Opens Rao-level pieces and closes every piece on the end card.
- **Gold coin/medallion** = Mary / Ambient (stand-in until the real medallion asset is supplied).
- **Lanes braiding into one gold core** = AII's shared index.
- **Platinum macOS desktop** (menubar, windows, cursor) = show the product in use, never a chat app.

**Layout**
- Portrait 1080×1920: 96 px side margins; kicker at y≈226; headline at y≈300 (≈108 px); visual stacked below from y≈600–680; keep the bottom 400 px free of key info (Reels UI).
- Landscape 1920×1080: headline left (x 120, width ≈760, ≈96 px, top ≈340); visual right (x ≈940–1820), vertically centred on the headline. Seal and end cards centred with even space above and below.
- Kicker (top-left): small coin + mono label, e.g. `AMBIENT, EXPLAINED`, `UNDER AMBIENT: AII`, `AII FOR MAC ENGINEERS`, `RAO STUDIOS`. **Never number assets** (no "01 / 16" tags) and **never add audience or level labels** (no "Junior / Mid / Senior") unless the user asks.

**Motion**
- Headlines rise in word by word (0.06 s stagger, ease-out quint).
- Scenes ≈2.5–7 s; one idea per scene; cross-fade with a slight upward drift.
- Cursor moves with ease-in-out, clicks with a tiny scale dip. Key caps press down 5 px. Code lines slide in one by one; terminal commands type at ≈28 chars/s.
- Texture drifts slowly the whole time. End card: platinum fade, seal scales 0.88→1, title, URL, tagline line.

---

## 2. Voice and copy

- Few words, more showing. Headlines of 2–7 words, split into a plain clause and an *italic gold payoff*: "Highlight *a line.*" "Every answer shows *where it came from.*"
- Lead with what the person does and feels; let the issue be implied. Show attribution, grounding and "you do the thinking" as outcomes; don't name problems like "AI psychosis" on screen.
- Ambient is not a chatbot. Lead with highlighting, reading along, speaking up at a natural pause, the ⌃A panel and Machine mode; chat is secondary.
- Core philosophy to return to: **personal, private, on-device, cited, credited**. AI plays a supporting role; the person learns on their own.
- For engineering audiences: real API names and commands from the docs, one concept per scene, a mono caption under the headline that explains the "why" in one or two lines. Let the series deepen naturally (setup → first use → data → streaming → security → internals) instead of labelling levels.
- End-card defaults: Ambient → `ambient.rao.nyc` / "Personal · private · cited · on your Mac"; AII → `github.com/rao-studios/AII` / "Open source · on-device · powers Ambient" (or "… · GPL-3.0" for developer pieces); Rao → `rao.nyc` / "Personal · private · cited · credited".

## 3. Accuracy rules (check before writing any scene)

1. **Fetch the source of truth first**: the app's site (ambient.rao.nyc, craft.rao.nyc, veil.rao.nyc, rao.nyc) and/or the repo README and docs (github.com/rao-studios/AII, including Docs/AII/README.md and Docs/AII/CLI.md for developer pieces). Only show features, shortcuts, API names, commands, ports, UI labels and limits stated there. Re-fetch each time: things change.
2. **Royalties**: unless the user confirms payments are live, frame citations as the receipt/groundwork ("Receipts are where *royalties begin*", "Every citation is a receipt"), never as money already paid.
3. **Veil** protects pixels, not likeness (per its site). Don't claim deepfake prevention unless the site does.
4. **Craft** and **Veil** are "Coming soon" until their sites say otherwise; label them so.
5. Demo content (notes, dates, memory counts, questions, ledger figures, terminal output) is illustrative. Use **fictional names only**, never real people (including photographers credited on the sites).
6. Avoid absolute claims the docs don't make ("works offline", "every feature free", "nothing kept anywhere"). Prefer the docs' own wording ("nothing has to leave the machine", "stays on this Mac"). State security limits honestly when the docs do (e.g. lanes separate apps' mistakes, not malicious code).
7. Don't explain API members the docs only name (show them by name).
8. In the final message, list what is illustrative and anything you softened.

---

## 4. Process

1. **Scope.** Confirm or infer: app(s), number of topics, 15 s or 30 s per topic, and the topic list. Orientation is not a choice: every topic gets a portrait and a landscape version. For a series, plan a gradual arc (premise → individual features → foundation → mission/finale), vary durations, and send the plan table (topic · length · what it shows) before building. Ask only if a wrong guess would be expensive.
2. **Research** the sites/README/docs (section 3).
3. **Set up the kit** (section 5) in a working folder. If the seal image isn't available, ask the user to attach it (RR mark on liquid platinum); generate `assets/rao-tex.jpg` from it (1080 px, Gaussian blur 28) for the background texture.
4. **Build each topic once** as a dual-orientation page (section 6), using the scene recipes (section 7).
5. **Check stills in both orientations before rendering**: `stills P` and `stills L` at 3–5 key times, into one sheet. Fix overlaps, empty halves, overflowing code lines, text under the Reels UI, unreadable sizes, and anything a scene hides that it should reveal. Portrait usually needs larger type and stacked visuals; landscape usually needs visuals pulled down to sit level with the headline.
6. **Render** both orientations of each topic (JPEG frame pipe; about 1 min per 15 s per orientation on 2 cores). Long batches go in the background.
7. **Verify**: ffprobe durations for every file, pull a few frames from the MP4s, build contact sheets (section 8).
8. **Deliver** in batches as topics finish, sending each topic's portrait and landscape files together, then the overview and per-topic sheets. Summarise each topic in a line and list the illustrative / softened items.

Naming: `NN-topic-portrait.mp4` and `NN-topic-landscape.mp4` (NN only orders the files; it never appears on screen).

---

## 5. Kit setup

```
work/
  fonts/   instrument-serif-latin-400-{normal,italic}.woff2, newsreader-latin-400-{normal,italic}.woff2, jetbrains-mono-latin-{400,500}-normal.woff2
  assets/  rao-hero.png (seal), rao-tex.jpg (blurred texture)
  kit.css  kit.js  render.py  sheets.py   (+ dev.css for code/terminal pieces)
  01-topic.html …
```

Fonts come from npm: `npm pack @fontsource/instrument-serif @fontsource/newsreader @fontsource/jetbrains-mono`, then copy the latin woff2 files above from each `package/files/`. The machine needs Playwright's Chromium and ffmpeg.

### kit.css
```css
@font-face{font-family:"Instrument Serif";src:url(fonts/instrument-serif-latin-400-normal.woff2)format("woff2");font-style:normal}
@font-face{font-family:"Instrument Serif";src:url(fonts/instrument-serif-latin-400-italic.woff2)format("woff2");font-style:italic}
@font-face{font-family:"Newsreader";src:url(fonts/newsreader-latin-400-normal.woff2)format("woff2");font-weight:400}
@font-face{font-family:"Newsreader";src:url(fonts/newsreader-latin-400-italic.woff2)format("woff2");font-weight:400;font-style:italic}
@font-face{font-family:"JetBrains Mono";src:url(fonts/jetbrains-mono-latin-400-normal.woff2)format("woff2");font-weight:400}
@font-face{font-family:"JetBrains Mono";src:url(fonts/jetbrains-mono-latin-500-normal.woff2)format("woff2");font-weight:500}
:root{
  --plat-0:#F7F6F3; --plat-1:#ECEBE7; --plat-2:#DDDCD7; --plat-3:#C4C3BD; --plat-4:#8F8E88;
  --ink:#1D1C1A; --ink-2:#64625C; --rule:rgba(29,28,26,.11);
  --gold:#B8914A; --gold-hi:#E2C887; --gold-deep:#86652B; --brush:rgba(206,160,72,.45);
  --foil:linear-gradient(125deg,#EED9A3 0%,#CFA85D 28%,#A87F3B 52%,#D9BB79 74%,#F1DFB0 100%);
  --night:#0E1015; --craft:#0B0D12; --veil:#2B4C53;
  --display:"Instrument Serif",serif; --body:"Newsreader",serif; --mono:"JetBrains Mono",monospace; --ui:"Inter",system-ui,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
body.P{--W:1080px;--H:1920px} body.L{--W:1920px;--H:1080px}
html,body{width:var(--W);height:var(--H);overflow:hidden}
#stage{position:relative;width:var(--W);height:var(--H);overflow:hidden;color:var(--ink);font-family:var(--body);background:linear-gradient(175deg,#EFEEEA 0%,#E2E1DC 55%,#D3D2CC 100%)}
#tex,.etex{position:absolute;width:1920px;height:1920px;background:url(assets/rao-tex.jpg) center/cover;opacity:.3;mix-blend-mode:multiply}
body.P #tex,body.P .etex{left:-420px;top:0} body.L #tex,body.L .etex{left:0;top:-420px}
#grain{position:absolute;inset:0;pointer-events:none;opacity:.2;mix-blend-mode:multiply;z-index:90}
.abs{position:absolute}
.scene{position:absolute;left:0;top:0;width:var(--W);height:var(--H)}
.mono{font-family:var(--mono);text-transform:uppercase;letter-spacing:.16em;font-size:20px;font-weight:500}
.disp{font-family:var(--display);letter-spacing:-.01em;font-weight:400}
.disp em,.head em{font-style:italic;color:var(--gold)}
.head{position:absolute;font-family:var(--display);letter-spacing:-.01em;line-height:.98}
body.P .head{left:96px;top:300px;width:900px;font-size:108px}
body.L .head{left:120px;top:340px;width:760px;font-size:96px}
.w{display:inline-block}
#kicker{position:absolute;display:flex;align-items:center;gap:16px;z-index:80}
body.P #kicker{left:96px;top:226px} body.L #kicker{left:120px;top:80px}
.card{border-radius:30px;box-shadow:inset 0 1px 0 rgba(255,255,255,.7),0 0 0 1px rgba(29,28,26,.08),0 44px 80px -36px rgba(50,48,42,.55)}
.pearl{background:linear-gradient(180deg,#FBFAF7,#F1F0EC)}
.gold-edge{box-shadow:inset 0 1px 0 #fff,0 0 0 1.5px rgba(184,145,74,.55),0 34px 60px -24px rgba(90,70,30,.45)}
.dark{background:var(--night);color:#E8E6E0}
.foil{background:var(--foil);color:#2A2010}
.chip{display:inline-flex;align-items:center;gap:10px;padding:10px 16px;border-radius:11px;border:1px solid var(--rule);font-family:var(--mono);font-size:17px;letter-spacing:.12em;text-transform:uppercase;color:var(--ink-2);font-weight:500;white-space:nowrap;background:rgba(255,255,255,.55)}
.chip .sw{width:24px;height:11px;border-radius:3px;background:rgba(206,160,72,.6)}
.dark .chip{background:rgba(255,255,255,.05);border-color:rgba(255,255,255,.14);color:#A9ACB6}
.coin{display:inline-block;border-radius:50%;background:radial-gradient(circle at 35% 30%,#F3DEA8 0%,#C99F55 45%,#8A6630 100%);box-shadow:inset 0 0 0 2px rgba(255,240,200,.4),0 1px 2px rgba(0,0,0,.2);position:relative;flex:none}
.coin::after{content:"";position:absolute;inset:26%;border-radius:50%;border:2px solid rgba(90,62,22,.42)}
.key{display:inline-flex;align-items:center;justify-content:center;min-width:84px;height:84px;padding:0 20px;border-radius:18px;background:var(--plat-0);border:1px solid var(--rule);box-shadow:0 5px 0 rgba(29,28,26,.2);font-family:var(--ui);font-size:40px;font-weight:500;color:var(--ink)}
.hl{position:relative;z-index:1}
.brushes{position:absolute;inset:0;z-index:0;pointer-events:none}
.para{font-size:36px;line-height:1.5}
.desk{position:absolute;border-radius:30px;overflow:hidden;background:radial-gradient(90% 60% at 85% 0%,rgba(226,200,135,.45),transparent 60%),linear-gradient(165deg,#E9E8E3 0%,#D6D5CF 55%,#C3C2BB 100%);box-shadow:inset 0 1px 0 #fff,0 0 0 1px rgba(29,28,26,.08),0 50px 90px -40px rgba(70,64,52,.5)}
.menubar{position:absolute;left:0;top:0;right:0;height:48px;background:rgba(255,255,255,.5);display:flex;align-items:center;padding:0 24px;font-family:var(--ui);font-size:20px;color:var(--ink);gap:26px;border-bottom:1px solid rgba(29,28,26,.06)}
.menubar b{font-weight:600} .menubar .r{margin-left:auto;display:flex;align-items:center;gap:20px}
.win{position:absolute;background:var(--plat-0);border-radius:16px;box-shadow:0 30px 60px -25px rgba(60,54,40,.45),0 0 0 1px rgba(0,0,0,.07);overflow:hidden}
.tbar{height:44px;display:flex;align-items:center;gap:9px;padding:0 18px;border-bottom:1px solid var(--rule);font-family:var(--ui);font-size:17px;color:var(--ink-2)}
.tl{width:12px;height:12px;border-radius:50%;background:#D5D4CE}
.cursor{position:absolute;left:0;top:0;z-index:50}
.seal{position:absolute;background:url(assets/rao-hero.png) center/cover;-webkit-mask-image:radial-gradient(circle at 50% 50%,#000 44%,transparent 70%);mask-image:radial-gradient(circle at 50% 50%,#000 44%,transparent 70%)}
/* orientation helpers: show an element only in one orientation */
body.P .only-L, body.L .only-P{display:none !important}
```

### kit.js
```js
/* orientation override from the URL (?o=P or ?o=L), applied before anything measures the page */
(()=>{const o=new URLSearchParams(location.search).get('o');if(o==='P'||o==='L'){document.body.classList.remove('P','L');document.body.classList.add(o);}})();
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const clamp=(v,a=0,b=1)=>Math.min(b,Math.max(a,v)), seg=(t,a,b)=>clamp((t-a)/(b-a));
const eo=x=>1-Math.pow(1-x,3), eoq=x=>1-Math.pow(1-x,5), eio=x=>x<.5?4*x*x*x:1-Math.pow(-2*x+2,3)/2, lerp=(a,b,p)=>a+(b-a)*p;
const IS_P=document.body.classList.contains('P');
const PL=(p,l)=>IS_P?p:l;   /* pick a value per orientation, e.g. PL([880,1700],[1700,900]) */
function brushPath(w,h,seed){let r=(s=>()=>(s=(s*16807)%2147483647)/2147483647)(seed);const n=14,top=[],bot=[];
  for(let i=0;i<=n;i++){const x=i/n*w;top.push([x+(r()-.5)*6,h*.16+(r()-.5)*h*.16]);bot.push([x+(r()-.5)*6,h*.9+(r()-.5)*h*.14]);}
  top[0][0]=-6;bot[0][0]=-2;top[n][0]=w+4;bot[n][0]=w+8;let d=`M${top[0][0]},${top[0][1]}`;top.slice(1).forEach(p=>d+=` L${p[0].toFixed(1)},${p[1].toFixed(1)}`);
  d+=` Q${w+16},${h*.5} ${bot[n][0]},${bot[n][1]}`;bot.slice().reverse().forEach(p=>d+=` L${p[0].toFixed(1)},${p[1].toFixed(1)}`);return d+` Q-14,${h*.5} ${top[0][0]},${top[0][1]} Z`;}
/* brushstrokes under inline spans: <div class="brushes" data-for="id1 id2" data-color="c1|c2"></div> placed first inside the paragraph */
const brushSegs={};
function layBrushes(){$$('.brushes').forEach(layer=>{
  const hidden=[];let p=layer;while(p&&p!==document.body){if(getComputedStyle(p).display==='none'){hidden.push([p,p.style.display]);p.style.display='block';}p=p.parentElement;}
  const host=layer.parentElement.getBoundingClientRect();const cols=(layer.dataset.color||'rgba(206,160,72,.45)').split('|');
  layer.dataset.for.split(' ').forEach((id,k)=>{const rects=[...$('#'+id).getClientRects()];brushSegs[id]=[];const total=rects.reduce((s,r)=>s+r.width,0);let acc=0;
    rects.forEach((rc,i)=>{const w=rc.width+10,h=rc.height*.7,x=rc.left-host.left-5,y=rc.top-host.top+rc.height*.2;
      const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('width',w);svg.setAttribute('height',h);svg.style.cssText=`position:absolute;left:${x}px;top:${y}px;overflow:visible`;
      svg.innerHTML=`<path d="${brushPath(w,h,11+i*7+k*31)}" fill="${cols[k%cols.length]}"/>`;layer.appendChild(svg);brushSegs[id].push({el:svg,from:acc/total,to:(acc+rc.width)/total,x,y,w,h});acc+=rc.width;});});
  hidden.forEach(([el,d])=>el.style.display=d);});}
function setBrush(id,p){(brushSegs[id]||[]).forEach(s=>{const q=clamp((p-s.from)/(s.to-s.from));s.el.style.clipPath=`inset(-20% ${(1-q)*100+.01}% -20% -5%)`;s.el.style.opacity=q>0?1:0;});}
function underBrush(el,h=26,seed=77,color='rgba(206,160,72,.55)'){const w=el.getBoundingClientRect().width;const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.setAttribute('width',w+12);svg.setAttribute('height',h);svg.style.cssText=`position:absolute;left:-6px;bottom:${-h*.8}px;overflow:visible`;svg.innerHTML=`<path d="${brushPath(w+12,h,seed)}" fill="${color}"/>`;
  if(getComputedStyle(el).position==='static')el.style.position='relative';el.appendChild(svg);return svg;}
function wipe(svg,p){svg.style.clipPath=`inset(-50% ${(1-p)*100}% -50% -5%)`;}
function splitWords(el){const walk=n=>[...n.childNodes].forEach(c=>{
  if(c.nodeType===3){const f=document.createDocumentFragment();c.textContent.split(/(\s+)/).forEach(tok=>{if(!tok)return;if(/^\s+$/.test(tok)){f.appendChild(document.createTextNode(tok));return;}const s=document.createElement('span');s.className='w';s.textContent=tok;f.appendChild(s);});c.replaceWith(f);}
  else if(c.nodeType===1&&c.tagName!=='BR'&&!c.classList.contains('w')&&c.tagName!=='svg')walk(c);});walk(el);}
function headline(el,t,tin,tout=999,step=.06){[...el.querySelectorAll('.w')].forEach((w,i)=>{const p=eoq(seg(t,tin+i*step,tin+i*step+.55)),o=eio(seg(t,tout,tout+.3));w.style.opacity=p*(1-o);w.style.transform=`translateY(${(1-p)*46-o*30}px)`;});el.style.display=(t>=tin-.05&&t<=tout+.35)?'':'none';}
function show(el,o,y=0,sc=1){el.style.opacity=o;el.style.transform=`translateY(${y}px) scale(${sc})`;el.style.display=o<=.001?'none':'';}
function rise(el,t,a,b,d=40){const p=eoq(seg(t,a,b));el.style.opacity=p;el.style.transform=`translateY(${(1-p)*d}px)`;return p;}
function slideX(el,t,a,b,d=-40){const p=eoq(seg(t,a,b));el.style.opacity=p;el.style.transform=`translateX(${(1-p)*d}px)`;return p;}
function scene(el,t,a,b,fin=.3,fout=.3,dy=50){const i=seg(t,a,a+fin),o=eio(seg(t,b-fout,b));show(el,i*(1-o),-o*dy);return i*(1-o);}
function typeText(el,txt,p,caret,col='#B8914A'){el.innerHTML=txt.slice(0,Math.round(txt.length*p))+(caret?`<span style="display:inline-block;width:3px;height:1em;background:${col};vertical-align:-.12em;margin-left:2px"></span>`:'');}
function karaoke(el){el.innerHTML=el.textContent.split(' ').map(w=>`<span class="kw">${w}</span>`).join(' ');return [...el.querySelectorAll('.kw')];}
function setKaraoke(ws,p,on='#1D1C1A',off='rgba(29,28,26,.25)'){ws.forEach((w,i)=>w.style.color=p*ws.length>i?on:off);}
function waveSVG(el,n=24,col='#B8914A',gap=7.3){let h='';for(let i=0;i<n;i++)h+=`<rect x="${i*gap}" width="4" rx="2" fill="${col}"/>`;el.innerHTML=h;}
function wave(el,t,amp,H=38){[...el.children].forEach((r,i)=>{const v=amp*(.25+.75*Math.abs(Math.sin(t*9+i*.7)*Math.sin(t*4.3+i*1.9)));const h=Math.max(4,v*H);r.setAttribute('height',h);r.setAttribute('y',H/2+1-h/2);});}
const CURSOR='<svg width="34" height="46" viewBox="0 0 17 23"><path d="M1 1 L1 18 L5.5 13.8 L8.6 21 L11.4 19.8 L8.4 12.8 L14.6 12.8 Z" fill="#111" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
const TICK='<svg width="18" height="18" viewBox="0 0 16 16"><path d="M3 8.5 L6.5 12 L13 4.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
/* boot: texture, grain, kicker, end card; wraps the page's seek */
function boot(o){
  const st=$('#stage');
  st.insertAdjacentHTML('afterbegin','<div id="tex"></div>');
  st.insertAdjacentHTML('beforeend',`<svg id="grain" width="100%" height="100%"><filter id="gF"><feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="9"/><feColorMatrix values="0 0 0 0 .32  0 0 0 0 .31  0 0 0 0 .3  0 0 0 .5 0"/></filter><rect width="100%" height="100%" filter="url(#gF)"/></svg>`);
  st.insertAdjacentHTML('beforeend',`<div id="kicker" class="mono"><span class="coin" style="width:22px;height:22px"></span>${o.kicker||'Ambient, explained'}</div>`);
  const E=IS_P?{seal:[240,500,600],t:1090,ts:118,s:1235,s2:1285}:{seal:[680,150,560],t:680,ts:110,s:830,s2:878};
  st.insertAdjacentHTML('beforeend',`<div id="end" class="scene" style="background:linear-gradient(175deg,#EFEEEA 0%,#E2E1DC 55%,#D3D2CC 100%);z-index:70"><div class="etex"></div>
    <div class="seal" id="endSeal" style="left:${E.seal[0]}px;top:${E.seal[1]}px;width:${E.seal[2]}px;height:${E.seal[2]}px"></div>
    <div id="endT" class="abs disp" style="left:0;width:100%;text-align:center;top:${E.t}px;font-size:${E.ts}px;line-height:1">${o.endTitle||'Ambient'}</div>
    <div id="endS" class="abs mono" style="left:0;width:100%;text-align:center;top:${E.s}px;font-size:22px">${o.endSub||'ambient.rao.nyc'}</div>
    <div id="endS2" class="abs mono" style="left:0;width:100%;text-align:center;top:${E.s2}px;font-size:18px;color:#64625C">${o.endSub2||'Personal · private · cited · on your Mac'}</div></div>`);
  $$('.head,.split').forEach(splitWords);
  if(o.setup)o.setup();
  layBrushes();
  const endAt=o.endAt??(o.dur-1.6);
  window.seek=t=>{
    $('#tex').style.transform=`translate(${Math.sin(t*.12)*40}px,${Math.cos(t*.1)*30}px) scale(${1.05+.03*Math.sin(t*.15)})`;
    show($('#kicker'),eo(seg(t,0,.4))*(1-seg(t,endAt,endAt+.25)));
    o.seek(t);
    const e=eoq(seg(t,endAt,endAt+.5)); const en=$('#end'); en.style.display=e>0?'':'none'; en.style.opacity=e;
    $('#endSeal').style.transform=`scale(${lerp(.88,1,e)})`;
    rise($('#endT'),t,endAt+.3,endAt+.75,26); rise($('#endS'),t,endAt+.5,endAt+.9,14); rise($('#endS2'),t,endAt+.65,endAt+1.05,12);
  };
  window.seek(0);
  if(!navigator.webdriver){let t0=performance.now();(function loop(){window.seek(((performance.now()-t0)/1000)%(o.dur+.5));requestAnimationFrame(loop);})();}
}
function ready(o){document.fonts.ready.then(()=>boot(o));}
```

### render.py
```python
"""python render.py page.html P|L video out.mp4
   python render.py page.html P|L stills t1 t2 ...   -> stills/<page>-<P|L>_<t>.jpg
Duration from window.DUR. Orientation is forced with ?o=P|L."""
import sys, subprocess, pathlib, glob, os
from playwright.sync_api import sync_playwright
HERE = pathlib.Path(__file__).parent.resolve(); FPS = 30
def chrome():
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
```

Render both versions of a topic:
```
for o in P L; do n=$([ $o = P ] && echo portrait || echo landscape); python3 render.py 01-topic.html $o video 01-topic-$n.mp4; done
```

---

## 6. Dual-orientation page template

One file per topic. Shared markup and timeline; layout lives in `body.P` / `body.L` CSS rules; any coordinates used in JS come from `PL(portraitValue, landscapeValue)` or are measured from the DOM in `setup()`. Default to `class="P"` in the file; the renderer switches it with `?o=`.

```html
<!doctype html><html><head><meta charset="utf-8"><title>Topic</title><link rel="stylesheet" href="kit.css">
<style>
  /* portrait: visual stacked under the headline */
  body.P #card{left:96px;top:640px;width:888px}
  body.P .para{font-size:40px}
  /* landscape: visual on the right, level with the headline */
  body.L #card{left:960px;top:300px;width:840px}
  body.L .para{font-size:34px}
</style></head>
<body class="P"><div id="stage">
  <div id="h1" class="head">Highlight <em>a line.</em></div>
  <div id="h2" class="head">No chat box. <em>No prompt.</em></div>
  <div id="card" class="abs pearl gold-edge" style="border-radius:24px;padding:28px 32px">
    <div class="para" style="position:relative"><div class="brushes" data-for="s1"></div>
      <span class="hl">Morrow kept the colour because it </span><span class="hl" id="s1">stays visible in fog</span><span class="hl">.</span></div>
    <span class="chip" id="c1"><span class="sw"></span>The Bridge in the Fog</span>
  </div>
  <div class="abs mono only-L" style="left:120px;top:600px">An extra caption only landscape has room for</div>
</div>
<script src="kit.js"></script>
<script>
window.DUR=15;
ready({dur:15,endAt:13.4,kicker:'Ambient, explained',endTitle:'Ambient',endSub:'ambient.rao.nyc',
  setup(){ /* build dynamic DOM; measure and cache positions here (per orientation) */ },
  seek(t){
    headline($('#h1'),t,.15,6.0); headline($('#h2'),t,6.35,13.3);
    const c=eoq(seg(t,.8,1.3)); show($('#card'),c*(1-seg(t,13.2,13.4)),(1-c)*50);
    setBrush('s1',eio(seg(t,2.0,2.7))); rise($('#c1'),t,2.6,3.0,14);
    const cursorStart=PL([880,1700],[1700,900]);   /* orientation-specific coordinates */
  }});
</script></body></html>
```

Rules for pages:
- Everything is a pure function of `t`; no timers, no `Math.random()` (use seeded paths).
- Same copy and same timeline in both orientations. Layout, type size and extra captions may differ; the story may not.
- Measure layout (cursor targets, brushed spans) in `setup()`, while elements are visible, then cache it. Calling `getClientRects()` on a hidden element inside `seek` crashes the render.
- 15 s: three or four beats plus end card at 13.4 s. 30 s: four or five beats plus end card at 28.4 s.
- Inline dark surfaces need an explicit background (`.box`-style white rules can override `.dark`).
- Portrait code: keep lines ≤ ~40 characters at 26–30 px (break long calls across lines). Landscape code: ≤ ~62 characters at 21–22 px in an ≈880 px card.

## 7. Scene recipes (reuse; vary the combination per topic)

- **Premise words**: 3–4 large words stacked, each with its own brushstroke and a one-line subline (Personal / Private / Cited / Credited). Landscape: words in one or two rows.
- **Desktop highlight**: platinum desktop + Reader/Preview window; cursor drags along a phrase; brushstroke follows; a "hold still" ring; menubar coin pulses; Mary card drops from the menubar.
- **Speaks up**: the Mary card with a gold waveform; words light karaoke-style; Mute variant shows the same card without the waveform.
- **⌃A panel**: key caps press; the desktop dims slightly; the panel opens below the window's content (never covering what it's reading); question types; answer with a brushed phrase; footer "Reading “Title”, in App".
- **Sources**: an answer with numbered strokes; the cursor taps a stroke and the source card swaps in, with the same phrase brushed; legend for stroke vs. no stroke.
- **Day timeline**: time label + app window per moment; Mary connects later moments to earlier ones; a recap of mini cards linked by gold threads.
- **Settings / privacy**: toggles turning gold; a lock badge "Never read" over password fields; a reading sheen passing over content.
- **On-device**: first-launch choice, a one-time download bar, a Mac outline holding Replies / Speech / Memory chips with the network line cut.
- **Plus upsell**: free features ticked first, then the gold foil Plus card with a light sweep; "Sign out any time" returns to on-device.
- **AII index**: entities brushed in a document, then a knowledge graph forms; a question lights a subgraph gold; ranked results each show a trace ("via X → Y").
- **AII lanes**: app lanes (gold / night / teal / dashed "Your app") braid into the gold core at `~/.rao`; keys per lane; a "Refused · not your lane" stamp; a Swift join snippet; the GPL-3.0 repo card. Portrait: lanes run top → bottom; landscape: left → right.
- **Memory**: a chat collapses into Summary / Resonant passage / Running recap docs; next-time recall with a memory chip; passage-weight bars; a model chip with a gold "your layer" ring and lock.
- **Finale / royalties**: an answer with author-named chips → a "who you learned from" ledger with counts and share bars (illustrative, fictional names) → callback words → the seal.
- **Code card** (developer pieces): night card with a title bar (three dots + file name), syntax colours from section 1, lines sliding in one by one, a gold marker sweep over the call being explained, and a one-line mono caption beside/below it.
- **Terminal**: night card titled "Terminal — zsh"; `$` prompt in grey, commands typing with a gold caret, outputs appearing line by line with gold ✓ ticks; `aii status` / `aii doctor` style checks.
- **Architecture**: white node cards (name in display serif, role in mono) joined by gold lines labelled with real ports from the docs; dashed grey lines for HTTP edges.

Code/terminal helpers (`dev.css` + `dev.js`) for developer pieces:
```css
.code,.term{position:absolute;border-radius:24px;background:#0E1015;color:#E6E4DE;box-shadow:0 0 0 1px rgba(0,0,0,.2),0 44px 80px -36px rgba(30,28,24,.7);overflow:hidden}
.code .bar,.term .bar{display:flex;align-items:center;gap:9px;padding:16px 22px;border-bottom:1px solid rgba(255,255,255,.07)}
.code .bar i,.term .bar i{width:12px;height:12px;border-radius:50%;background:#2A2D35}
.code .bar span,.term .bar span{margin-left:12px;font-family:var(--mono);font-size:15px;letter-spacing:.12em;text-transform:uppercase;color:#7C808C}
.src{font-family:var(--mono);font-size:22px;line-height:1.75;padding:22px 30px 26px;white-space:pre;position:relative}
.ln{display:block;min-height:1.75em}
.k{color:#C79BE0}.t{color:#8FB8E8}.s{color:#E2C887}.c{color:#6B707C}.n{color:#E9A178}.p{color:#9E9D97}.ok{color:#E2C887}.dim{color:#7C808C}
.gmark{background-image:linear-gradient(transparent 12%,rgba(206,160,72,.34) 12%,rgba(206,160,72,.34) 92%,transparent 92%);background-repeat:no-repeat;background-size:0% 100%;border-radius:3px}
```
```js
function lines(el,t,start,step=.14,dur=.3){[...el.querySelectorAll('.ln')].forEach((l,i)=>{const q=eo(seg(t,start+i*step,start+i*step+dur));l.style.opacity=q;l.style.transform=`translateX(${(1-q)*-14}px)`;});}
function mark(el,t,a,b){el.style.backgroundSize=`${eio(seg(t,a,b))*100}% 100%`;}
/* script: [{at, cmd:'...'} | {at, out:'html'}]; commands type at 28 chars/s */
function terminal(el,t,script){el.innerHTML=script.map((s,i)=>{if(s.cmd!==undefined){if(t<s.at)return '';const n=Math.round(clamp((t-s.at)*28/s.cmd.length)*s.cmd.length);const nxt=script[i+1];const caret=(t-s.at)*28<s.cmd.length+6&&(!nxt||t<nxt.at);
  return `<span class="ln"><span class="p">$</span> ${s.cmd.slice(0,n)}${caret?'<span style="display:inline-block;width:12px;height:1.1em;background:#E2C887;vertical-align:-.2em;margin-left:2px"></span>':''}</span>`;}
  return t>=s.at?`<span class="ln">${s.out}</span>`:'';}).join('');}
```

## 8. Contact sheets (sheets.py)

For each topic, one sheet with both versions: pull frames at 18 / 42 / 66 / 97 % of each MP4 with ffmpeg; put the portrait frames in a row at 270×480 on the left and the landscape frames in a 2×2 grid at 480×270 on the right. Add a header with "name · length · portrait + landscape" and a time label on each frame. Also build `00-series-overview.jpg`: one mid frame per file in a 4-column grid, letterboxed into equal cells, with names under each.

## 9. Final message

One line per topic (length · what it shows), noting it was delivered in portrait and landscape; the files; then a short list of what's illustrative or softened for accuracy. No closing flourish.