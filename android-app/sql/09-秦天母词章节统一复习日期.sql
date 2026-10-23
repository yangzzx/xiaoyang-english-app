-- 秦天母词章节复习日期统一迁移。
-- 只处理当前用户自己的未完成、有效复习任务；已完成历史不改。

update public.study_word_reviews as r
set scheduled_for = g.first_scheduled_for
from (
  select user_id, parent_key, min(scheduled_for) as first_scheduled_for
  from public.study_word_reviews
  where module = 'mother'
    and active = true
    and completed_at is null
  group by user_id, parent_key
) as g
where r.user_id = g.user_id
  and r.module = 'mother'
  and r.parent_key = g.parent_key
  and r.active = true
  and r.completed_at is null
  and r.scheduled_for is distinct from g.first_scheduled_for;

create or replace function public.study_word_sync(p_items jsonb)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
  u uuid := auth.uid();
  d date := (now() at time zone 'Asia/Shanghai')::date;
  item jsonb;
  inserted_count integer := 0;
  parent_module text;
  parent_key text;
  word_module text;
  word_key text;
  en text;
  zh text;
  schedule_key text;
begin
  if u is null then raise exception 'authentication required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 3000 then
    raise exception 'invalid review items';
  end if;

  for item in select value from jsonb_array_elements(p_items) loop
    word_module := item->>'module';
    parent_module := item->>'parent_module';
    parent_key := item->>'parent_key';
    word_key := item->>'word_key';
    en := left(trim(item->>'english'), 160);
    zh := left(trim(item->>'chinese'), 500);

    if word_module not in ('root','core','mother','phon','phonics')
       or coalesce(en, '') = '' or coalesce(zh, '') = '' then
      continue;
    end if;

    if parent_module = 'root' then
      if not exists (
        select 1 from public.day32_lessons
        where user_id = u and day_no = parent_key::integer and status = 'completed'
      ) then continue; end if;
    else
      if not exists (
        select 1 from public.study_records
        where user_id = u and module = parent_module and item_key = parent_key and completed_at is not null
      ) then continue; end if;
    end if;

    -- 秦天母词按组排期；其他模块保留原来的单词级排期。
    schedule_key := case when word_module = 'mother' then coalesce(parent_key, '') else coalesce(word_key, '') end;
    insert into public.study_word_reviews(
      user_id, module, parent_key, word_key, english, chinese, pattern, example, scheduled_for
    ) values (
      u, word_module, parent_key, word_key, en, zh,
      left(item->>'pattern', 240), left(item->>'example', 500),
      d + 1 + mod(mod(hashtextextended(
        u::text || ':' || word_module || ':' || schedule_key, 0
      ), 7) + 7, 7)::integer
    ) on conflict do nothing;

    if found then inserted_count := inserted_count + 1; end if;
  end loop;

  return jsonb_build_object('inserted', inserted_count);
end $$;

revoke all on function public.study_word_sync(jsonb) from public, anon;
grant execute on function public.study_word_sync(jsonb) to authenticated;

create or replace function public.study_word_grade(p_review bigint, p_result text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare
  u uuid := auth.uid();
  r public.study_word_reviews;
  d date := (now() at time zone 'Asia/Shanghai')::date;
  intervals integer[] := array[1,3,7,15,30,60,90];
  next_stage integer;
  next_date date;
begin
  if u is null then raise exception 'authentication required'; end if;
  if p_result not in ('remembered','fuzzy','forgotten') then raise exception 'invalid result'; end if;

  select * into r
  from public.study_word_reviews
  where id = p_review and user_id = u and active and completed_at is null
  for update;
  if not found then raise exception 'review item unavailable'; end if;

  next_stage := case p_result
    when 'remembered' then least(6, r.stage + 1)
    when 'fuzzy' then greatest(0, r.stage - 1)
    else 0
  end;
  next_date := d + intervals[next_stage + 1];

  update public.study_word_reviews
  set active = false, completed_at = now(), result = p_result
  where id = r.id;

  insert into public.study_word_reviews(
    user_id, module, parent_key, word_key, english, chinese, pattern, example,
    scheduled_for, stage
  ) values (
    u, r.module, r.parent_key, r.word_key, r.english, r.chinese, r.pattern, r.example,
    next_date, next_stage
  );

  -- 秦天母词按章节统一下一次复习时间；其他模块维持单词级间隔。
  if r.module = 'mother' then
    update public.study_word_reviews
    set scheduled_for = next_date
    where user_id = u
      and module = 'mother'
      and parent_key = r.parent_key
      and active = true
      and completed_at is null;
  end if;

  return jsonb_build_object('saved', true, 'stage', next_stage, 'scheduled_for', next_date);
end $$;

revoke all on function public.study_word_grade(bigint, text) from public, anon;
grant execute on function public.study_word_grade(bigint, text) to authenticated;
