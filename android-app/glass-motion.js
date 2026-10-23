// Short interactions for study state changes; no perpetual background animation.
(function(){
 'use strict';
 if(window.StudyAndroid){
  document.documentElement.classList.add('study-edge');
  document.documentElement.style.setProperty('--study-safe-top',(StudyAndroid.statusInset?.()||0)+'px');
  document.documentElement.style.setProperty('--study-safe-bottom',(StudyAndroid.bottomInset?.()||0)+'px');
 }
 const media=window.matchMedia?.('(prefers-reduced-motion: reduce)');
 function enabled(){return !media?.matches&&(!window.StudyAndroid?.motionEnabled||StudyAndroid.motionEnabled());}
 let running=null;
 function enter(node,kind){
  if(!node||!enabled()||!node.animate)return;
  running?.cancel();
  running=node.animate([{opacity:.65,transform:'translateY('+(kind==='answer'?6:10)+'px)'},{opacity:1,transform:'translateY(0)'}],{duration:kind==='answer'?180:230,easing:'cubic-bezier(.22,1,.36,1)'});
 }
 function syncMotion(){document.documentElement.classList.toggle('study-motion-off',!enabled());if(!enabled())running?.cancel();}
 media?.addEventListener?.('change',syncMotion);window.addEventListener('focus',syncMotion);
 function setup(){
  syncMotion();const root=document.getElementById('appView');
  if(root){let previous='',started=false,frame=0;
   const changed=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{
    const session=root.querySelector('.v14-session'),answer=session?.querySelector('.v14-answer');
    const panel=root.querySelector('.android-review-tabs button.active')?.dataset.panel||'';
    const fingerprint=location.search+'|'+panel+'|'+(session?(session.querySelector('.v14-word,h2')?.textContent||'')+'|'+(session.querySelector('.v14-session-head')?.textContent||'')+'|'+!!answer:root.querySelector('.android-review-result,.v14-finished')?.textContent||'list');
    if(fingerprint===previous)return;const before=previous;previous=fingerprint;
    if(started){const reveal=answer&&before.endsWith('|false');enter(reveal?answer:session||root.querySelector('.android-review-overview,.android-spell-review,.v14-manage,.android-review-result,.v14-finished')||root,reveal?'answer':'view');}
    started=true;
   });};
   new MutationObserver(changed).observe(root,{childList:true});changed();
  }
  document.addEventListener('toggle',e=>{const d=e.target;if(!d.matches?.('details[open]'))return;enter(d.querySelector(':scope>.android-progress-chapters,:scope>.android-manage-chapter,:scope>.android-manage-row,:scope>p,:scope>.card-b'),'answer');},true);
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',setup,{once:true});else setup();
})();
