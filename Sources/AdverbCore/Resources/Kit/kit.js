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
    if(typeof beatAccents==='function')beatAccents(t);
    const e=eoq(seg(t,endAt,endAt+.5)); const en=$('#end'); en.style.display=e>0?'':'none'; en.style.opacity=e;
    $('#endSeal').style.transform=`scale(${lerp(.88,1,e)})`;
    rise($('#endT'),t,endAt+.3,endAt+.75,26); rise($('#endS'),t,endAt+.5,endAt+.9,14); rise($('#endS2'),t,endAt+.65,endAt+1.05,12);
  };
  window.seek(0);
  if(!navigator.webdriver&&!window.__ADVERB__){let t0=performance.now();(function loop(){window.seek(((performance.now()-t0)/1000)%(o.dur+.5));requestAnimationFrame(loop);})();}
}
function ready(o){document.fonts.ready.then(()=>boot(o));}
