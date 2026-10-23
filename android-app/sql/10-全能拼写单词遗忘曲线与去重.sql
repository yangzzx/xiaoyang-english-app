-- One active spelling review per normalized English word.
-- Keeps existing practice records and completed history.

create or replace function public.study_spell_answer(p_key text,p_correct boolean,p_attempt uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
 u uuid:=auth.uid(); r public.study_records; canonical text; review_key text;
 streak integer; inserted integer; stage_value integer:=0; d date:=(now() at time zone 'Asia/Shanghai')::date;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_key is null or p_correct is null or p_attempt is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid answer'; end if;
 canonical:=regexp_replace(lower(coalesce(nullif(trim(p_data->>'canonical_word'),''),nullif(trim(p_data->>'title'),''),p_key)),'[^a-z0-9]','','g');
 if canonical='' then raise exception 'invalid spelling word'; end if;
 review_key:='word:'||canonical;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':spell-word:'||canonical,0));
 perform pg_advisory_xact_lock(hashtextextended(u::text||':spell:'||p_key,0));
 insert into public.study_answers(user_id,attempt_id,module,item_key,correct) values(u,p_attempt,'spell',p_key,p_correct) on conflict do nothing;
 get diagnostics inserted=row_count;
 if inserted=0 then return jsonb_build_object('duplicate',true); end if;
 perform public.study_save('spell',p_key,p_data);
 select * into r from public.study_records where user_id=u and module='spell' and item_key=p_key for update;
 streak:=case when p_correct then coalesce((r.data->>'streak')::integer,0)+1 else 0 end;
 update public.study_records set data=data||jsonb_build_object('streak',streak,'answer_count',coalesce((data->>'answer_count')::integer,0)+1,'wrong_count',coalesce((data->>'wrong_count')::integer,0)+case when p_correct then 0 else 1 end,'last_correct',p_correct,'last_answered_at',now(),'mastered',streak>=2),completed_at=case when streak>=2 then coalesce(completed_at,now()) else null end,updated_at=now() where user_id=u and module='spell' and item_key=p_key returning * into r;
 perform public.study_save('spell',review_key,p_data||jsonb_build_object('title',coalesce(nullif(p_data->>'title',''),canonical),'canonical_word',canonical));
 if not exists(select 1 from public.study_reviews where user_id=u and module='spell' and item_key=review_key and completed_at is null and (active or paused)) then
  select coalesce(stage,0) into stage_value from public.study_reviews where user_id=u and module='spell' and item_key=review_key and completed_at is not null order by completed_at desc,id desc limit 1;
  insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,paused,stage) values(u,'spell',review_key,d+1,true,false,least(6,greatest(0,coalesce(stage_value,0)))) on conflict(user_id,module,item_key) where active and completed_at is null do nothing;
 end if;
 return jsonb_build_object('duplicate',false,'record',to_jsonb(r),'review_key',review_key,'review_scheduled_for',d+1);
end $$;

-- Consolidate active legacy spelling tasks by normalized word.
with old as (
 select r.id,r.user_id,r.item_key,
  'word:'||regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(r.item_key,'^.*:',''))),'[^a-z0-9]','','g') canonical,
  row_number() over(partition by r.user_id,regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(r.item_key,'^.*:',''))),'[^a-z0-9]','','g') order by r.stage desc,r.scheduled_for,r.id) pos
 from public.study_reviews r left join public.study_records s on s.user_id=r.user_id and s.module='spell' and s.item_key=r.item_key
 where r.module='spell' and r.active and r.completed_at is null
), duplicates as (
 update public.study_reviews r set active=false,paused=true,paused_at=now() from old o where r.id=o.id and o.pos>1 returning r.id
)
update public.study_reviews r set item_key=o.canonical from old o where r.id=o.id and o.pos=1 and r.item_key<>o.canonical;

