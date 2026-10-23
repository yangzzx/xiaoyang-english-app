-- Additive cleanup window for paused review tasks.
-- Old study records and completed review history remain untouched.

alter table public.study_reviews
  add column if not exists paused_at timestamptz;
alter table public.day32_reviews
  add column if not exists paused_at timestamptz;

-- Give tasks paused before this upgrade a fresh three-day recovery window.
update public.study_reviews
  set paused_at=now()
  where paused and not active and completed_at is null and paused_at is null;
update public.day32_reviews
  set paused_at=now()
  where paused and not active and completed_at is null and paused_at is null;

create or replace function public.study_review_manage(p_module text,p_key text,p_active boolean)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 u uuid:=auth.uid(); changed integer; d date:=(now() at time zone 'Asia/Shanghai')::date;
 stage_value integer:=0; paused_id bigint; paused_time timestamptz;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_module is null or p_module in ('plan','spell') or p_key is null or p_active is null then raise exception 'invalid review task'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_module||':'||p_key,0));
 if not exists(select 1 from public.study_records where user_id=u and module=p_module and item_key=p_key) then raise exception 'study item not found'; end if;
 if not p_active then
  update public.study_reviews set active=false,paused=true,paused_at=now()
   where user_id=u and module=p_module and item_key=p_key and active and completed_at is null;
  get diagnostics changed=row_count;
  return jsonb_build_object('saved',changed>0,'active',false,'changed',changed);
 end if;
 if exists(select 1 from public.study_reviews where user_id=u and module=p_module and item_key=p_key and active and completed_at is null) then
  return jsonb_build_object('saved',false,'active',true,'already_active',true);
 end if;
 select id,stage,paused_at into paused_id,stage_value,paused_time from public.study_reviews
  where user_id=u and module=p_module and item_key=p_key and paused and completed_at is null
  order by id desc limit 1 for update;
 if paused_id is not null and paused_time>=now()-interval '3 days' then
  update public.study_reviews set active=true,paused=false,paused_at=null,scheduled_for=d+1,result=null where id=paused_id;
  return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1,'stage',stage_value);
 end if;
 if paused_id is null then
  select coalesce(stage,0) into stage_value from public.study_reviews
   where user_id=u and module=p_module and item_key=p_key and completed_at is not null
   order by completed_at desc,id desc limit 1;
 end if;
 insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,paused,paused_at,stage)
  values(u,p_module,p_key,d+1,true,false,null,least(6,greatest(0,coalesce(stage_value,0))))
  on conflict(user_id,module,item_key) where active and completed_at is null do update
   set active=true,paused=false,paused_at=null,stage=excluded.stage,result=null,completed_at=null
   where public.study_reviews.completed_at is null;
 return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1);
end $$;

create or replace function public.day32_review_manage(p_day_no integer,p_active boolean)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date;
 changed integer; paused_id bigint; stage_value integer:=0; paused_time timestamptz;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day_no is null or p_day_no<1 or p_day_no>32 or p_active is null then raise exception 'Invalid review task'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 if not exists(select 1 from day32_lessons where user_id=uid and day_no=p_day_no and status='completed') then raise exception 'Study day is not complete'; end if;
 if not p_active then
  update day32_reviews set active=false,paused=true,paused_at=now()
   where user_id=uid and day_no=p_day_no and active and completed_at is null;
  get diagnostics changed=row_count;
  update day32_lessons set next_review_at=null where user_id=uid and day_no=p_day_no;
  return jsonb_build_object('saved',changed>0,'active',false,'changed',changed);
 end if;
 if exists(select 1 from day32_reviews where user_id=uid and day_no=p_day_no and active and completed_at is null) then
  return jsonb_build_object('saved',false,'active',true,'already_active',true);
 end if;
 select id,stage,paused_at into paused_id,stage_value,paused_time from day32_reviews
  where user_id=uid and day_no=p_day_no and paused and completed_at is null
  order by id desc limit 1 for update;
 if paused_id is not null and paused_time>=now()-interval '3 days' then
  update day32_reviews set active=true,paused=false,paused_at=null,scheduled_for=today+1,result=null where id=paused_id;
  update day32_lessons set review_stage=stage_value,next_review_at=((today+1)::timestamp at time zone 'Asia/Shanghai')
   where user_id=uid and day_no=p_day_no;
  return jsonb_build_object('saved',true,'active',true,'scheduled_for',today+1,'stage',stage_value);
 end if;
 if paused_id is null then
  select coalesce(stage,0) into stage_value from day32_reviews
   where user_id=uid and day_no=p_day_no and completed_at is not null
   order by completed_at desc,id desc limit 1;
 end if;
 stage_value:=coalesce(stage_value,0);
 insert into day32_reviews(user_id,day_no,scheduled_for,active,paused,paused_at,stage)
  values(uid,p_day_no,today+1,true,false,null,least(6,greatest(0,coalesce(stage_value,0))))
  on conflict(user_id,day_no) where active and completed_at is null do update
   set active=true,paused=false,paused_at=null,stage=excluded.stage,result=null,completed_at=null
   where day32_reviews.completed_at is null;
 update day32_lessons set review_stage=stage_value,next_review_at=((today+1)::timestamp at time zone 'Asia/Shanghai')
  where user_id=uid and day_no=p_day_no;
 return jsonb_build_object('saved',true,'active',true,'scheduled_for',today+1,'stage',stage_value);
end $$;

create or replace function public.study_review_version()
returns jsonb language plpgsql security invoker set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return jsonb_build_object('version',2,'intervals',jsonb_build_array(1,3,7,15,30,60,90),'active_task_limit',1,'removed_task_retention_days',3);
end $$;

revoke all on function public.study_review_manage(text,text,boolean),public.day32_review_manage(integer,boolean),public.study_review_version() from public,anon;
grant execute on function public.study_review_manage(text,text,boolean),public.day32_review_manage(integer,boolean),public.study_review_version() to authenticated;
