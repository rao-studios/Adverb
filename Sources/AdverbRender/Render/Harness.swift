//
//  Harness.swift
//  AdverbRender
//
//  WHAT: The script Adverb injects into every page before the page's own scripts run, and the
//        caption probe the renderer calls while it renders.
//  PIN:  The kit runs its own requestAnimationFrame loop unless `navigator.webdriver` is true
//        (Playwright sets it; WebKit does not). Left alone, that loop would seek the page to wall
//        time between Adverb's seeks. The harness makes webdriver true, sets `window.__ADVERB__`
//        (which kit.js also checks), stubs requestAnimationFrame, and turns CSS animations and
//        transitions off: every frame is `seek(t)` and nothing else.
//

import Foundation

enum Harness {
    static let documentStart = """
    (function(){
      try{Object.defineProperty(navigator,'webdriver',{get:function(){return true},configurable:true});}catch(e){}
      window.__ADVERB__={render:true,fps:30,errors:[]};
      window.requestAnimationFrame=function(){return 0};
      window.cancelAnimationFrame=function(){};
      window.addEventListener('error',function(e){window.__ADVERB__.errors.push(String(e.message||e))});
      document.addEventListener('DOMContentLoaded',function(){
        var s=document.createElement('style');
        s.textContent='*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}';
        document.head.appendChild(s);
      });
    })();
    """

    /// What the page is: its length, its scenes, whether the kit's faces loaded, what threw.
    static let probe = """
    (function(){
      var faces=['italic 108px "Instrument Serif"','108px "Instrument Serif"','36px "Newsreader"','italic 36px "Newsreader"','500 20px "JetBrains Mono"'];
      var fonts={};faces.forEach(function(f){fonts[f]=document.fonts.check(f)});
      return JSON.stringify({dur:Number(window.DUR||0),scenes:(window.SCENES||[]).map(Number),
        dpr:window.devicePixelRatio,fonts:fonts,errors:(window.__ADVERB__&&window.__ADVERB__.errors)||[],
        title:document.title||''});
    })()
    """

    static let ready = "(typeof window.seek==='function' && document.fonts.status==='loaded') ? 1 : 0"

    /// The text visible in #stage right now, element by element, in reading order. What a closed
    /// caption should say at this instant; folded into cues by CueTracker.
    static let cues = """
    (function(){
      var stage=document.getElementById('stage');if(!stage)return '[]';
      var W=stage.clientWidth,H=stage.clientHeight;
      var skip='#grain,#tex,.etex,.cursor,.brushes,svg,script,style';
      function visible(el){
        if(el.closest(skip))return false;
        var o=1,n=el;
        while(n&&n!==document.body){var cs=getComputedStyle(n);if(cs.display==='none'||cs.visibility==='hidden')return false;o*=parseFloat(cs.opacity||'1');n=n.parentElement;}
        if(o<0.6)return false;
        var r=el.getBoundingClientRect();
        return r.width>0&&r.height>0&&r.right>0&&r.bottom>0&&r.left<W&&r.top<H;
      }
      function kind(el){
        if(el.closest('#end'))return 'end';
        if(el.closest('#kicker'))return 'kicker';
        if(el.closest('.head'))return 'headline';
        if(el.closest('.chip'))return 'chip';
        if(el.closest('.code,.term,.src'))return 'code';
        return 'body';
      }
      // A block: the nearest ancestor that is a headline, a chip, a line, or a positioned box.
      function block(el){
        return el.closest('.head,#kicker,.chip,.ln,.para,#endT,#endS,#endS2,.mono,.abs,.card,.win,p,li,h1,h2,h3')||el.parentElement;
      }
      var out=[],seen=new Map();
      var walker=document.createTreeWalker(stage,NodeFilter.SHOW_TEXT,null);
      var node;
      while((node=walker.nextNode())){
        var text=node.nodeValue.replace(/\\s+/g,' ');
        var el=node.parentElement;if(!el)continue;
        // Whitespace between the kit's word spans: a space in whatever block is being built.
        if(!text.trim()){var wb=block(el);var wid=wb&&(wb.id||('b'+Array.prototype.indexOf.call(document.querySelectorAll('*'),wb)));if(wid&&seen.has(wid))seen.get(wid).text+=' ';continue;}
        if(!visible(el))continue;
        // A line break (<br>, or the end of a span before one) separates words too.
        var prev=node.previousSibling||(el.previousSibling);
        if(prev&&prev.nodeName==='BR')text=' '+text;
        var b=block(el);if(!b)continue;
        var id=b.id||('b'+Array.prototype.indexOf.call(document.querySelectorAll('*'),b));
        var r=b.getBoundingClientRect();
        if(!seen.has(id)){seen.set(id,{id:id,text:'',kind:kind(el),x:Math.round(r.left),y:Math.round(r.top)});out.push(seen.get(id));}
        seen.get(id).text+=text;
      }
      out.forEach(function(c){c.text=c.text.replace(/\\s+/g,' ').trim()});
      return JSON.stringify(out.filter(function(c){return c.text.length>0}));
    })()
    """
}
