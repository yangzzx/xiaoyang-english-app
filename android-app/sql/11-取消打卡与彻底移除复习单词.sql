-- User-requested review lifecycle controls. Preserve completed review history when
-- unchecking a lesson; permanently removed generated words are blocked from sync
-- using a one-way digest (the English word itself is not retained in exclusions).
create table if not exists public.study_word_review_exclusions(
 user_id uuid not null references auth.users(id) on delete cascade,
 module text not null check(module in ('root','core','mother','phon','phonics')),
 word_hash text not null check(length(word_hash)=32),
 created_at timestamptz not null default now(),
 primary key(user_id,module,word_hash)
);
alter table public.study_word_review_exclusions enable row level security;
drop policy if exists study_word_review_exclusions_own on public.study_word_review_exclusions;
create policy study_word_review_exclusions_own on public.study_word_review_exclusions
 for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
grant select on public.study_word_review_exclusions to authenticated;

create or replace function public.skip_excluded_study_word_review()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if exists(select 1 from public.study_word_review_exclusions e where e.user_id=new.user_id and e.module=new.module and e.word_hash=md5(new.word_key)) then return null; end if;
 return new;
end $$;
drop trigger if exists study_word_review_exclusion_guard on public.study_word_reviews;
create trigger study_word_review_exclusion_guard before insert on public.study_word_reviews
 for each row execute function public.skip_excluded_study_word_review();

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

create or replace function public.study_word_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); r public.study_word_reviews;
begin
 if u is null then raise exception 'authentication required'; end if;
 select * into r from public.study_word_reviews where id=p_id and user_id=u for update;
 if not found then return jsonb_build_object('deleted',false); end if;
 insert into public.study_word_review_exclusions(user_id,module,word_hash) values(u,r.module,md5(r.word_key)) on conflict do nothing;
 delete from public.study_word_reviews where user_id=u and module=r.module and word_key=r.word_key;
 if r.module='spell' then
  delete from public.study_answers where user_id=u and module='spell' and item_key=r.word_key;
  delete from public.study_reviews where user_id=u and module='spell' and item_key=r.word_key;
  delete from public.study_records where user_id=u and module='spell' and item_key=r.word_key;
 end if;
 return jsonb_build_object('deleted',true,'module',r.module);
end $$;

-- Spell reviews live in the original study_reviews tables, not in the
-- generated per-module study_word_reviews table.
create or replace function public.study_spell_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); r public.study_reviews;
begin
 if u is null then raise exception 'authentication required'; end if;
 select * into r from public.study_reviews where id=p_id and user_id=u and module='spell' for update;
 if not found then return jsonb_build_object('deleted',false); end if;
 delete from public.study_answers where user_id=u and module='spell' and item_key=r.item_key;
 delete from public.study_reviews where user_id=u and module='spell' and item_key=r.item_key;
 delete from public.study_records where user_id=u and module='spell' and item_key=r.item_key;
 return jsonb_build_object('deleted',true,'module','spell','item_key',r.item_key);
end $$;

create or replace function public.day32_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); r public.day32_reviews;
begin
 if u is null then raise exception 'authentication required'; end if;
 select * into r from public.day32_reviews where id=p_id and user_id=u for update;
 if not found then return jsonb_build_object('deleted',false); end if;
 delete from public.day32_reviews where id=r.id and user_id=u;
 return jsonb_build_object('deleted',true,'day_no',r.day_no,'lesson_kept',true);
end $$;

create or replace function public.study_review_delete_many(p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 u uuid:=auth.uid(); item jsonb; src text; rid bigint; r public.study_word_reviews; s public.study_reviews; d public.day32_reviews;
 canonical text; deleted_count integer:=0;
begin
 if u is null then raise exception 'authentication required'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>10000 then raise exception 'invalid delete batch'; end if;
 for item in select value from jsonb_array_elements(p_items) loop
  src:=item->>'source';
  if coalesce(item->>'id','') !~ '^[0-9]{1,19}$' then continue; end if;
  rid:=(item->>'id')::bigint;
  if src='word' then
   select * into r from public.study_word_reviews where id=rid and user_id=u for update;
   if found then
    insert into public.study_word_review_exclusions(user_id,module,word_hash) values(u,r.module,md5(r.word_key)) on conflict do nothing;
    delete from public.study_word_reviews where user_id=u and module=r.module and word_key=r.word_key;
    deleted_count:=deleted_count+1;
   end if;
  elsif src='root' then
   select * into d from public.day32_reviews where id=rid and user_id=u for update;
   if found then delete from public.day32_reviews where id=d.id and user_id=u; deleted_count:=deleted_count+1; end if;
  elsif src='spell' then
   select * into s from public.study_reviews where id=rid and user_id=u and module='spell' for update;
   if found then
    canonical:=regexp_replace(lower(regexp_replace(s.item_key,'^word:','')),'[^a-z0-9]','','g');
    delete from public.study_answers a where a.user_id=u and a.module='spell' and a.item_key in (
     select sr.item_key from public.study_records sr where sr.user_id=u and sr.module='spell'
      and regexp_replace(lower(coalesce(nullif(trim(sr.data->>'canonical_word'),''),nullif(trim(sr.data->>'title'),''),sr.item_key)),'[^a-z0-9]','','g')=canonical
    );
    delete from public.study_reviews where user_id=u and module='spell' and item_key=s.item_key;
    delete from public.study_records where user_id=u and module='spell' and (
     item_key=s.item_key or regexp_replace(lower(coalesce(nullif(trim(data->>'canonical_word'),''),nullif(trim(data->>'title'),''),item_key)),'[^a-z0-9]','','g')=canonical
    );
    deleted_count:=deleted_count+1;
   end if;
  end if;
 end loop;
 return jsonb_build_object('deleted',deleted_count);
end $$;

revoke all on function public.study_uncomplete(text,text),public.day32_uncomplete(integer),public.day32_review_delete(bigint),public.study_word_review_delete(bigint),public.study_spell_review_delete(bigint),public.study_review_delete_many(jsonb),public.skip_excluded_study_word_review() from public,anon;
grant execute on function public.study_uncomplete(text,text),public.day32_uncomplete(integer),public.day32_review_delete(bigint),public.study_word_review_delete(bigint),public.study_spell_review_delete(bigint),public.study_review_delete_many(jsonb) to authenticated;
create or replace function public.study_review_version()
returns jsonb language plpgsql security invoker set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return jsonb_build_object('version',3,'intervals',jsonb_build_array(1,3,7,15,30,60,90),'active_task_limit',1,'removed_task_retention_days',3,'supports_uncomplete',true,'supports_word_delete',true);
end $$;
revoke all on function public.study_review_version() from public,anon;
grant execute on function public.study_review_version() to authenticated;
