-- Fix cancellation against the actual word-review schema.
-- No existing learning or review records are changed by this migration.
create or replace function public.study_uncomplete(p_module text,p_key text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); changed integer;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_module in ('plan','spell','root') or p_module is null or p_key is null then raise exception 'invalid study item'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_module||':'||p_key,0));
 update public.study_records set completed_at=null,updated_at=now() where user_id=u and module=p_module and item_key=p_key and completed_at is not null;
 get diagnostics changed=row_count;
 update public.study_reviews set active=false,paused=false,paused_at=null where user_id=u and module=p_module and item_key=p_key and completed_at is null;
 update public.study_word_reviews set active=false where user_id=u and module=p_module and parent_key=p_key and completed_at is null;
 return jsonb_build_object('saved',changed>0,'completed',false,'removed_from_review',true);
end $$;

create or replace function public.day32_uncomplete(p_day integer)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare u uuid:=auth.uid(); changed integer; total integer; next_day integer;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_day is null or p_day<1 or p_day>32 then raise exception 'invalid day'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,32));
 update public.day32_lessons set status='available',completed_at=null,next_review_at=null,review_stage=0 where user_id=u and day_no=p_day and status='completed';
 get diagnostics changed=row_count;
 update public.day32_reviews set active=false,paused=false,paused_at=null where user_id=u and day_no=p_day and completed_at is null;
 update public.study_word_reviews set active=false where user_id=u and module='root' and parent_key=p_day::text and completed_at is null;
 select count(*) into total from public.day32_lessons where user_id=u and status='completed';
 select min(n) into next_day from generate_series(1,32) n where not exists(select 1 from public.day32_lessons l where l.user_id=u and l.day_no=n and l.status='completed');
 update public.day32_progress set completed_days=total,current_day=coalesce(next_day,32),last_completed_at=(select max(completed_at) from public.day32_lessons where user_id=u) where user_id=u;
 return jsonb_build_object('saved',changed>0,'completed_days',total,'current_day',coalesce(next_day,32),'removed_from_review',true);
end $$;

