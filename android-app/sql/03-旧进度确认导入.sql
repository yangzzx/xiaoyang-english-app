-- 允许确认后一次导入不连续的旧课次；保持原有 RLS，不删除任何记录。
create or replace function public.day32_import_days(p_days integer[])
returns jsonb language plpgsql security invoker set search_path = public as $$
declare n integer; result jsonb;
begin
  if auth.uid() is null then raise exception 'Please sign in'; end if;
  if p_days is null or cardinality(p_days)<1 or cardinality(p_days)>32
    or array_position(p_days,null) is not null
    or exists(select 1 from unnest(p_days) d where d<1 or d>32) then
    raise exception 'Invalid days';
  end if;
  for n in select distinct d from unnest(p_days) d order by d loop
    result := public.day32_complete(n);
  end loop;
  return result;
end $$;
revoke execute on function public.day32_import_days(integer[]) from public,anon;
grant execute on function public.day32_import_days(integer[]) to authenticated;
