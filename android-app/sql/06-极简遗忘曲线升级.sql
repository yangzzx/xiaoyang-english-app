-- Additive review upgrade. Existing vocabulary, study records, and review history are retained.
-- Apply after 01-基础表与隔离规则.sql and 04-其他模块云端记录.sql.

alter table public.study_reviews
  add column if not exists active boolean not null default true,
  add column if not exists paused boolean not null default false,
  add column if not exists stage smallint not null default 0;
alter table public.day32_reviews
  add column if not exists active boolean not null default true,
  add column if not exists paused boolean not null default false,
  add column if not exists stage smallint not null default 0;

-- Review rows are history events; only the partial index below constrains live work.
alter table public.study_reviews drop constraint if exists study_reviews_user_id_module_item_key_scheduled_for_key;
alter table public.day32_reviews drop constraint if exists day32_reviews_user_id_day_no_scheduled_for_key;

alter table public.day32_lessons drop constraint if exists day32_lessons_review_stage_check;
alter table public.day32_lessons add constraint day32_lessons_review_stage_check check (review_stage between 0 and 6);
alter table public.day32_lessons add column if not exists review_result text;

-- Keep one pending task per item. Extra old tasks remain in the database, inactive and recoverable.
update public.study_reviews set active=false where completed_at is not null or module='spell';
with ranked as (
  select id,row_number() over(partition by user_id,module,item_key order by scheduled_for,id) as position
  from public.study_reviews where completed_at is null and module<>'spell'
)
update public.study_reviews r set active=(ranked.position=1)
from ranked where ranked.id=r.id;

with ranked as (
  select id,row_number() over(partition by user_id,day_no order by scheduled_for,id) as position
  from public.day32_reviews where completed_at is null
)
update public.day32_reviews r set active=(ranked.position=1)
from ranked where ranked.id=r.id;
update public.day32_reviews set active=false where completed_at is not null;

create unique index if not exists study_reviews_one_active_item_idx
  on public.study_reviews(user_id,module,item_key) where active and completed_at is null;
create unique index if not exists day32_reviews_one_active_day_idx
  on public.day32_reviews(user_id,day_no) where active and completed_at is null;

create or replace function public.study_review_interval(p_stage integer)
returns integer language sql immutable as $$
  select case greatest(0,least(6,coalesce(p_stage,0)))
    when 0 then 1 when 1 then 3 when 2 then 7 when 3 then 15
    when 4 then 30 when 5 then 60 else 90 end
$$;

create or replace function public.study_complete(p_module text,p_key text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); r public.study_records; was_done boolean; d date:=(now() at time zone 'Asia/Shanghai')::date;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_module='plan' or p_module='spell' then raise exception 'this module does not create review tasks'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_module||':'||p_key,0));
 perform public.study_save(p_module,p_key,p_data);
 select * into r from public.study_records where user_id=u and module=p_module and item_key=p_key for update;
 was_done:=r.completed_at is not null;
 if not was_done then
  update public.study_records set completed_at=now(),updated_at=now() where user_id=u and module=p_module and item_key=p_key returning * into r;
  if not exists(select 1 from public.study_reviews where user_id=u and module=p_module and item_key=p_key and active and completed_at is null) then
    insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,stage)
      values(u,p_module,p_key,d+1+mod(mod(hashtextextended(u::text||':'||p_module||':'||p_key,0),7)+7,7)::integer,true,0)
      on conflict(user_id,module,item_key) where active and completed_at is null do update
        set active=true,paused=false,stage=0,result=null,completed_at=null
        where public.study_reviews.completed_at is null;
  end if;
 end if;
 return jsonb_build_object('record',to_jsonb(r),'already_completed',was_done);
end $$;

