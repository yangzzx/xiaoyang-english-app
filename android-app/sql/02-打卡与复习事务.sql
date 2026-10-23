-- 仅新增函数，保留现有三张表及已有进度。所有操作使用调用者的 RLS 权限。
create or replace function public.day32_complete(p_day integer)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Shanghai')::date;
  added integer; total integer; next_day integer;
begin
  if uid is null then raise exception 'Please sign in'; end if;
  if p_day is null or p_day < 1 or p_day > 32 then raise exception 'Invalid day'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 32));
  insert into day32_progress(user_id) values(uid) on conflict do nothing;
  insert into day32_lessons(user_id,day_no,status,completed_at,next_review_at)
    values(uid,p_day,'completed',now(),((today+1)::timestamp at time zone 'Asia/Shanghai'))
    on conflict(user_id,day_no) do update set status='completed',completed_at=excluded.completed_at,
      next_review_at=excluded.next_review_at
      where day32_lessons.status <> 'completed';
  get diagnostics added = row_count;
  -- 同一课重复打卡不覆盖完成时间，也不重置复习记录。
  if added = 1 then
    insert into day32_reviews(user_id,day_no,scheduled_for)
      select uid,p_day,today+n from unnest(array[1,3,7,14]) as n
      on conflict do nothing;
  end if;
  select count(*) into total from day32_lessons where user_id=uid and status='completed';
  select min(n) into next_day from generate_series(1,32) as n
    where not exists(select 1 from day32_lessons l where l.user_id=uid and l.day_no=n and l.status='completed');
  update day32_progress set completed_days=total,current_day=coalesce(next_day,32),
    last_completed_at=(select max(completed_at) from day32_lessons where user_id=uid)
    where user_id=uid;
  return jsonb_build_object('completed_days',total,'current_day',coalesce(next_day,32),'newly_completed',added=1);
end $$;

create or replace function public.day32_grade_day(p_day_no integer, p_result text)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Shanghai')::date;
  changed integer := 0;
  extra boolean := false;
begin
  if uid is null then raise exception 'Please sign in'; end if;
  if p_day_no is null or p_day_no < 1 or p_day_no > 32 then raise exception 'Invalid day'; end if;
  if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'Invalid result'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
  update day32_reviews
    set result=p_result, completed_at=now()
    where user_id=uid and day_no=p_day_no and completed_at is null and scheduled_for<=today;
  get diagnostics changed = row_count;
  if changed=0 then
    return jsonb_build_object('already_completed',true,'saved',false,'processed',0);
  end if;
  if p_result in ('fuzzy','forgotten') then
    insert into day32_reviews(user_id,day_no,scheduled_for)
      values(uid,p_day_no,today+1) on conflict do nothing;
    extra := true;
  end if;
  update day32_lessons set next_review_at=(
    select (min(scheduled_for)::timestamp at time zone 'Asia/Shanghai')
    from day32_reviews where user_id=uid and day_no=p_day_no and completed_at is null
  ) where user_id=uid and day_no=p_day_no;
  return jsonb_build_object('saved',true,'processed',changed,'extra_review_tomorrow',extra);
end $$;

create or replace function public.day32_import(p_through integer)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare n integer; result jsonb;
begin
  if auth.uid() is null then raise exception 'Please sign in'; end if;
  if p_through is null or p_through < 1 or p_through > 32 then raise exception 'Invalid day'; end if;
  for n in 1..p_through loop result := day32_complete(n); end loop;
  return result;
end $$;

create or replace function public.day32_grade(p_review bigint, p_result text)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Shanghai')::date;
  r day32_reviews%rowtype;
begin
  if uid is null then raise exception 'Please sign in'; end if;
  if p_result is null or p_result not in ('remembered','fuzzy','forgotten') then raise exception 'Invalid result'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
  select * into r from day32_reviews where id=p_review and user_id=uid for update;
  if not found then raise exception 'Review not found'; end if;
  if r.completed_at is not null then return jsonb_build_object('already_completed',true); end if;
  if r.scheduled_for > today then raise exception 'Review is not due'; end if;
  update day32_reviews set result=p_result,completed_at=now() where id=r.id and user_id=uid;
  if p_result in ('fuzzy','forgotten') then
    insert into day32_reviews(user_id,day_no,scheduled_for) values(uid,r.day_no,today+1) on conflict do nothing;
  end if;
  update day32_lessons set next_review_at=(
    select (min(scheduled_for)::timestamp at time zone 'Asia/Shanghai')
    from day32_reviews where user_id=uid and day_no=r.day_no and completed_at is null
  ) where user_id=uid and day_no=r.day_no;
  return jsonb_build_object('saved',true,'extra_review_tomorrow',p_result<>'remembered');
end $$;

revoke execute on function public.day32_complete(integer) from public,anon;
revoke execute on function public.day32_import(integer) from public,anon;
revoke execute on function public.day32_grade(bigint,text) from public,anon;
revoke execute on function public.day32_grade_day(integer,text) from public,anon;
grant execute on function public.day32_complete(integer) to authenticated;
grant execute on function public.day32_import(integer) to authenticated;
grant execute on function public.day32_grade(bigint,text) to authenticated;
grant execute on function public.day32_grade_day(integer,text) to authenticated;
