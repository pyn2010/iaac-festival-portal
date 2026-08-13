-- Final two-account model: Admin and Group accounts.
-- This migration preserves existing data while adding claimable Group IDs and group-scoped authorization.

alter type public.app_role add value if not exists 'group';

create type public.group_id_status as enum ('available','claimed','disabled','replaced');
create type public.document_scope as enum ('official','group');
create table public.group_ids (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  status public.group_id_status not null default 'available',
  claimed_by uuid unique references auth.users(id) on delete set null,
  claimed_at timestamptz,
  replaced_by uuid references public.group_ids(id),
  replacement_for uuid references public.group_ids(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint available_group_id_unclaimed check (status <> 'available' or claimed_by is null)
);
create table public.group_id_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.group_ids(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists group_id uuid references public.group_ids(id);
alter table public.applications add column if not exists group_id uuid references public.group_ids(id);
alter table public.event_documents add column if not exists group_id uuid references public.group_ids(id);
alter table public.event_documents add column if not exists scope public.document_scope not null default 'official';
update public.profiles set role = 'group'::public.app_role where role::text = 'participant';

create unique index if not exists one_profile_per_group on public.profiles(group_id) where group_id is not null;
alter table public.applications add constraint applications_group_id_key unique (group_id);
create index if not exists applications_group_id_idx on public.applications(group_id);
create index if not exists event_documents_group_id_idx on public.event_documents(group_id);
insert into public.group_ids (code) values
  ('PUIFF26-5235ELP7'), ('PUIFF26-4R9VED0S'), ('PUIFF26-AE6ZU663'), ('PUIFF26-92N2WGTW'),
  ('PUIFF26-3XE0GNWA'), ('PUIFF26-B50WEY9E'), ('PUIFF26-W6LZAW8S'), ('PUIFF26-Y7N6FT8O'),
  ('PUIFF26-B0MQWICG'), ('PUIFF26-6QU4DOCB'), ('PUIFF26-2M2OFJYO'), ('PUIFF26-N1MQMKTB'),
  ('PUIFF26-OE7128HS'), ('PUIFF26-J344TYRQ'), ('PUIFF26-ZR86IW7Z'), ('PUIFF26-ZLJY1IJV'),
  ('PUIFF26-MNQHCVKQ'), ('PUIFF26-7TG51SKU'), ('PUIFF26-LLBIL9GE'), ('PUIFF26-8R78Y40C')
on conflict (code) do nothing;
create or replace function public.current_group_id() returns uuid language sql stable security definer set search_path = public as $$
  select group_id from public.profiles where id = auth.uid();
$$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, role)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'info@iaac.in' then 'admin'::public.app_role else 'group'::public.app_role end
  ) on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.claim_group_id(group_code text) returns uuid language plpgsql security definer set search_path = public as $$
declare claimed_id uuid;
begin
  if public.current_role() = 'admin' then
    raise exception 'Admin accounts cannot claim Group IDs';
  end if;
  update public.group_ids
  set status = 'claimed', claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
  where upper(code) = upper(trim(group_code))
    and status = 'available'
    and claimed_by is null
  returning id into claimed_id;

  if claimed_id is null then
    raise exception 'Group ID is invalid, disabled, replaced, or already claimed';
  end if;
  update public.profiles set role = 'group'::public.app_role, group_id = claimed_id, updated_at = now() where id = auth.uid();
  insert into public.group_id_events(group_id, actor_id, event_type, details) values (claimed_id, auth.uid(), 'claimed', jsonb_build_object('code', upper(trim(group_code))));
  return claimed_id;
