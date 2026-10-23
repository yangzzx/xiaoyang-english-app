(function(){
  'use strict';
  // Loaded only by the Android package, before the shared account and study scripts.
  if(!window.StudyAndroid)return;
  // Animate view changes once, not each cloud status update or keystroke.
  let reduced=typeof window.requestAnimationFrame!=='function'||(window.matchMedia&&window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    let entrance=null;
    window.matchMedia?.('(prefers-reduced-motion: reduce)').addEventListener?.('change',e=>{reduced=e.matches;if(reduced&&entrance)entrance.cancel()});
    const reveal=el=>{if(reduced||!el)return;if(entrance)entrance.cancel();el.classList.add('android-enter');entrance=el.animate([{opacity:.72},{opacity:1}],{duration:220,easing:'cubic-bezier(.22,1,.36,1)'});};
    document.documentElement.dataset.androidInput='touch';
    document.addEventListener('pointerdown',()=>{document.documentElement.dataset.androidInput='touch'},true);
    document.addEventListener('keydown',e=>{if(e.key==='Tab')document.documentElement.dataset.androidInput='keyboard'},true);
    const prepare=()=>{
      const names={phon:'国际音标',phonics:'自然拼读',root:'32 天词根词缀',mother:'秦天 58 组母词','500':'500 高频词汇',spell:'全能拼写',courses:'刘晓燕单词课',grammar:'刘晓燕语法课',papers:'真题精做',essay:'作文模板',review:'到期复习',plan:'学习计划'};
      const module=location.pathname.split('/').slice(-2,-1)[0],heading=document.querySelector('.en-hero h1');
      if(heading){const value=names[module]||'今日学习';if(heading.textContent!==value)heading.textContent=value;}
      const rootTitle=document.querySelector('.en-page-root .t1 .tt');if(rootTitle&&!rootTitle.dataset.androidTitle){const sub=rootTitle.querySelector('small');rootTitle.replaceChildren(document.createTextNode('32 天词根词缀'));if(sub)rootTitle.append(sub);rootTitle.dataset.androidTitle='1';}
      const tabs=document.querySelector('.en-page-root .en-content>.tabs'),page=document.querySelector('.en-page-root .en-content>.page');if(tabs&&page&&tabs.nextElementSibling!==page)page.before(tabs);
    };
    let scopeBackdrop=null;
    const ensureScopeBackdrop=()=>{
      if(scopeBackdrop?.isConnected)return scopeBackdrop;
      scopeBackdrop=document.createElement('button');scopeBackdrop.type='button';scopeBackdrop.className='android-scope-backdrop';scopeBackdrop.setAttribute('aria-label','关闭章节选择');scopeBackdrop.hidden=true;
      scopeBackdrop.addEventListener('click',()=>closeOpenScope());document.body.append(scopeBackdrop);return scopeBackdrop;
    };
    const syncScopeBody=()=>{
      const open=[...document.querySelectorAll('details.android-scope-picker[open]')].length>0;
      document.body.classList.toggle('android-scope-active',open);
      const backdrop=ensureScopeBackdrop();backdrop.hidden=!open;backdrop.classList.toggle('visible',open);
    };
    const closeOpenScope=()=>{
      const picker=document.querySelector('details.android-scope-picker[open]');if(!picker)return;
      picker.dataset.androidScopeClosing='1';
      window.setTimeout(()=>{picker.open=false;delete picker.dataset.androidScopeClosing;syncScopeBody()},190);
    };
    window.StudyAndroid.closeScopePicker=closeOpenScope;
    const enhanceScopePickers=()=>{
      for(const picker of document.querySelectorAll('details.v13-scope-picker:not([data-android-scope])')){
        picker.classList.add('android-scope-picker');picker.dataset.androidScope='1';
        const summary=picker.querySelector(':scope>summary');
        if(!summary)continue;
        summary.addEventListener('click',event=>{
          event.preventDefault();event.stopPropagation();
          if(picker.open){closeOpenScope();
          }else{
            picker.open=true;syncScopeBody();
          }
        });
      }
      syncScopeBody();
    };
    const setup=()=>{
      prepare();
      enhanceScopePickers();
      const content=document.getElementById('appView');
      if(content){
        let key='',pending=0,first=true;
        const changed=()=>{prepare();enhanceScopePickers();const next=location.pathname;if(key===next)return;key=next;const nativeEntry=first&&typeof StudyAndroid.ownsPageTransitions==='function'&&StudyAndroid.ownsPageTransitions();first=false;if(!reduced&&!nativeEntry){cancelAnimationFrame(pending);pending=requestAnimationFrame(()=>reveal(content))}};
        new MutationObserver(changed).observe(content,{childList:true});changed();
      }else if(typeof StudyAndroid.ownsPageTransitions!=='function')reveal(document.querySelector('.en-content .topbar'));
      if(!reduced)document.addEventListener('toggle',e=>{if(e.target.matches('details[open]')){const body=e.target.querySelector('.card-b');if(body){body.classList.remove('android-section-enter');requestAnimationFrame(()=>body.classList.add('android-section-enter'))}}},true);
    };
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',setup,{once:true});else setup();
  const synth={cancel(){},speak(u){StudyAndroid.speakText(String(u.text||''))}};
  try{Object.defineProperty(window,'speechSynthesis',{value:synth,configurable:true});Object.defineProperty(window,'SpeechSynthesisUtterance',{value:function(text){this.text=text},configurable:true})}catch(e){}
  document.addEventListener('click',async e=>{
    const a=e.target.closest('a[download]');if(!a||!a.href.startsWith('blob:'))return;
    e.preventDefault();e.stopImmediatePropagation();
    try{const response=await fetch(a.href),text=await response.text();JSON.parse(text);StudyAndroid.saveBackup(text,a.download||'个人学习备份.json')}
    catch(error){alert('备份没有导出成功，请重新尝试。')}
  },true);
})();
