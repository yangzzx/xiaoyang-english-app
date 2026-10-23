// This module is injected inside the study-page closure by build.py.
var reviewUpgradeReady=false,reviewHistoryRows=[],reviewHistoryRootRows=[],reviewPanel=Q.get('panel')||'today',reviewSession=null,gradingReview=false,reviewExpiryTimerV14=null;
const legacyReviewViewV14=reviewView;
const basePracticeViewV14=practiceView;
const spellBatchMemoryV14=new Map();
function due(){
 const t=today();
 return [...reviews.map(r=>({...r,source:'all'})),...rootReviews.map(r=>({...r,module:'root',item_key:String(r.day_no),source:'root'}))]
  .filter(r=>r.active!==false&&!r.paused&&activeReview(r)&&r.scheduled_for<=t)
  .sort((a,b)=>a.scheduled_for.localeCompare(b.scheduled_for)||a.module.localeCompare(b.module));
}
function reviewGroups(rows){
 const map=new Map();
 for(const r of rows){const key=[r.source,r.module,String(r.item_key)].join(':');let g=map.get(key);if(!g){g={key,word:reviewWord(r),rows:[],module:r.module,item_key:String(r.item_key),scheduled_for:r.scheduled_for,id:r.id,source:r.source};map.set(key,g)}g.rows.push(r);if(r.scheduled_for<g.scheduled_for)g.scheduled_for=r.scheduled_for}
 return [...map.values()].map(g=>({...g,ids:g.rows.map(r=>({source:r.source,id:r.id})),sources:[...new Set(g.rows.map(r=>r.module==='root'?'32 天词根':MODS[r.module]?.[0]||r.module))]})).sort((a,b)=>a.scheduled_for.localeCompare(b.scheduled_for)||a.module.localeCompare(b.module)||a.item_key.localeCompare(b.item_key));
}
function dueCount(m=''){return reviewGroups(due().filter(r=>!m||r.module===m)).length}
function reviewSessionKey(){return 'xiaoyang.review.session.v14.'+(session?.user.id||'')}
function saveReviewSession(){try{if(reviewSession)localStorage.setItem(reviewSessionKey(),JSON.stringify(reviewSession));else if(session?.user.id)localStorage.removeItem(reviewSessionKey())}catch(e){notify('本机无法保存复习进度，当前练习完成前请保持 App 打开。')}}
function restoreReviewSession(){if(!reviewUpgradeReady||!session?.user.id)return;try{const raw=localStorage.getItem(reviewSessionKey());reviewSession=raw?JSON.parse(raw):null;if(!reviewSession||!Array.isArray(reviewSession.cards)){reviewSession=null;if(reviewPanel==='session')reviewPanel='today';return}const live=new Set([...reviews.filter(r=>r.active!==false&&!r.paused).map(r=>'all:'+r.id),...rootReviews.filter(r=>r.active!==false&&!r.paused).map(r=>'root:'+r.id)]);reviewSession.cards=reviewSession.cards.filter(c=>live.has(c.source+':'+c.id));reviewSession.index=Math.min(reviewSession.index||0,Math.max(0,reviewSession.cards.length-1));if(!reviewSession.cards.length&&reviewSession.index===0){reviewSession=null;if(reviewPanel==='session')reviewPanel='today'}saveReviewSession()}catch(e){reviewSession=null;if(reviewPanel==='session')reviewPanel='today'}}
const reviewLabelsV14={root:'32 天词根',phon:'国际音标',phonics:'自然拼读',mother:'秦天母词',core:'500 高频词汇',spell:'全能拼写',courses:'刘晓燕单词课',grammar:'刘晓燕语法课',papers:'真题精做',essay:'作文模板'};
function reviewModules(){return ['root','phon','phonics','mother','core','spell','courses','grammar','papers','essay'].filter(m=>due().some(r=>r.module===m))}
function reviewItem(c){
 const k=String(c.item_key),r=c.source==='root'?roots.find(x=>String(x.day_no)===k):record(c.module,k),d=r?.data||{};
 if(c.source==='root'){
  const day=DATA.days?.find(x=>Number(x.day)===Number(k));
  const answer=day?day.sections.map(s=>'<section class="v14-answer-section"><h3>'+esc(s.title)+'</h3>'+(s.desc?'<p>'+esc(String(s.desc).replace(/\*\*/g,''))+'</p>':'')+(s.words||[]).map(w=>'<p><b>'+esc(w['单词']||'')+'</b> · '+esc(w['中文意思']||'')+(w['怎么记']?'<br>'+esc(w['怎么记']):'')+(w['怎么拆']?'<br>'+esc(w['怎么拆']):'')+(w['例句']?'<br>'+esc(w['例句']):'')+'</p>').join('')+'</section>').join(''):'第 '+esc(k)+' 天课程内容';
  return {title:'第 '+k+' 天 · '+(day?.title||'词根词缀'),prompt:'请先回忆本日的前缀、后缀、母词和代表词。',answer,word:''};
 }
 if(c.module==='core'){const w=DATA.core.find(x=>String(x.no)===k);return {title:w?.w||d.title||k,word:w?.w||d.canonical_word||'',prompt:'先回忆英文的中文意思、词性和拼写。',answer:'<p>'+esc(w?.m||d.meaning||'')+'</p>'+(w?.ipa?'<p>音标：'+esc(w.ipa)+'</p>':'')+(w?.sp?'<p>考点：'+esc(w.sp)+'</p>':'')+(d.custom_note?'<p>'+esc(d.custom_note)+'</p>':'')}}
 if(c.module==='spell'){const word=d.title||d.canonical_word||k.split(':').pop();return {title:word,word,prompt:'先回忆这个英文单词的中文意思。',answer:'<p>'+esc(d.meaning||'')+'</p>'}}
 if(c.module==='phon'){const p=DATA.phon.find(x=>x.sym===k);return {title:'/'+k+'/',word:p?.eg?.[0]?.w||'',prompt:'请回忆这个音标的发音要领和例词。',answer:'<p>'+esc(p?.name||'')+' · '+esc(p?.type||'')+'</p><p>'+esc(p?.tip||'')+'</p>'+((p?.eg||[]).map(x=>'<p><b>'+esc(x.w)+'</b> · '+esc(x.zh)+' · '+esc(x.ipa)+'</p>').join(''))}}
 if(c.module==='phonics'){const p=DATA.phonics.find(x=>String(x.id)===k);return {title:p?.title||d.title||k,word:p?.words?.[0]||'',prompt:'请回忆本组拼读组合、发音规律和代表词。',answer:'<p>'+esc(p?.pattern||'')+'</p><p>'+esc(p?.explain||p?.rule||'')+'</p><p>'+esc((p?.words||[]).join(' · '))+'</p>'}}
 if(c.module==='mother'){const g=DATA.mother.find(x=>String(x.no)===k),words=(DATA.books?.mother||[]).filter(x=>String(x.grp)===k);return {title:g?.roots||d.title||('第 '+k+' 组母词'),word:words[0]?.w||'',prompt:'回忆母词含义，以及本组衍生词的意思和构词。',answer:'<p>'+esc(g?.def||'')+'</p>'+words.map(w=>'<p><b>'+esc(w.w)+'</b> · '+esc(w.zh)+'<br>'+esc(w.explain||w.split||'')+'</p>').join('')}}
 const unit=custom(c.module).find(x=>String(x.key)===k),title=unit?.title||d.title||unitTitle(c.module,k),content=unit?.content||unit?.text||d.content||d.text||d.notes||d.draft||'';
 return {title,word:'',prompt:'先回忆本项课程或资料的重点，再展开核对。',answer:'<div>'+esc(content||unit?.subtitle||'暂无已保存的课程笔记或正文。').replace(/\n/g,'<br>')+'</div>'};
}
function reviewTaskRows(){return [...reviews.filter(r=>r.active!==false&&!r.paused).map(r=>({...r,source:'all'})),...rootReviews.filter(r=>r.active!==false&&!r.paused).map(r=>({...r,module:'root',item_key:String(r.day_no),source:'root'}))]}
function reviewSpecialCandidates(modules,grade){return due().filter(r=>modules.includes(r.module)&&(!grade||String(r.source==='root'?roots.find(x=>String(x.day_no)===String(r.item_key))?.review_result:record(r.module,r.item_key)?.data?.review_result)===grade))}
function startReviewSession(rows,random=true,count=Infinity){
 const unique=reviewGroups(rows);let list=unique.map(g=>g.rows[0]);if(random)list.sort(()=>Math.random()-.5);else list.sort((a,b)=>a.scheduled_for.localeCompare(b.scheduled_for)||a.module.localeCompare(b.module)||String(a.item_key).localeCompare(String(b.item_key)));if(Number.isFinite(count))list=list.slice(0,Math.max(1,count));
 if(!list.length){notify('当前筛选没有到期复习项。');return}
 reviewSession={cards:list.map(r=>({source:r.source,id:r.id,module:r.module,item_key:String(r.item_key),scheduled_for:r.scheduled_for,stage:r.stage||0})),index:0,revealed:false,started_at:new Date().toISOString(),results:[]};reviewPanel='session';const q=new URLSearchParams(location.search);q.set('panel','session');history.replaceState(null,'','?'+q);saveReviewSession();render();
}
function reviewResultText(c){const state=String(c.source==='root'?roots.find(x=>String(x.day_no)===String(c.item_key))?.review_result:record(c.module,c.item_key)?.data?.review_result||'');return state}
function reviewRowTitle(r){return reviewItem({source:r.source||'all',module:r.module,item_key:r.item_key}).title}
function historySummary(){const map=new Map();for(const r of [...reviewHistoryRows.map(x=>({...x,source:'all'})),...reviewHistoryRootRows.map(x=>({...x,module:'root',item_key:String(x.day_no),source:'root'}))]){if(!r.result||!r.completed_at)continue;const key=r.source+':'+r.module+':'+r.item_key;let g=map.get(key);if(!g){g={key,module:r.module,item_key:String(r.item_key),source:r.source,rows:[]};map.set(key,g)}g.rows.push(r)}return [...map.values()].map(g=>({...g,rows:g.rows.sort((a,b)=>String(b.completed_at).localeCompare(String(a.completed_at))),last:g.rows[0]})).sort((a,b)=>String(b.last.completed_at).localeCompare(String(a.last.completed_at)))}
function reviewTabsHTML(){return '<nav class="v14-tabs" aria-label="复习中心">'+[['today','今日待复习'],['special','专项复习'],['history','复习历史'],['manage','任务管理']].map(([k,t])=>'<button type="button" data-v14-tab="'+k+'" class="'+(reviewPanel===k?'active':'')+'">'+t+'</button>').join('')+'</nav>'}
function reviewSessionHTML(){
 const p=reviewSession;if(!p)return '<section class="en-card"><h2>没有未完成的复习会话</h2><button class="en-btn" data-v14-tab="today">返回今日待复习</button></section>';
 const c=p.cards[p.index];if(!c)return '<section class="en-card v14-finished"><h2>本轮复习完成</h2><p>完成 '+(p.results||[]).length+' 项 · 记住 '+(p.results||[]).filter(x=>x==='remembered').length+' · 模糊 '+(p.results||[]).filter(x=>x==='fuzzy').length+' · 忘记 '+(p.results||[]).filter(x=>x==='forgotten').length+'</p><button class="en-btn primary" data-v14-action="finish">完成</button></section>';
 const item=reviewItem(c),progress=(p.index+1)+' / '+p.cards.length;
 return '<section class="en-card v14-session"><div class="v14-session-head"><span>'+esc(reviewLabelsV14[c.module]||c.module)+' · '+progress+'</span><button class="en-btn" data-v14-action="exit">退出本轮</button></div><div class="en-progress"><i style="width:'+Math.round(p.index/Math.max(1,p.cards.length)*100)+'%"></i></div><p class="v14-prompt">'+esc(item.prompt)+'</p><h2>'+esc(item.title)+'</h2>'+(item.word?'<div class="v14-word">'+esc(item.word)+'</div><button class="en-btn" data-v14-action="speak" data-word="'+esc(item.word)+'">听发音</button>':'')+(p.revealed?'<div class="v14-answer">'+item.answer+'</div><div class="v14-grade">'+[['remembered','记住了'],['fuzzy','有些模糊'],['forgotten','忘记了']].map(([g,t])=>'<button class="en-btn" data-v14-action="grade" data-grade="'+g+'" '+(busy?'disabled':'')+'>'+t+'</button>').join('')+'</div>':'<button class="en-btn primary" data-v14-action="reveal">显示答案</button>')+'</section>';
}
function moduleReviewView(scope,onlyKey=''){
 if(!reviewUpgradeReady)return '<section class="en-card v14-migration"><b>云端复习规则待升级</b><p>请先完成云端复习升级，再刷新此页。旧学习进度和复习历史不会删除。</p></section>';
 if(reviewPanel==='session'&&reviewSession)return reviewSessionHTML();
 const matches=r=>r.module===scope&&(!onlyKey||String(r.item_key)===String(onlyKey));
 const dueRows=due().filter(matches),groups=reviewGroups(dueRows),scheduled=reviewTaskRows().filter(matches),future=scheduled.filter(r=>r.scheduled_for>today()).sort((a,b)=>a.scheduled_for.localeCompare(b.scheduled_for));
 const title=reviewLabelsV14[scope]||scope,heading=onlyKey?reviewRowTitle({module:scope,item_key:onlyKey,source:scope==='root'?'root':'all'}):title+' · 本模块复习';
 const cards=groups.map(g=>{const r=g.rows[0];return '<article><div><b>'+esc(reviewRowTitle(r))+'</b><small>'+esc(g.scheduled_for)+(g.scheduled_for<today()?' · 逾期保留':' · 今天到期')+'</small></div><button class="en-btn" data-v14-action="startOne" data-source="'+r.source+'" data-id="'+r.id+'" '+(busy?'disabled':'')+'>开始复习</button></article>'}).join('');
 const emptyText=future.length?'本模块有 '+future.length+' 项后续复习，最近一次是 '+future[0].scheduled_for+'。':'完成本模块的学习打卡后，到期项目会在这里出现。';
 return '<section class="en-card v14-module-review"><div class="v14-module-review-head"><div><span class="en-muted">'+esc(title)+'</span><h2>'+esc(heading)+'</h2></div><b class="v14-module-count">'+groups.length+'</b></div><p class="en-muted">只显示本模块已经到期的项目；已逾期项目会保留。拼写练习记录独立保存。</p><button class="en-btn primary" data-v14-action="startModule" data-module="'+esc(scope)+'" data-key="'+esc(onlyKey)+'" '+(!groups.length||busy?'disabled':'')+'>开始本模块复习</button></section>'+(groups.length?'<section class="v14-due-list v14-module-due">'+cards+'</section>':'<section class="en-card v14-module-empty"><b>本模块当前没有到期项目</b><p>'+esc(emptyText)+'</p></section>');
}
function scheduleReviewExpiryV14(rows){
 if(reviewExpiryTimerV14)clearTimeout(reviewExpiryTimerV14);
 const next=rows.map(r=>r.paused_at?new Date(r.paused_at).getTime()+3*86400000:0).filter(t=>t>Date.now()).sort((a,b)=>a-b)[0];
 if(next)reviewExpiryTimerV14=setTimeout(()=>{reviewExpiryTimerV14=null;render()},next-Date.now()+100);
}
function spellBatchPoolV14(mode,key='',entry=''){
 let list=uniqueSpellCards(spellUnits().filter(u=>!entry||u.entries.includes(entry)||u.entry===entry));
 if(key)list=list.filter(u=>u.key===key);else if(mode==='wrong')list=list.filter(u=>(data('spell',u.key).wrong_count||0)>0&&!done('spell',u.key));
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
 state.used=Array.isArray(state.used)?[...new Set(state.used.filter(k=>list.some(u=>u.key===k)))]:[];return state;
}
function saveSpellBatchStateV14(key,state){spellBatchMemoryV14.set(key,state);try{localStorage.setItem(key,JSON.stringify(state))}catch(e){notify('本机无法保存本轮已练词条；退出 App 前请完成当前批次。')}}
startSpell=function(mode,key='',entry=''){
 if(busy||attemptPending){notify('请先确认上一次作答的保存结果。');return}
 let list=spellBatchPoolV14(mode,key,entry);
 if(!list.length){notify(mode==='wrong'?'当前没有待重练的错词。':'当前没有可以练习的内容。');return}
 const practiceMode=book==='phon'?'phon':mode;
 if(key){list=[...list].sort(()=>Math.random()-.5);practice={kind:'spell',mode:practiceMode,cards:list,index:0,revealed:false,feedback:null,results:[],completedKeys:[]};}
 else{
  const storageKey=spellBatchKeyV14(practiceMode,list),state=spellBatchStateV14(storageKey,list);let remaining=list.filter(u=>!state.used.includes(u.key));
  if(!remaining.length){state.used=[];remaining=list;notify('本范围已练完，已为你开启新一轮。')}
  remaining.sort(()=>Math.random()-.5);const cards=remaining.slice(0,20);state.used.push(...cards.map(u=>u.key));saveSpellBatchStateV14(storageKey,state);
  practice={kind:'spell',mode:practiceMode,cards,index:0,revealed:false,feedback:null,results:[],completedKeys:[],batchRemaining:remaining.length-cards.length};
 }
 view='practice';attemptPending=null;render();
};
practiceView=function(){
 const p=practice;
 if(p?.kind==='spell'&&p.cards.length&&p.index>=p.cards.length){
  return '<section class="en-card v14-spell-finished"><span class="en-muted">全能拼写 · 本批完成</span><h2>已完成 '+p.cards.length+' 个词条</h2><p>下一批会跳过之前练过的词。当前范围还剩 '+(p.batchRemaining||0)+' 个不同词条。</p>'+(p.batchRemaining?'<button class="en-btn primary" data-v14-action="spellNextBatch">继续下一批</button>':'<p>本范围已全部练完；下次开始将进入新一轮。</p>')+'<button class="en-btn" data-act="endPractice">返回学习内容</button></section>';
 }
 return basePracticeViewV14();
};
function reviewView(only=module==='review'?'':module,onlyKey=''){
 if(module!=='review'||only){if(module!=='root'&&only)return moduleReviewView(only,onlyKey);return legacyReviewViewV14(only,onlyKey)}
 if(!ready)return empty('正在读取个人复习安排','联网后会显示到期与逾期任务；请等待同步成功。',button('重新读取','refresh'));
 const counts=[1,3,7,15,30,60,90].map(n=>{const dt=new Date();dt.setUTCDate(dt.getUTCDate()+n);return [n,reviewGroups(reviewTaskRows().filter(r=>r.scheduled_for===today(dt))).length]});
 let body='';
 if(!reviewUpgradeReady)body='<div class="v14-migration"><b>云端复习规则待升级</b><p>当前 APK 已准备好新的复习流程，但云端还没有“单项任务、暂停恢复和复习历史”结构。先完成随安装包提供的云端复习升级，再刷新此页。你的旧进度不会删除。</p></div>';
 else if(reviewPanel==='session')body=reviewSessionHTML();
 else if(reviewPanel==='special'){
  const modules=reviewModules(),total=due().length;
  body='<section class="en-card v14-special"><h2>专项复习</h2><p class="en-muted">按模块、掌握状态和数量组成一轮；不会新建或重复安排任务。</p><div class="v14-check-actions"><button class="en-btn" data-v14-action="selectModules">全选</button><button class="en-btn" data-v14-action="clearModules">全不选</button></div><div class="v14-module-grid">'+modules.map(m=>'<label><input type="checkbox" data-v14-module="'+m+'" checked><span>'+esc(reviewLabelsV14[m])+' <small>'+dueCount(m)+'</small></span></label>').join('')+'</div><div class="v14-special-controls"><label>只看掌握状态<select id="v14Grade"><option value="">全部到期</option><option value="fuzzy">只看模糊</option><option value="forgotten">只看忘记</option></select></label><label>本轮数量<input id="v14Count" type="number" min="1" max="500" value="'+Math.max(1,total)+'"></label><div class="v14-order-control"><span>排列顺序</span><div class="v14-order-segment" role="group" aria-label="排列顺序"><button type="button" data-v14-order="random" class="active" aria-pressed="true">随机</button><button type="button" data-v14-order="scheduled" aria-pressed="false">按到期</button></div><input id="v14Random" type="checkbox" checked hidden></div></div><button class="en-btn primary" data-v14-action="startSpecial" '+(!total||busy?'disabled':'')+'>开始所选复习</button></section>';
 }else if(reviewPanel==='history'){
  const list=historySummary();body=list.length?'<section class="en-card v14-history"><h2>复习历史 · '+list.length+' 项</h2>'+list.slice(0,300).map(g=>'<article><div><b>'+esc(reviewRowTitle(g.last))+'</b><small>'+esc(reviewLabelsV14[g.module]||g.module)+' · '+esc(String(g.last.completed_at).replace('T',' ').slice(0,16))+' · '+g.rows.length+' 次</small></div><span class="v14-result '+esc(g.last.result)+'">'+({remembered:'记住了',fuzzy:'模糊',forgotten:'忘记了'}[g.last.result]||'已完成')+'</span></article>').join('')+'</section>':empty('还没有复习历史','完成一项到期复习后，结果和时间会保存在这里。','');
 }else if(reviewPanel==='manage'){
  const active=reviewTaskRows(),allPaused=[...reviews.filter(r=>r.active===false&&r.paused).map(r=>({...r,source:'all'})),...rootReviews.filter(r=>r.active===false&&r.paused).map(r=>({...r,module:'root',item_key:String(r.day_no),source:'root'}))],recent=(r)=>!r.paused_at||Date.now()-new Date(r.paused_at).getTime()<3*86400000,paused=allPaused.filter(recent);scheduleReviewExpiryV14(allPaused);
  body='<section class="en-card v14-manage"><h2>有效任务 · '+active.length+'</h2>'+active.slice(0,500).map(r=>'<article><div><b>'+esc(reviewRowTitle(r))+'</b><small>'+esc(reviewLabelsV14[r.module]||r.module)+' · '+esc(r.scheduled_for)+(r.scheduled_for<today()?' · 逾期':' · 待到期')+'</small></div><button class="en-btn" data-v14-action="pause" data-source="'+r.source+'" data-module="'+esc(r.module)+'" data-key="'+esc(r.item_key)+'" '+(busy?'disabled':'')+'>移出队列</button></article>').join('')+'</section><section class="en-card v14-manage"><h2>已移出 · '+paused.length+' <small>（3 天内可恢复）</small></h2>'+paused.slice(0,500).map(r=>'<article><div><b>'+esc(reviewRowTitle(r))+'</b><small>'+esc(reviewLabelsV14[r.module]||r.module)+' · 移出于 '+esc(r.paused_at?String(r.paused_at).replace('T',' ').slice(0,16):'最近')+'</small></div><button class="en-btn" data-v14-action="rejoin" data-source="'+r.source+'" data-module="'+esc(r.module)+'" data-key="'+esc(r.item_key)+'" '+(busy?'disabled':'')+'>重新加入</button></article>').join('')+'</section>';
 }else{
  const all=due(),groups=reviewGroups(all),saved=reviewSession?.cards?.length||0;
  body='<div class="v4-tools"><span class="en-muted">今天 '+today()+' · 逾期任务会一直保留</span><button class="en-btn" data-v14-action="refresh">刷新复习</button></div><div class="v4-date-strip">'+counts.map(([n,c])=>'<div><b>'+c+'</b>'+n+' 天后</div>').join('')+'</div>'+(saved?'<section class="en-card v14-resume"><b>有一轮未完成复习 · '+saved+' 项</b><button class="en-btn primary" data-v14-action="resume">继续复习</button></section>':'')+'<section class="en-card v14-today"><div><h2>今日与逾期待复习</h2><p>'+groups.length+' 项 · 包含已打卡模块单词和全能拼写</p></div><button class="en-btn primary" data-v14-action="startAll" '+(!reviewUpgradeReady||!groups.length||busy?'disabled':'')+'>一键复习全部</button></section>'+(groups.length?'<section class="v14-due-list">'+groups.slice(0,300).map(g=>{const r=g.rows[0];return '<article><div><b>'+esc(reviewRowTitle(r))+'</b><small>'+esc(reviewLabelsV14[r.module]||r.module)+' · '+esc(g.scheduled_for)+(g.scheduled_for<today()?' · 逾期保留':' · 今天到期')+'</small></div><button class="en-btn" data-v14-action="startOne" data-source="'+r.source+'" data-id="'+r.id+'" '+(!reviewUpgradeReady||busy?'disabled':'')+'>开始复习</button></article>'}).join('')+'</section>':empty('今天没有到期任务','完成一项新的学习后，会从明天开始安排复习。',''));
 }
 return reviewTabsHTML()+body;
}
function v14ReadSession(){return reviewSession?.cards?.[reviewSession.index]||null}
function v14ModulesSelected(){return [...document.querySelectorAll('[data-v14-module]:checked')].map(x=>x.dataset.v14Module)}
async function v14Grade(result){
 const c=v14ReadSession();if(!c||busy)return;gradingReview=true;
 const ok=await write(()=>rpc(c.source==='root'?'day32_grade':'study_grade',c.source==='root'?{p_review:Number(c.id),p_result:result}:{p_review:Number(c.id),p_result:result}),r=>{
  if(r?.saved===false&&r?.already_completed){notify('这项已在其他设备完成，已从本轮跳过。')}
  const at=reviewSession?.cards?.findIndex(x=>x.source===c.source&&String(x.id)===String(c.id))??-1;
  if(at>=0){reviewSession.cards.splice(at,1);if(at<reviewSession.index)reviewSession.index--}
  reviewSession.results.push(result);reviewSession.revealed=false;
  if(reviewSession.index>=reviewSession.cards.length){reviewSession.cards=[];reviewSession.index=0}
  const historyRow={module:c.module,item_key:c.item_key,day_no:c.source==='root'?Number(c.item_key):undefined,result,completed_at:new Date().toISOString()};
  if(c.source==='root')reviewHistoryRootRows.unshift(historyRow);else reviewHistoryRows.unshift(historyRow);
  saveReviewSession();
 },r=>r?.saved===false&&r?.already_completed?'已同步另一设备的完成结果。':('已保存 · '+({remembered:'记住了',fuzzy:'模糊',forgotten:'忘记了'}[result]||'')));
 gradingReview=false;if(!ok)render();
}
function v14OpenPanel(panel){reviewPanel=panel;const q=new URLSearchParams(location.search);q.set('panel',panel);history.replaceState(null,'','?'+q);render()}
async function v14Manage(source,module,key,active){
 if(!reviewUpgradeReady||busy)return;await write(()=>rpc(source==='root'?'day32_review_manage':'study_review_manage',source==='root'?{p_day_no:Number(key),p_active:active}:{p_module:module,p_key:key,p_active:active}),active?'已重新加入复习队列。':'已移出复习队列；学习记录和历史保留。');
}
const baseLoadV14=load;
load=async function(renderAfter=true){
 await baseLoadV14(renderAfter);
 const version=await rpc('study_review_version');reviewUpgradeReady=!version.error&&Number(version.data?.version)>=2;
 if(reviewUpgradeReady){
  const uid=session?.user.id;
  if(renderAfter||reviewPanel==='history'){
   const [h,rh]=await Promise.all([pages('study_reviews',q=>q.select('*').eq('user_id',uid).not('completed_at','is',null).order('completed_at',{ascending:false})),pages('day32_reviews',q=>q.select('*').eq('user_id',uid).not('completed_at','is',null).order('completed_at',{ascending:false}))]);
   if(StudyAccount.session?.user.id===uid){reviewHistoryRows=h;reviewHistoryRootRows=rh}
  }
  if(!gradingReview)restoreReviewSession();
 }else{reviewHistoryRows=[];reviewHistoryRootRows=[];reviewSession=null}
 if(renderAfter)render();
};
document.addEventListener('click',async e=>{
 const tab=e.target.closest('[data-v14-tab]');if(tab){e.preventDefault();e.stopImmediatePropagation();v14OpenPanel(tab.dataset.v14Tab);return}
 const order=e.target.closest('[data-v14-order]');if(order){e.preventDefault();e.stopImmediatePropagation();const random=order.dataset.v14Order==='random',input=$('v14Random');if(input)input.checked=random;order.closest('.v14-order-segment')?.querySelectorAll('[data-v14-order]').forEach(x=>{const active=x===order;x.classList.toggle('active',active);x.setAttribute('aria-pressed',String(active))});return}
 const b=e.target.closest('[data-v14-action]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();if(b.disabled)return;
 const a=b.dataset.v14Action;
 if(a==='startAll'){startReviewSession(due(),true);return}
 if(a==='startModule'){const scope=b.dataset.module,key=b.dataset.key||'';startReviewSession(due().filter(r=>r.module===scope&&(!key||String(r.item_key)===key)),true);return}
 if(a==='spellNextBatch'){if(practice?.kind==='spell')startSpell(practice.mode);return}
 if(a==='startOne'){const row=due().find(r=>r.source===b.dataset.source&&String(r.id)===String(b.dataset.id));if(row)startReviewSession([row],false);return}
 if(a==='startSpecial'){const modules=v14ModulesSelected(),grade=$('v14Grade')?.value||'',random=!!$('v14Random')?.checked,count=Math.max(1,Number($('v14Count')?.value)||1);startReviewSession(reviewSpecialCandidates(modules,grade),random,count);return}
 if(a==='resume'){reviewPanel='session';render();return}
 if(a==='reveal'){if(reviewSession){reviewSession.revealed=true;saveReviewSession();render()}return}
 if(a==='grade'){await v14Grade(b.dataset.grade);return}
 if(a==='speak'){say(b.dataset.word);return}
 if(a==='exit'){reviewPanel='today';const q=new URLSearchParams(location.search);q.set('panel','today');history.replaceState(null,'','?'+q);render();return}
 if(a==='finish'){reviewSession=null;saveReviewSession();reviewPanel='today';const q=new URLSearchParams(location.search);q.set('panel','today');history.replaceState(null,'','?'+q);render();return}
 if(a==='pause'||a==='rejoin'){await v14Manage(b.dataset.source,b.dataset.module,b.dataset.key,a==='rejoin');return}
 if(a==='selectModules'||a==='clearModules'){document.querySelectorAll('[data-v14-module]').forEach(x=>x.checked=a==='selectModules');return}
 if(a==='refresh'){refresh();return}
},true);
window.addEventListener('study-account-change',e=>{if(session?.user.id!==e.detail.session?.user.id){reviewSession=null;reviewHistoryRows=[];reviewHistoryRootRows=[];reviewUpgradeReady=false}});
if(module==='root'){
 rootPending=rootPending.map(r=>({...r,active:r.active!==false,paused:!!r.paused}));
}