create or replace function public.study_grade(p_review bigint,p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 u uuid:=auth.uid(); r public.study_reviews; d date:=(now() at time zone 'Asia/Shanghai')::date;
 next_stage integer; interval_days integer; changed integer;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'invalid grade'; end if;
 select * into r from public.study_reviews where user_id=u and id=p_review for update;
 if not found then raise exception 'review not found'; end if;
 if r.completed_at is not null or not r.active then return jsonb_build_object('already_completed',true,'saved',false); end if;
 if r.scheduled_for>d then raise exception 'review not due'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||r.module||':'||r.item_key,0));
 update public.study_reviews set completed_at=now(),result=p_result,active=false
  where id=r.id and user_id=u and active and completed_at is null;
 get diagnostics changed=row_count;
 if changed=0 then return jsonb_build_object('already_completed',true,'saved',false); end if;
 next_stage:=case p_result when 'remembered' then least(6,r.stage+1) when 'fuzzy' then greatest(0,r.stage-1) else 0 end;
 interval_days:=public.study_review_interval(next_stage);
 update public.study_records set data=data||jsonb_build_object('review_result',p_result,'review_stage',next_stage,'last_reviewed_at',now()),updated_at=now()
  where user_id=u and module=r.module and item_key=r.item_key;
 insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,stage)
  values(u,r.module,r.item_key,d+interval_days,true,next_stage)
  on conflict(user_id,module,item_key) where active and completed_at is null do update
    set active=true,paused=false,stage=excluded.stage,result=null,completed_at=null
    where public.study_reviews.completed_at is null;
 return jsonb_build_object('saved',true,'already_completed',false,'next_review',d+interval_days,'interval_days',interval_days,'stage',next_stage);
end $$;

create or replace function public.study_grade_many(p_reviews bigint[],p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare review_id bigint; result jsonb; processed integer:=0; interval_days integer:=0;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 if p_reviews is null or cardinality(p_reviews) not between 1 and 200 then raise exception 'invalid reviews'; end if;
 if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'invalid grade'; end if;
 for review_id in select distinct unnest(p_reviews) loop
  result:=public.study_grade(review_id,p_result);
  if coalesce((result->>'saved')::boolean,false) then
    processed:=processed+1;
    interval_days:=greatest(interval_days,coalesce((result->>'interval_days')::integer,0));
  end if;
 end loop;
 return jsonb_build_object('saved',processed>0,'processed',processed,'interval_days',interval_days,'already_completed',processed=0);
end $$;

create or replace function public.study_review_manage(p_module text,p_key text,p_active boolean)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); changed integer; d date:=(now() at time zone 'Asia/Shanghai')::date; stage_value integer:=0; paused_id bigint;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_module is null or p_module in ('plan','spell') or p_key is null or p_active is null then raise exception 'invalid review task'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_module||':'||p_key,0));
 if not exists(select 1 from public.study_records where user_id=u and module=p_module and item_key=p_key) then raise exception 'study item not found'; end if;
 if not p_active then
  update public.study_reviews set active=false,paused=true where user_id=u and module=p_module and item_key=p_key and active and completed_at is null;
  get diagnostics changed=row_count;
  return jsonb_build_object('saved',changed>0,'active',false,'changed',changed);
 end if;
 if exists(select 1 from public.study_reviews where user_id=u and module=p_module and item_key=p_key and active and completed_at is null) then
  return jsonb_build_object('saved',false,'active',true,'already_active',true);
 end if;
 select id,stage into paused_id,stage_value from public.study_reviews where user_id=u and module=p_module and item_key=p_key and paused and completed_at is null order by id desc limit 1 for update;
 if paused_id is not null then
  update public.study_reviews set active=true,paused=false,scheduled_for=d+1,result=null where id=paused_id;
  return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1,'stage',stage_value);
 end if;
 select coalesce(stage,0) into stage_value from public.study_reviews
  where user_id=u and module=p_module and item_key=p_key and completed_at is not null
  order by completed_at desc,id desc limit 1;
 insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,stage)
  values(u,p_module,p_key,d+1,true,least(6,greatest(0,coalesce(stage_value,0))))
  on conflict(user_id,module,item_key) where active and completed_at is null do update
   set active=true,paused=false,stage=excluded.stage,result=null,completed_at=null
   where public.study_reviews.completed_at is null;
 return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1);
end $$;

