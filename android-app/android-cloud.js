(function(){
 'use strict';
 function requireUser(uid){if(!uid||window.StudyAccount?.session?.user?.id!==uid)throw new Error('账号已切换，请重新读取后再操作。')}
 async function checked(query){const result=await query;if(result.error)throw result.error;return result.data}
 // The deployed legacy RPC references columns absent from study_word_reviews.
 // Only use this compatibility path after a confirmed SQL schema rejection;
 // a lost network response must never cause a second, different write attempt.
 let legacyCancellation=false;
 async function cancelModule(client,uid,module,key){
  try{
   requireUser(uid);
   if(!legacyCancellation){
    const result=await client.rpc('study_uncomplete',{p_module:module,p_key:key});
    if(!result.error)return result;
    if(result.error.code!=='42703'||!/(parent_module|paused|paused_at)/.test(result.error.message||''))return result;
    legacyCancellation=true;
   }
   // Clear children before the completion flag. If a request fails, the lesson
   // stays checked in and cancellation can be retried without losing its content.
   await checked(client.from('study_word_reviews').update({active:false}).eq('user_id',uid).eq('module',module).eq('parent_key',key).is('completed_at',null));
   requireUser(uid);
   await checked(client.from('study_reviews').update({active:false,paused:false,paused_at:null}).eq('user_id',uid).eq('module',module).eq('item_key',key).is('completed_at',null));
   requireUser(uid);
   const rows=await checked(client.from('study_records').update({completed_at:null,updated_at:new Date().toISOString()}).eq('user_id',uid).eq('module',module).eq('item_key',key).not('completed_at','is',null).select('item_key'));
   return {data:{saved:!!rows?.length,completed:false,removed_from_review:true},error:null};
  }catch(error){return {data:null,error}}
 }
 async function cancelRoot(client,uid,day){
  try{
   requireUser(uid);
   // The existing root RPC clears lesson cards, but omits their word cards.
   await checked(client.from('study_word_reviews').update({active:false}).eq('user_id',uid).eq('module','root').eq('parent_key',String(day)).is('completed_at',null));
   requireUser(uid);
   return await client.rpc('day32_uncomplete',{p_day:day});
  }catch(error){return {data:null,error}}
 }
 window.StudyCloud={cancelModule,cancelRoot};
})();
