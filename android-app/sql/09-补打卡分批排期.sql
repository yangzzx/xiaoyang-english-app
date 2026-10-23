-- Stagger first reviews for late check-ins. Apply after the existing review migrations.
-- This replaces only the completion functions and does not rewrite existing review rows.

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

create or replace function public.day32_complete(p_day integer)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date; added integer; total integer; next_day integer; first_review date;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day is null or p_day<1 or p_day>32 then raise exception 'Invalid day'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 insert into day32_progress(user_id) values(uid) on conflict do nothing;
 first_review:=today+1+mod(mod(hashtextextended(uid::text||':root:'||p_day,0),7)+7,7)::integer;
 insert into day32_lessons(user_id,day_no,status,completed_at,next_review_at,review_stage)
  values(uid,p_day,'completed',now(),(first_review::timestamp at time zone 'Asia/Shanghai'),0)
  on conflict(user_id,day_no) do update set status='completed',completed_at=excluded.completed_at,next_review_at=excluded.next_review_at,review_stage=0
  where day32_lessons.status<>'completed';
 get diagnostics added=row_count;
 if added=1 and not exists(select 1 from day32_reviews where user_id=uid and day_no=p_day and active and completed_at is null) then
  insert into day32_reviews(user_id,day_no,scheduled_for,active,stage) values(uid,p_day,first_review,true,0)
   on conflict(user_id,day_no) where active and completed_at is null do update set active=true,paused=false,stage=0,result=null,completed_at=null
   where day32_reviews.completed_at is null;
 end if;
 select count(*) into total from day32_lessons where user_id=uid and status='completed';
 select min(n) into next_day from generate_series(1,32) as n where not exists(select 1 from day32_lessons l where l.user_id=uid and l.day_no=n and l.status='completed');
 update day32_progress set completed_days=total,current_day=coalesce(next_day,32),last_completed_at=(select max(completed_at) from day32_lessons where user_id=uid) where user_id=uid;
 return jsonb_build_object('completed_days',total,'current_day',coalesce(next_day,32),'newly_completed',added=1);
end $$;