create or replace function public.study_spell_answer(p_key text,p_correct boolean,p_attempt uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); r public.study_records; streak integer; first_answer boolean; inserted integer;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_correct is null or p_attempt is null then raise exception 'invalid answer'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':spell:'||p_key,0));
 insert into public.study_answers(user_id,attempt_id,module,item_key,correct) values(u,p_attempt,'spell',p_key,p_correct) on conflict do nothing;
 get diagnostics inserted=row_count;
 if inserted=0 then return jsonb_build_object('duplicate',true); end if;
 perform public.study_save('spell',p_key,p_data);
 select * into r from public.study_records where user_id=u and module='spell' and item_key=p_key for update;
 first_answer:=not(r.data?'answer_count');
 streak:=case when p_correct then coalesce((r.data->>'streak')::integer,0)+1 else 0 end;
 update public.study_records set data=data||jsonb_build_object('streak',streak,'answer_count',coalesce((data->>'answer_count')::integer,0)+1,'wrong_count',coalesce((data->>'wrong_count')::integer,0)+case when p_correct then 0 else 1 end,'last_correct',p_correct,'last_answered_at',now(),'mastered',streak>=2),completed_at=case when streak>=2 then coalesce(completed_at,now()) else null end,updated_at=now()
  where user_id=u and module='spell' and item_key=p_key returning * into r;
 return jsonb_build_object('duplicate',false,'record',to_jsonb(r),'review_independent',true);
end $$;

create or replace function public.day32_complete(p_day integer)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date; added integer; total integer; next_day integer;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day is null or p_day<1 or p_day>32 then raise exception 'Invalid day'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 insert into day32_progress(user_id) values(uid) on conflict do nothing;
 insert into day32_lessons(user_id,day_no,status,completed_at,next_review_at,review_stage)
  values(uid,p_day,'completed',now(),(today+1+mod(mod(hashtextextended(uid::text||':root:'||p_day,0),7)+7,7)::integer)::timestamp at time zone 'Asia/Shanghai',0)
  on conflict(user_id,day_no) do update set status='completed',completed_at=excluded.completed_at,next_review_at=excluded.next_review_at,review_stage=0
  where day32_lessons.status<>'completed';
 get diagnostics added=row_count;
 if added=1 and not exists(select 1 from day32_reviews where user_id=uid and day_no=p_day and active and completed_at is null) then
  insert into day32_reviews(user_id,day_no,scheduled_for,active,stage) values(uid,p_day,today+1+mod(mod(hashtextextended(uid::text||':root:'||p_day,0),7)+7,7)::integer,true,0)
   on conflict(user_id,day_no) where active and completed_at is null do update set active=true,paused=false,stage=0,result=null,completed_at=null
   where day32_reviews.completed_at is null;
 end if;
 select count(*) into total from day32_lessons where user_id=uid and status='completed';
 select min(n) into next_day from generate_series(1,32) as n where not exists(select 1 from day32_lessons l where l.user_id=uid and l.day_no=n and l.status='completed');
 update day32_progress set completed_days=total,current_day=coalesce(next_day,32),last_completed_at=(select max(completed_at) from day32_lessons where user_id=uid) where user_id=uid;
 return jsonb_build_object('completed_days',total,'current_day',coalesce(next_day,32),'newly_completed',added=1);
end $$;

