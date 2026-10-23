(function(){
 'use strict';
 if(!window.StudyAndroid)return;
 let active=null;
 const selectable=e=>e.target instanceof HTMLSelectElement&&!e.target.disabled&&!e.target.multiple;
 function open(source,keyboard=false){
  if(active?.open)return;
  const route=location.href,index=[...document.querySelectorAll('select')].indexOf(source);
  const resolve=()=>{if(location.href!==route)return null;if(source.isConnected)return source;const list=[...document.querySelectorAll('select')];return list.find(s=>source.id&&s.id===source.id)||list.find(s=>source.name&&s.name===source.name)||list.find(s=>source.dataset.act&&s.dataset.act===source.dataset.act)||list[index]};
  const element=(tag,cls,text)=>{const e=document.createElement(tag);e.className=cls;if(text!==undefined)e.textContent=text;return e};
  const dialog=element('dialog','android-select-dialog');active=dialog;
  const motion=()=>!matchMedia('(prefers-reduced-motion: reduce)').matches;
  const nativeClose=dialog.close.bind(dialog);let closing=false;
  dialog.close=()=>{
   if(closing)return;closing=true;
   if(!motion()||!dialog.animate){nativeClose();return;}
   dialog.classList.add('closing');dialog.getAnimations().forEach(a=>a.cancel());
   const out=dialog.animate([{transform:'translate3d(0,0,0)',opacity:1},{transform:'translate3d(0,100%,0)',opacity:1}],{duration:230,easing:'cubic-bezier(.4,0,1,1)',fill:'forwards'});
   out.finished.then(nativeClose, nativeClose);
  };
  dialog.addEventListener('cancel',e=>{e.preventDefault();dialog.close()});
  const first=source.options[0]?.textContent||'';
  let title=source.getAttribute('aria-label')||source.getAttribute('title');
  if(!title&&source.id){const label=[...document.querySelectorAll('label')].find(l=>l.htmlFor===source.id);if(label)title=[...label.childNodes].filter(n=>n.nodeType===3).map(n=>n.textContent).join('').trim();}
  title=title||(/全部模块/.test(first)?'选择学习模块':/章节/.test(first)?'选择章节':/阶段/.test(source.name||'')?'选择学习阶段':'选择项目');
  const head=element('div','android-select-head'),heading=element('h2','',title),close=element('button','android-select-close','×');heading.id='androidSelectTitle';heading.tabIndex=-1;close.type='button';close.setAttribute('aria-label','取消选择');close.addEventListener('click',()=>dialog.close());head.append(heading,close);dialog.append(head);dialog.setAttribute('aria-labelledby',heading.id);
  const count=element('p','android-select-subtitle','当前：'+(source.selectedOptions[0]?.textContent||'未选择'));dialog.append(count);
  let search=null;if(source.options.length>7){search=element('input','android-select-search');search.type='search';search.placeholder='搜索选项';search.setAttribute('aria-label','搜索选项');dialog.append(search);}
  const list=element('div','android-select-options');list.setAttribute('role','listbox');list.setAttribute('aria-label',title);dialog.append(list);
  const empty=element('p','android-select-empty','没有找到匹配项，换个关键词试试。');empty.hidden=true;dialog.append(empty);
  const buttons=[];
  for(const option of source.options){
   if(option.hidden)continue;
   const selected=option.index===source.selectedIndex,button=element('button','android-select-option'+(selected?' selected':''));
   button.type='button';button.disabled=option.disabled||option.parentElement.disabled===true;button.setAttribute('role','option');button.setAttribute('aria-selected',String(selected));
   button.append(element('span','android-select-label',option.textContent));const check=element('span','android-select-check');check.setAttribute('aria-hidden','true');button.append(check);
   button.addEventListener('click',()=>{
    const target=resolve();if(!target||target.disabled){dialog.close();return;}
    const candidate=target.options[option.index]?.value===option.value?target.options[option.index]:[...target.options].find(o=>o.value===option.value);
    if(!candidate||candidate.disabled){dialog.close();return;}
    const changed=target.selectedIndex!==candidate.index;dialog.close();
    if(changed){target.selectedIndex=candidate.index;target.dispatchEvent(new Event('input',{bubbles:true}));target.dispatchEvent(new Event('change',{bubbles:true}));}
   });buttons.push(button);list.append(button);
  }
  search?.addEventListener('input',()=>{let visible=0;const query=search.value.trim().toLocaleLowerCase();for(const button of buttons){button.hidden=!button.textContent.toLocaleLowerCase().includes(query);if(!button.hidden)visible++;}empty.hidden=visible>0;});
  dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientY<r.top||e.clientX<r.left||e.clientX>r.right||e.clientY>r.bottom)dialog.close();}});
  dialog.addEventListener('close',()=>{if(active===dialog)active=null;dialog.remove();const target=resolve();if(target?.isConnected){if(keyboard)target.focus({preventScroll:true});else target.blur();}},{once:true});
  document.body.append(dialog);dialog.showModal();heading.focus({preventScroll:true});
 }
 // Prevent Android WebView's platform picker; retain the original select and events.
 document.addEventListener('pointerdown',e=>{if(selectable(e))e.preventDefault();},true);
 document.addEventListener('click',e=>{if(!selectable(e))return;e.preventDefault();e.stopImmediatePropagation();open(e.target);},true);
 document.addEventListener('keydown',e=>{if(selectable(e)&&(e.key==='Enter'||e.key===' '||e.key==='F4'||(e.altKey&&e.key==='ArrowDown'))){e.preventDefault();open(e.target,true);}},true);
})();
