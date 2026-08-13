-- Allow authenticated Group accounts to upload documents for their own claimed Group ID.
-- Existing schema already has event_documents.group_id and event_documents.scope, so only RLS policy additions are needed.

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'event_documents' and policyname = 'documents group insert own') then
    create policy "documents group insert own" on public.event_documents
      for insert to authenticated
      with check (
        public.current_role() = 'group'
        and scope = 'group'
        and group_id = public.current_group_id()
        and created_by = auth.uid()
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'group document uploads') then
    create policy "group document uploads" on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'event-documents'
        and public.current_role() = 'group'
        and name like public.current_group_id()::text || '/%'
      );
  end if;
end;
$$;