create or replace function public.day32_grade(p_review bigint,p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date; r public.day32_reviews; next_stage integer; interval_days integer; changed integer;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'Invalid result'; end if;
 select * into r from day32_reviews where id=p_review and user_id=uid for update;
 if not found then raise exception 'Review not found'; end if;
 if r.completed_at is not null or not r.active then return jsonb_build_object('already_completed',true,'saved',false); end if;
 if r.scheduled_for>today then raise exception 'Review is not due'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 update day32_reviews set result=p_result,completed_at=now(),active=false where id=r.id and user_id=uid and active and completed_at is null;
 get diagnostics changed=row_count;
 if changed=0 then return jsonb_build_object('already_completed',true,'saved',false); end if;
 next_stage:=case p_result when 'remembered' then least(6,r.stage+1) when 'fuzzy' then greatest(0,r.stage-1) else 0 end;
 interval_days:=public.study_review_interval(next_stage);
 update day32_lessons set review_result=p_result where user_id=uid and day_no=r.day_no;
 insert into day32_reviews(user_id,day_no,scheduled_for,active,stage) values(uid,r.day_no,today+interval_days,true,next_stage)
  on conflict(user_id,day_no) where active and completed_at is null do update set active=true,paused=false,stage=excluded.stage,result=null,completed_at=null
  where day32_reviews.completed_at is null;
 update day32_lessons set review_stage=next_stage,next_review_at=((today+interval_days)::timestamp at time zone 'Asia/Shanghai') where user_id=uid and day_no=r.day_no;
 return jsonb_build_object('saved',true,'next_review',today+interval_days,'interval_days',interval_days,'stage',next_stage);
end $$;

create or replace function public.day32_grade_day(p_day_no integer,p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); review_id bigint; item_result jsonb; processed integer:=0; next_review date;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day_no is null or p_day_no<1 or p_day_no>32 then raise exception 'Invalid day'; end if;
 if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'Invalid result'; end if;
 for review_id in select id from day32_reviews where user_id=uid and day_no=p_day_no and active and completed_at is null and scheduled_for<=(now() at time zone 'Asia/Shanghai')::date order by id loop
  item_result:=public.day32_grade(review_id,p_result);
  if coalesce((item_result->>'saved')::boolean,false) then processed:=processed+1; next_review:=(item_result->>'next_review')::date; end if;
 end loop;
 return jsonb_build_object('saved',processed>0,'processed',processed,'next_review',next_review,'already_completed',processed=0);
end $$;

create or replace function public.day32_review_manage(p_day_no integer,p_active boolean)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date; changed integer; paused_id bigint; stage_value integer;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day_no is null or p_day_no<1 or p_day_no>32 or p_active is null then raise exception 'Invalid review task'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 if not exists(select 1 from day32_lessons where user_id=uid and day_no=p_day_no and status='completed') then raise exception 'Study day is not complete'; end if;
 if not p_active then
 update day32_reviews set active=false,paused=true where user_id=uid and day_no=p_day_no and active and completed_at is null;
  get diagnostics changed=row_count;
  update day32_lessons set next_review_at=null where user_id=uid and day_no=p_day_no;
  return jsonb_build_object('saved',changed>0,'active',false,'changed',changed);
 end if;
 if exists(select 1 from day32_reviews where user_id=uid and day_no=p_day_no and active and completed_at is null) then return jsonb_build_object('saved',false,'active',true,'already_active',true); end if;
 select id,stage into paused_id,stage_value from day32_reviews where user_id=uid and day_no=p_day_no and paused and completed_at is null order by id desc limit 1 for update;
 if paused_id is not null then
  update day32_reviews set active=true,paused=false,scheduled_for=today+1,result=null where id=paused_id;
  update day32_lessons set review_stage=stage_value,next_review_at=((today+1)::timestamp at time zone 'Asia/Shanghai') where user_id=uid and day_no=p_day_no;
  return jsonb_build_object('saved',true,'active',true,'scheduled_for',today+1,'stage',stage_value);
 end if;
 insert into day32_reviews(user_id,day_no,scheduled_for,active,stage) values(uid,p_day_no,today+1,true,0)
  on conflict(user_id,day_no) where active and completed_at is null do update set active=true,paused=false,stage=0,result=null,completed_at=null
  where day32_reviews.completed_at is null;
 update day32_lessons set review_stage=0,next_review_at=((today+1)::timestamp at time zone 'Asia/Shanghai') where user_id=uid and day_no=p_day_no;
 return jsonb_build_object('saved',true,'active',true,'scheduled_for',today+1);
end $$;

revoke all on function public.study_review_interval(integer),public.study_review_manage(text,text,boolean),public.day32_review_manage(integer,boolean) from public,anon;
grant execute on function public.study_review_interval(integer),public.study_review_manage(text,text,boolean),public.day32_review_manage(integer,boolean) to authenticated;
revoke all on function public.study_complete(text,text,jsonb),public.study_grade(bigint,text),public.study_grade_many(bigint[],text),public.study_spell_answer(text,boolean,uuid,jsonb),public.day32_complete(integer),public.day32_grade(bigint,text),public.day32_grade_day(integer,text) from public,anon;
grant execute on function public.study_complete(text,text,jsonb),public.study_grade(bigint,text),public.study_grade_many(bigint[],text),public.study_spell_answer(text,boolean,uuid,jsonb),public.day32_complete(integer),public.day32_grade(bigint,text),public.day32_grade_day(integer,text) to authenticated;

create or replace function public.study_review_version()
returns jsonb language plpgsql security invoker set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return jsonb_build_object('version',1,'intervals',jsonb_build_array(1,3,7,15,30,60,90),'active_task_limit',1);
end $$;
revoke all on function public.study_review_version() from public,anon;
grant execute on function public.study_review_version() to authenticated;
