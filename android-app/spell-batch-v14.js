// Keep bulk spelling sessions in non-repeating batches of at most 20 words.
const spellBatchMemoryV14=new Map();
const basePracticeViewSpellBatchV14=practiceView;
function spellBatchPoolV14(mode,key='',entry=''){
 let list=uniqueSpellCards(spellUnits().filter(u=>!entry||u.entries.includes(entry)||u.entry===entry));
 if(key)list=list.filter(u=>u.key===key);
 else if(mode==='wrong')list=list.filter(u=>(data('spell',u.key).wrong_count||0)>0&&!done('spell',u.key));
 return list;
}
function spellBatchKeyV14(mode,list){
 const pool=list.map(u=>u.key).sort().join('\n'),scope=(chapterSelection||[]).map(String).sort().join(',')+'|'+book+'|'+mode+'|'+pool;
 let hash=2166136261;for(let i=0;i<scope.length;i++)hash=Math.imul(hash^scope.charCodeAt(i),16777619);
 return 'xiaoyang.spell.batch.v1.'+(session?.user.id||'guest')+'.'+(hash>>>0).toString(36)+'.'+list.length;
}
function spellBatchStateV14(key,list){
 const signature=list.map(u=>u.key).sort().join('|');let state=spellBatchMemoryV14.get(key);
 try{const saved=JSON.parse(localStorage.getItem(key)||'null');if(saved&&saved.signature===signature)state=saved}catch(e){}
 if(!state||state.signature!==signature)state={signature,used:[]};
 state.used=Array.isArray(state.used)?[...new Set(state.used.filter(k=>list.some(u=>u.key===k)))]:[];
 return state;
}
function saveSpellBatchStateV14(key,state){
 spellBatchMemoryV14.set(key,state);
 try{localStorage.setItem(key,JSON.stringify(state))}catch(e){notify('本机无法保存本轮已练词条；退出 App 前请完成当前批次。')}
}
startSpell=function(mode,key='',entry=''){
 if(busy||attemptPending){notify('请先确认上一次作答的保存结果。');return}
 let list=spellBatchPoolV14(mode,key,entry);
 if(!list.length){notify(mode==='wrong'?'当前没有待重练的错词。':'当前没有可以练习的内容。');return}
 const practiceMode=book==='phon'?'phon':mode;
 let cards,batchRemaining;
 if(key){
  cards=[...list].sort(()=>Math.random()-.5);
 }else{
  const storageKey=spellBatchKeyV14(practiceMode,list),state=spellBatchStateV14(storageKey,list);
  let remaining=list.filter(u=>!state.used.includes(u.key));
  if(!remaining.length){state.used=[];remaining=list;notify('本范围已练完，已为你开启新一轮。')}
  remaining.sort(()=>Math.random()-.5);cards=remaining.slice(0,20);batchRemaining=remaining.length-cards.length;
  state.used.push(...cards.map(u=>u.key));saveSpellBatchStateV14(storageKey,state);
 }
 practice={kind:'spell',mode:practiceMode,cards,index:0,revealed:false,feedback:null,results:[],completedKeys:[],batchRemaining};
 view='practice';attemptPending=null;render();
};
practiceView=function(){
 const p=practice;
 if(p?.kind==='spell'&&p.cards.length&&p.index>=p.cards.length){
  return '<section class="en-card v14-spell-finished"><span class="en-muted">全能拼写 · 本批完成</span><h2>已完成 '+p.cards.length+' 个词条</h2><p>下一批会跳过之前练过的词。当前范围还剩 '+(p.batchRemaining||0)+' 个不同词条。</p>'+(p.batchRemaining?'<button class="en-btn primary" data-v14-action="spellNextBatch">继续下一批</button>':'<p>本范围已全部练完；下次开始将进入新一轮。</p>')+'<button class="en-btn" data-act="endPractice">返回学习内容</button></section>';
 }
 return basePracticeViewSpellBatchV14();
};
document.addEventListener('click',e=>{
 const b=e.target.closest('[data-v14-action="spellNextBatch"]');if(!b)return;
 e.preventDefault();e.stopImmediatePropagation();if(practice?.kind==='spell')startSpell(practice.mode);
},true);