end;
$$;
create or replace function public.admin_replace_group_id(old_group_id uuid, new_code text, reason text default null) returns uuid language plpgsql security definer set search_path = public as $$
declare new_group_id uuid;
begin
  if public.current_role() <> 'admin' then raise exception 'Admin role required'; end if;
  insert into public.group_ids(code, notes) values (upper(trim(new_code)), reason) returning id into new_group_id;
  update public.group_ids set status = 'replaced', replaced_by = new_group_id, notes = coalesce(reason, notes), updated_at = now() where id = old_group_id;
  update public.group_ids set replacement_for = old_group_id where id = new_group_id;
  insert into public.group_id_events(group_id, actor_id, event_type, details) values (old_group_id, auth.uid(), 'replaced', jsonb_build_object('replacement_group_id', new_group_id, 'reason', reason));
  return new_group_id;
end;
$$;
create or replace function public.admin_disable_group_id(target_group_id uuid, reason text default null) returns void language plpgsql security definer set search_path = public as $$
begin
  if public.current_role() <> 'admin' then raise exception 'Admin role required'; end if;
  update public.group_ids set status = 'disabled', notes = coalesce(reason, notes), updated_at = now() where id = target_group_id and status <> 'claimed';
  insert into public.group_id_events(group_id, actor_id, event_type, details) values (target_group_id, auth.uid(), 'disabled', jsonb_build_object('reason', reason));
end;
$$;
alter table public.group_ids enable row level security;
alter table public.group_id_events enable row level security;
drop policy if exists "profiles own or admin read" on public.profiles;
drop policy if exists "profiles own update" on public.profiles;
drop policy if exists "participants manage own applications" on public.applications;
drop policy if exists "admins update all applications" on public.applications;
drop policy if exists "documents visible to authenticated" on public.event_documents;
drop policy if exists "documents admin insert" on public.event_documents;
drop policy if exists "documents admin delete" on public.event_documents;
drop policy if exists "authenticated document downloads" on storage.objects;
drop policy if exists "admin document uploads" on storage.objects;
drop policy if exists "admin document deletes" on storage.objects;
create policy "profiles own group or admin read" on public.profiles for select using (id = auth.uid() or public.current_role() = 'admin' or group_id = public.current_group_id());
create policy "profiles own update no role escalation" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = public.current_role() and group_id = public.current_group_id());
create policy "profiles self insert group only" on public.profiles for insert with check (id = auth.uid() and role = 'group'::public.app_role);
create policy "applications group scoped or admin" on public.applications for all using (public.current_role() = 'admin' or group_id = public.current_group_id() or user_id = auth.uid()) with check (public.current_role() = 'admin' or (group_id = public.current_group_id() and user_id = auth.uid()));
create policy "documents scoped to official group or admin" on public.event_documents for select to authenticated using (public.current_role() = 'admin' or scope = 'official' or group_id = public.current_group_id());
create policy "documents admin insert" on public.event_documents for insert with check (public.current_role() = 'admin');
create policy "documents admin delete" on public.event_documents for delete using (public.current_role() = 'admin');
create policy "documents admin update" on public.event_documents for update using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
create policy "group ids admin read all group read own" on public.group_ids for select using (public.current_role() = 'admin' or claimed_by = auth.uid() or id = public.current_group_id());
create policy "group ids admin insert" on public.group_ids for insert with check (public.current_role() = 'admin');
create policy "group ids admin update" on public.group_ids for update using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
create policy "group id events admin or own group read" on public.group_id_events for select using (public.current_role() = 'admin' or group_id = public.current_group_id());
create policy "group id events admin insert" on public.group_id_events for insert with check (public.current_role() = 'admin');
create policy "scoped document downloads" on storage.objects for select to authenticated using (bucket_id = 'event-documents' and (public.current_role() = 'admin' or exists (select 1 from public.event_documents d where d.file_path = storage.objects.name and (d.scope = 'official' or d.group_id = public.current_group_id()))));
create policy "admin document uploads" on storage.objects for insert to authenticated with check (bucket_id = 'event-documents' and public.current_role() = 'admin');
create policy "admin document deletes" on storage.objects for delete to authenticated using (bucket_id = 'event-documents' and public.current_role() = 'admin');
