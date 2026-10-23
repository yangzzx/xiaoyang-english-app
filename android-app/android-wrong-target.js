// Keep the mastery threshold adjustable without changing the original course pages.
var androidWrongTarget=2;
window.reviewLabelsV14=window.reviewLabelsV14||{root:'32 天词根',core:'500 高频词',mother:'58 组母词',phon:'国际音标',phonics:'自然拼读'};
function androidWrongTargetKey(){return 'study-wrong-target:'+String(session?.user?.id||'guest')}
function androidReadWrongTarget(){
 const value=Number(localStorage.getItem(androidWrongTargetKey()));
 androidWrongTarget=Number.isInteger(value)&&value>=1&&value<=10?value:2;
}
const androidLoadWrongBase=androidLoadWrong;
androidLoadWrong=async function(){await androidLoadWrongBase();androidReadWrongTarget()};
const androidWrongNotebookBase=androidWrongNotebook;
androidWrongNotebook=function(){
 const options=Array.from({length:10},(_,i)=>i+1).map(n=>'<option value="'+n+'" '+(n===androidWrongTarget?'selected':'')+'>'+n+'</option>').join('');
 return androidWrongNotebookBase()
  .replace('<div class="en-actions"><button class="en-btn primary" data-awr="addWrong">','<div class="en-actions"><label>连对 <select class="v4-select" id="androidWrongTarget">'+options+'</select> 次后移出待练</label><button class="en-btn primary" data-awr="addWrong">')
  .replaceAll('连对两次，已移出待练','连对 '+androidWrongTarget+' 次，已移出待练');
};
document.addEventListener('change',async event=>{
 const input=event.target.closest?.('#androidWrongTarget');if(!input)return;
 const next=Number(input.value);if(!Number.isInteger(next)||next<1||next>10)return;
 const changes=androidWrongRows.filter(row=>Boolean(row.active)!==(Number(row.streak||0)<next));
 for(const row of changes){
  const result=await client.from('study_wrong_words').update({active:Number(row.streak||0)<next}).eq('id',row.id).eq('user_id',session.user.id);
  if(result.error){notify('更新移出规则失败：'+result.error.message);render();return}
 }
 androidWrongTarget=next;localStorage.setItem(androidWrongTargetKey(),String(next));
 await androidLoadWrong();render();
},true);
document.addEventListener('click',async event=>{
 const button=event.target.closest?.('[data-awr="wrongGrade"]');if(!button)return;
 event.preventDefault();event.stopPropagation();event.stopImmediatePropagation();
 const practice=androidWordSession,row=practice?.rows?.[practice.index];if(!row)return;
 const correct=button.dataset.correct==='true';
 const streak=correct?Math.min(androidWrongTarget,Number(row.streak||0)+1):0;
 const active=!correct||streak<androidWrongTarget;
 const result=await client.from('study_wrong_words').update({streak,active,wrong_count:(row.wrong_count||0)+(correct?0:1),updated_at:new Date().toISOString()}).eq('id',row.id).eq('user_id',session.user.id);
 if(result.error){notify('保存错题记录失败：'+result.error.message);return}
 practice.index++;practice.revealed=false;
 if(practice.index>=practice.rows.length){androidWordSession=null;view='library'}
 await androidLoadWrong();render();
},true);
