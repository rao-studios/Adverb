function lines(el,t,start,step=.14,dur=.3){[...el.querySelectorAll('.ln')].forEach((l,i)=>{const q=eo(seg(t,start+i*step,start+i*step+dur));l.style.opacity=q;l.style.transform=`translateX(${(1-q)*-14}px)`;});}
function mark(el,t,a,b){el.style.backgroundSize=`${eio(seg(t,a,b))*100}% 100%`;}
/* script: [{at, cmd:'...'} | {at, out:'html'}]; commands type at 28 chars/s */
function terminal(el,t,script){el.innerHTML=script.map((s,i)=>{if(s.cmd!==undefined){if(t<s.at)return '';const n=Math.round(clamp((t-s.at)*28/s.cmd.length)*s.cmd.length);const nxt=script[i+1];const caret=(t-s.at)*28<s.cmd.length+6&&(!nxt||t<nxt.at);
  return `<span class="ln"><span class="p">$</span> ${s.cmd.slice(0,n)}${caret?'<span style="display:inline-block;width:12px;height:1.1em;background:#E2C887;vertical-align:-.2em;margin-left:2px"></span>':''}</span>`;}
  return t>=s.at?`<span class="ln">${s.out}</span>`:'';}).join('');}
