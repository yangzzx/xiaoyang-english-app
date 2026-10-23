{
 const noChapter='__none__';
 const originalSpellUnits=spellUnits;
 const originalSpellScopeInfo=spellScopeInfo;
 let picker=null,draft=new Set(),appliedClose=false,observer=null;

 const scopeOptions=()=>spellScopeOptions().map(([value,label])=>[String(value),String(label)]);
 const isNone=()=>chapterSelection.length===1&&chapterSelection[0]===noChapter;
 const committed=()=>{
  const ids=new Set(scopeOptions().map(([value])=>value));
  if(isNone())return new Set();
  if(!chapterSelection.length)return ids;
  return new Set(chapterSelection.map(String).filter(value=>ids.has(value)));
 };
 const close=()=>window.StudyAndroid?.closeScopePicker?.();
 const controls=()=>picker?.querySelector('.v13-scope-panel');
 const inputs=()=>[...(controls()?.querySelectorAll('[data-chapter-scope]')||[])];

 spellUnits=function(b=book,scope=day,all=false){
  if(!all&&b===book&&isNone())return [];
  return originalSpellUnits(b,scope,all);
 };
 spellScopeInfo=function(){
  if(!isNone())return originalSpellScopeInfo();
  const options=scopeOptions();
  const source=book==='root'?'root':book==='mother'?'mother':book==='phonics'?'phonics':book==='w500'?'core':'phon';
  return {options,values:[],title:'未选择章节',invalid:false,href:link(source)};
 };

 function updateCount(){
  const el=controls()?.querySelector('.android-scope-count');if(!el)return;
  const count=draft.size,total=scopeOptions().length;
  const next='<strong>已选 '+count+' / '+total+'</strong> 个章节'+(count?'':' · 应用后暂停练习');
  if(el.innerHTML!==next)el.innerHTML=next;
 }
 function paintDraft(){
  for(const input of inputs())input.checked=draft.has(input.dataset.chapterScope);
  updateCount();
  const none=isNone();
  document.querySelectorAll('[data-act="startSpell"],[data-act="spellOne"]').forEach(button=>{
   if(none){button.dataset.androidNoScope='1';button.disabled=true}
   else if(button.dataset.androidNoScope){delete button.dataset.androidNoScope;button.disabled=!!(busy||attemptPending)}
  });
 }
 function resetDraft(){draft=committed();appliedClose=false;paintDraft()}
 function makeButton(label,action,className=''){
  const button=document.createElement('button');button.type='button';button.className='en-btn '+className;button.dataset.androidScopeAction=action;button.textContent=label;return button;
 }
 function installPicker(){
  const next=document.getElementById('chapterPicker');if(!next)return;
  const changed=picker!==next;
  picker=next;
  const panel=controls();if(!panel)return;
  if(!panel.dataset.androidScopeDraft){
   panel.dataset.androidScopeDraft='1';
   const oldActions=panel.querySelector('.en-actions');oldActions?.remove();
   const count=document.createElement('div');count.className='android-scope-count';count.setAttribute('role','status');count.setAttribute('aria-live','polite');
   const search=panel.querySelector('input[type="search"]');if(search)search.after(count);else panel.prepend(count);
   const tools=document.createElement('div');tools.className='android-scope-tools';tools.append(makeButton('全选','all'),makeButton('清空','none'),makeButton('反选','invert'));count.after(tools);
   const list=panel.querySelector('.v13-scope-list');
   const footer=document.createElement('div');footer.className='android-scope-footer';footer.append(makeButton('取消','cancel'),makeButton('应用','apply','android-scope-apply'));
   if(list)list.after(footer);else panel.append(footer);
   picker.addEventListener('toggle',()=>{
    if(picker?.open){resetDraft();return}
    if(!appliedClose)resetDraft();
    appliedClose=false;
   });
  }
  if(changed||!picker.open)resetDraft();else paintDraft();
 }
 function applyNone(){
  chapterSelection=[noChapter];day=0;group=0;phonicsLesson='';spellUnit='';
  const query=new URLSearchParams(location.search);query.set('book',book);query.set('chapters',noChapter);query.delete('day');query.delete('group');query.delete('lesson');query.delete('unit');
  history.replaceState(null,'','?'+query);
  updateSpellPracticeScope();updateSpellScopePanel();updateSpellPracticeSession();
 }
 function applyDraft(){
  if(busy||attemptPending){notify('请先确认上一次作答的保存结果。');return}
  const values=[...draft],wasEmpty=values.length===0;
  appliedClose=true;close();
  if(wasEmpty)applyNone();else changeSpellScopes(values);
  render();
  draft=committed();paintDraft();
 }
 function cancelDraft(){draft=committed();appliedClose=false;paintDraft();close()}

 document.addEventListener('click',event=>{
  const summary=event.target.closest('#chapterPicker>summary');
  if(summary){if(!picker?.open)resetDraft();else{cancelDraft();event.preventDefault();event.stopImmediatePropagation()}return}
  const button=event.target.closest('[data-android-scope-action]');if(!button)return;
  event.preventDefault();event.stopImmediatePropagation();
  const ids=scopeOptions().map(([value])=>value),action=button.dataset.androidScopeAction;
  if(action==='all')draft=new Set(ids);
  else if(action==='none')draft.clear();
  else if(action==='invert')draft=new Set(ids.filter(value=>!draft.has(value)));
  else if(action==='cancel'){cancelDraft();return}
  else if(action==='apply'){applyDraft();return}
  paintDraft();
 },true);

 document.addEventListener('change',event=>{
  const input=event.target.closest?.('[data-chapter-scope]');if(!input)return;
  event.preventDefault();event.stopImmediatePropagation();
  if(input.checked)draft.add(input.dataset.chapterScope);else draft.delete(input.dataset.chapterScope);
  updateCount();
 },true);

 document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&picker?.open){event.preventDefault();event.stopImmediatePropagation();cancelDraft()}
 },true);
 window.addEventListener('popstate',()=>requestAnimationFrame(()=>{installPicker();resetDraft()}));

 installPicker();
 const host=document.getElementById('appView')||document.body;
 observer=new MutationObserver(()=>installPicker());
 observer.observe(host,{childList:true,subtree:true});
}
