-- Private photo notes. Existing learning records are not changed.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('study-note-photos','study-note-photos',false,3145728,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
do $policy$
begin
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='study_photos_read_own_v8') then
  create policy study_photos_read_own_v8 on storage.objects for select to authenticated
  using(bucket_id='study-note-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='study_photos_insert_own_v8') then
  create policy study_photos_insert_own_v8 on storage.objects for insert to authenticated
  with check(bucket_id='study-note-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='study_photos_move_own_v8') then
  create policy study_photos_move_own_v8 on storage.objects for update to authenticated
  using(bucket_id='study-note-photos' and (storage.foldername(name))[1]=(select auth.uid())::text)
  with check(bucket_id='study-note-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
 end if;
end $policy$;
-- No delete policy: the app moves removed images to a recoverable folder.
commit;
select id,public,file_size_limit,allowed_mime_types from storage.buckets where id='study-note-photos';
