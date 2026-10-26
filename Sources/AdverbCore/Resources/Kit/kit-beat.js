/* kit-beat.js — Adverb's beat helpers for beatmapped pages. Pure functions of t over static arrays
   written by Adverb beside the page (NN-topic.beats.js: window.BEATS, window.DOWNBEATS, window.BPM,
   window.BEAT_META), so every frame stays deterministic. Load after kit.js.
   Restraint: beatPulse may drive only the kicker coin (scale ≤ 1.06), the texture scale, chip swatch
   opacity and the end seal's settle; never headline text or layout. */
function beatIndex(t){const B=window.BEATS||[];let lo=0,hi=B.length-1,r=-1;while(lo<=hi){const m=(lo+hi)>>1;if(B[m]<=t){r=m;lo=m+1;}else hi=m-1;}return r;}
function beatPulse(t,width=.12){const B=window.BEATS||[],i=beatIndex(t);if(i<0)return 0;const d=t-B[i];return d>=width?0:1-eo(d/width);}
function beatPhase(t){const B=window.BEATS||[],i=beatIndex(t);return(i<0||i>=B.length-1)?0:(t-B[i])/(B[i+1]-B[i]);}
function nextDownbeat(t){const D=window.DOWNBEATS||[];for(const d of D){if(d>=t)return d;}return null;}
function prevDownbeat(t){const D=window.DOWNBEATS||[];let r=null;for(const d of D){if(d<=t)r=d;else break;}return r;}
function barPhase(t){const a=prevDownbeat(t),b=nextDownbeat(t+1e-6);return(a==null||b==null||b===a)?0:(t-a)/(b-a);}
function snapToBeat(t){const B=window.BEATS||[],i=beatIndex(t);if(!B.length)return t;if(i<0)return B[0];const n=B[i+1]??B[i];return(t-B[i]<=n-t)?B[i]:n;}
/* Accents boot() applies on its own when a page has beats: the texture breathes and the kicker coin
   taps on each beat. Called from kit.js's seek wrapper. */
function beatAccents(t){if(!(window.BEATS&&window.BEATS.length))return;const p=beatPulse(t,.14);
  const tex=document.getElementById('tex');if(tex)tex.style.transform+=` scale(${1+.01*p})`;
  const coin=document.querySelector('#kicker .coin');if(coin)coin.style.transform=`scale(${1+.05*p})`;}