-- Ensure canonical records exist for current review cards and management.
insert into public.study_records(user_id,module,item_key,data)
select distinct on (s.user_id,'word:'||regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(s.item_key,'^.*:',''))),'[^a-z0-9]','','g'))
 s.user_id,'spell','word:'||regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(s.item_key,'^.*:',''))),'[^a-z0-9]','','g'),
 s.data||jsonb_build_object('title',coalesce(nullif(s.data->>'title',''),regexp_replace(s.item_key,'^.*:','')),'canonical_word',regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(s.item_key,'^.*:',''))),'[^a-z0-9]','','g'))
from public.study_records s where s.module='spell'
order by s.user_id,'word:'||regexp_replace(lower(coalesce(nullif(trim(s.data->>'canonical_word'),''),nullif(trim(s.data->>'title'),''),regexp_replace(s.item_key,'^.*:',''))),'[^a-z0-9]','','g'),s.updated_at desc
on conflict(user_id,module,item_key) do update set data=study_records.data||excluded.data,updated_at=now();

-- Add already-practiced words to the new queue unless an active or paused task exists.
insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,paused,stage)
select s.user_id,'spell',s.item_key,(now() at time zone 'Asia/Shanghai')::date+1,true,false,0
from public.study_records s
where s.module='spell' and s.item_key like 'word:%' and coalesce((s.data->>'answer_count')::integer,0)>0
  and not exists(select 1 from public.study_reviews r where r.user_id=s.user_id and r.module='spell' and r.item_key=s.item_key and r.completed_at is null and (r.active or r.paused))
on conflict(user_id,module,item_key) where active and completed_at is null do nothing;

create or replace function public.study_review_manage(p_module text,p_key text,p_active boolean)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); changed integer; d date:=(now() at time zone 'Asia/Shanghai')::date; stage_value integer:=0; paused_id bigint; paused_time timestamptz;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_module is null or p_module='plan' or p_key is null or p_active is null then raise exception 'invalid review task'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_module||':'||p_key,0));
 if not exists(select 1 from public.study_records where user_id=u and module=p_module and item_key=p_key) then raise exception 'study item not found'; end if;
 if not p_active then
  update public.study_reviews set active=false,paused=true,paused_at=now() where user_id=u and module=p_module and item_key=p_key and active and completed_at is null;
  get diagnostics changed=row_count; return jsonb_build_object('saved',changed>0,'active',false,'changed',changed);
 end if;
 if exists(select 1 from public.study_reviews where user_id=u and module=p_module and item_key=p_key and active and completed_at is null) then return jsonb_build_object('saved',false,'active',true,'already_active',true); end if;
 select id,stage,paused_at into paused_id,stage_value,paused_time from public.study_reviews where user_id=u and module=p_module and item_key=p_key and paused and completed_at is null order by id desc limit 1 for update;
 if paused_id is not null and paused_time>=now()-interval '3 days' then
  update public.study_reviews set active=true,paused=false,paused_at=null,scheduled_for=d+1,result=null where id=paused_id;
  return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1,'stage',stage_value);
 end if;
 if paused_id is null then select coalesce(stage,0) into stage_value from public.study_reviews where user_id=u and module=p_module and item_key=p_key and completed_at is not null order by completed_at desc,id desc limit 1; end if;
 insert into public.study_reviews(user_id,module,item_key,scheduled_for,active,paused,paused_at,stage) values(u,p_module,p_key,d+1,true,false,null,least(6,greatest(0,coalesce(stage_value,0)))) on conflict(user_id,module,item_key) where active and completed_at is null do update set active=true,paused=false,paused_at=null,stage=excluded.stage,result=null,completed_at=null where public.study_reviews.completed_at is null;
 return jsonb_build_object('saved',true,'active',true,'scheduled_for',d+1);
end $$;

revoke all on function public.study_spell_answer(text,boolean,uuid,jsonb),public.study_review_manage(text,text,boolean) from public,anon;
grant execute on function public.study_spell_answer(text,boolean,uuid,jsonb),public.study_review_manage(text,text,boolean) to authenticated;
