-- v1.0.41 母词整章排期。只交付维护者手动执行，本次未连接云端。
-- 已有 08 单词队列结构即可；不需要重跑旧 06 或旧 09。
-- 当前轮未评分的到期词保留，整章练完后统一下一次日期，以本轮最短间隔为准。
-- 保留历史、已移出任务和单词各自掌握阶段；不修改其他模块间隔。
begin;
do $$ begin
 if to_regclass('public.study_word_reviews') is null
 or to_regclass('public.study_records') is null
 or to_regclass('public.study_word_reviews_one_active') is null
 then raise exception '缺少单词复习结构，请先运行 00 只读导出脚本核对，不要重复执行旧迁移。'; end if;
end $$;

-- 旧任务按“本轮待完成/下一轮”分别统一日期，重复执行不把已练内容拉回今天。
update public.study_word_reviews r set scheduled_for=g.next_date
from (select user_id,parent_key,scheduled_for<=(now() at time zone 'Asia/Shanghai')::date as is_due,min(scheduled_for) next_date
 from public.study_word_reviews where module='mother' and active and completed_at is null
 group by user_id,parent_key,scheduled_for<=(now() at time zone 'Asia/Shanghai')::date) g
where r.user_id=g.user_id and r.parent_key=g.parent_key and r.module='mother'
 and (r.scheduled_for<=(now() at time zone 'Asia/Shanghai')::date)=g.is_due
 and r.active and r.completed_at is null and r.scheduled_for is distinct from g.next_date;

create or replace function public.study_word_sync(p_items jsonb)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 u uuid:=auth.uid(); d date:=(now() at time zone 'Asia/Shanghai')::date;
 item jsonb; inserted_count integer:=0; pm text; pk text; wm text; wk text; en text; zh text;
 first_day date; next_day date; learned_at timestamptz;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>3000
 then raise exception 'invalid review items'; end if;
 for item in select value from jsonb_array_elements(p_items) loop
  wm:=item->>'module';pm:=item->>'parent_module';pk:=item->>'parent_key';wk:=item->>'word_key';
  en:=left(trim(item->>'english'),160);zh:=left(trim(item->>'chinese'),500);
  if wm is null or wm not in ('root','core','mother','phon','phonics') or pk is null or wk is null
   or coalesce(en,'')='' or coalesce(zh,'')='' then continue; end if;
  if pm='root' then
   if pk !~ '^[0-9]{1,2}$' then continue; end if;
   select l.completed_at into learned_at
   from public.day32_lessons l where l.user_id=u and l.day_no=pk::integer and l.status='completed';
  else
   select s.completed_at into learned_at
   from public.study_records s where s.user_id=u and s.module=pm and s.item_key=pk and s.completed_at is not null;
  end if;
  if learned_at is null then continue; end if;
  first_day:=(learned_at at time zone 'Asia/Shanghai')::date;
  -- Keep a manually removed pending task removed. A later, new check-in may start again.
  if exists(select 1 from public.study_word_reviews q where q.user_id=u and q.module=wm
   and q.word_key=wk and not q.active and q.completed_at is null and q.created_at>=learned_at)
   then continue;end if;
  if wm='mother' then
   perform pg_advisory_xact_lock(hashtextextended(u::text||':mother:'||pk,0));
   select min(r.scheduled_for) into next_day from public.study_word_reviews r
    where r.user_id=u and r.module='mother' and r.parent_key=pk and r.active and r.completed_at is null;
   next_day:=coalesce(next_day,first_day+1);
  else
   next_day:=d+1+mod(mod(hashtextextended(u::text||':'||wm||':'||wk,0),7)+7,7)::integer;
  end if;
  insert into public.study_word_reviews(user_id,module,parent_key,word_key,english,chinese,pattern,example,scheduled_for)
   values(u,wm,pk,wk,en,zh,left(item->>'pattern',240),left(item->>'example',500),next_day) on conflict do nothing;
  if found then inserted_count:=inserted_count+1; end if;
 end loop;
 return jsonb_build_object('inserted',inserted_count);
end $$;

create or replace function public.study_word_grade(p_review bigint,p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 u uuid:=auth.uid(); r public.study_word_reviews; d date:=(now() at time zone 'Asia/Shanghai')::date;
 intervals integer[]:=array[1,3,7,15,30,60,90];next_stage integer;next_date date;chapter_date date;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_review is null or p_result is null or p_result not in ('remembered','fuzzy','forgotten')
 then raise exception 'invalid result'; end if;
 -- Always take the chapter lock before the row lock to serialize sibling ratings.
 select * into r from public.study_word_reviews where id=p_review and user_id=u;
 if not found then raise exception 'review item unavailable'; end if;
 if r.module='mother' then perform pg_advisory_xact_lock(hashtextextended(u::text||':mother:'||r.parent_key,0));end if;
 select * into r from public.study_word_reviews where id=p_review and user_id=u for update;
 if not found then raise exception 'review item unavailable';end if;
 if r.completed_at is not null then return jsonb_build_object('saved',false,'already_completed',true);end if;
 if not r.active then raise exception 'review item unavailable';end if;
 next_stage:=case p_result when 'remembered' then least(6,r.stage+1) when 'fuzzy' then greatest(0,r.stage-1) else 0 end;
 next_date:=d+intervals[next_stage+1];
 if r.module='mother' then
  select min(q.scheduled_for) into chapter_date from public.study_word_reviews q
   where q.user_id=u and q.module='mother' and q.parent_key=r.parent_key and q.id<>r.id
    and q.active and q.completed_at is null and q.scheduled_for>d;
  next_date:=least(next_date,coalesce(chapter_date,next_date));
 end if;
 update public.study_word_reviews set active=false,completed_at=now(),result=p_result where id=r.id;
 insert into public.study_word_reviews(user_id,module,parent_key,word_key,english,chinese,pattern,example,scheduled_for,stage)
  values(u,r.module,r.parent_key,r.word_key,r.english,r.chinese,r.pattern,r.example,next_date,next_stage);
 if r.module='mother' then
  update public.study_word_reviews set scheduled_for=next_date
   where user_id=u and module='mother' and parent_key=r.parent_key and active and completed_at is null
    and scheduled_for>d;
 end if;
 return jsonb_build_object('saved',true,'stage',next_stage,'scheduled_for',next_date);
end $$;
revoke all on function public.study_word_sync(jsonb),public.study_word_grade(bigint,text) from public,anon;
grant execute on function public.study_word_sync(jsonb),public.study_word_grade(bigint,text) to authenticated;
create index if not exists study_word_reviews_chapter_queue_idx
 on public.study_word_reviews(user_id,module,parent_key,scheduled_for,id) where active and completed_at is null;
commit;

-- 练习中允许“本轮待完成”和“下一轮”两个日期；整章完成后应只有一个未来日期。
select count(*) as mother_chapters_with_multiple_future_dates from (
 select user_id,parent_key from public.study_word_reviews
 where module='mother' and active and completed_at is null
  and scheduled_for>(now() at time zone 'Asia/Shanghai')::date
 group by user_id,parent_key having count(distinct scheduled_for)>1
) q;
