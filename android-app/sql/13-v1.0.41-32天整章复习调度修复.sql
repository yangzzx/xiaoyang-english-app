-- v1.0.41：基于 v1.0.39 的 32 天章节复习调度修复。
-- 此文件仅交付给维护者在 Supabase SQL Editor 中手动执行；本次没有执行云端 SQL。
-- 适用：已具备 06/07 的 active、paused、stage 字段和单章节唯一有效任务索引。
-- 不要为执行本文件重新运行旧的 01～12，尤其不要重跑 06。
-- 作用：新打卡次日开始整章复习；既有首次未复习章节按原打卡次日校正。
-- 保留学习内容、打卡时间、已完成复习历史；不恢复用户移出的任务。
-- 未完成的旧 root 单词队列保留原样，新客户端只使用 day32_reviews 做整章复习。
begin;
do $$
begin
 if to_regclass('public.day32_lessons') is null or to_regclass('public.day32_reviews') is null
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='day32_reviews' and column_name='active')
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='day32_reviews' and column_name='paused')
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='day32_reviews' and column_name='stage')
    or to_regprocedure('public.study_review_interval(integer)') is null
    or to_regclass('public.day32_reviews_one_active_day_idx') is null
 then raise exception '缺少既有复习升级结构，请先导出结构与函数定义核对；不要重复执行旧迁移。';
 end if;
end $$;

create or replace function public.day32_complete(p_day integer)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(now() at time zone 'Asia/Shanghai')::date; added integer; total integer; next_day integer; first_review date;
begin
 if uid is null then raise exception 'Please sign in'; end if;
 if p_day is null or p_day<1 or p_day>32 then raise exception 'Invalid day'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,32));
 insert into day32_progress(user_id) values(uid) on conflict do nothing;
 first_review:=today+1;
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

revoke all on function public.day32_complete(integer) from public,anon;
grant execute on function public.day32_complete(integer) to authenticated;

-- 只校正从未提交过反馈的章节首轮任务；已评分后的间隔原样保留。
update public.day32_reviews r
set scheduled_for=(l.completed_at at time zone 'Asia/Shanghai')::date+1
from public.day32_lessons l
where r.user_id=l.user_id and r.day_no=l.day_no and l.status='completed'
 and l.completed_at is not null and r.active and not r.paused
 and r.completed_at is null and r.stage=0
 and not exists(select 1 from public.day32_reviews h where h.user_id=r.user_id and h.day_no=r.day_no and h.completed_at is not null)
 and r.scheduled_for is distinct from (l.completed_at at time zone 'Asia/Shanghai')::date+1;

-- 同一章节的进度提示与复习中心共用一份排期。
update public.day32_lessons l
set next_review_at=(q.next_date::timestamp at time zone 'Asia/Shanghai')
from (select user_id,day_no,min(scheduled_for) next_date from public.day32_reviews
 where active and not paused and completed_at is null group by user_id,day_no) q
where l.user_id=q.user_id and l.day_no=q.day_no and l.status='completed'
 and l.next_review_at is distinct from (q.next_date::timestamp at time zone 'Asia/Shanghai');

create index if not exists day32_reviews_queue_order_idx
 on public.day32_reviews(user_id,scheduled_for,day_no,id) where active and not paused and completed_at is null;
commit;

-- 执行后核对（只展示聚合数量，不包含账户身份或学习正文）：
select count(*) as completed_chapters,
 count(*) filter(where next_review_at is not null) as chapters_with_next_review
from public.day32_lessons where status='completed';
