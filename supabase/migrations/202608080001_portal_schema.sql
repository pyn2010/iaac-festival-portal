create type public.app_role as enum ('admin','participant');
create type public.application_status as enum ('Draft','Submitted','Under Review','Approved','Rejected');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role public.app_role not null default 'participant',
  full_name text,
  country text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  team_name text not null default '',
  country text not null default '',
  category text not null default 'Folk Dance',
  members text not null default '',
  media_links text not null default '',
  notes text not null default '',
  status public.application_status not null default 'Draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.event_documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  file_url text not null,
  file_path text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.current_role() returns public.app_role language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'participant'::public.app_role);
$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, role)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'info@iaac.in' or new.raw_user_meta_data->>'role' = 'admin' then 'admin'::public.app_role else 'participant'::public.app_role end
  ) on conflict (id) do update set email = excluded.email, role = excluded.role;
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.applications enable row level security;
alter table public.event_documents enable row level security;

create policy "profiles own or admin read" on public.profiles for select using (id = auth.uid() or public.current_role() = 'admin');
create policy "profiles own update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = public.current_role());
create policy "profiles self insert" on public.profiles for insert with check (id = auth.uid());

create policy "participants manage own applications" on public.applications for all using (user_id = auth.uid() or public.current_role() = 'admin') with check (user_id = auth.uid() or public.current_role() = 'admin');
create policy "admins update all applications" on public.applications for update using (public.current_role() = 'admin') with check (public.current_role() = 'admin');

create policy "documents visible to authenticated" on public.event_documents for select to authenticated using (true);
create policy "documents admin insert" on public.event_documents for insert with check (public.current_role() = 'admin');
create policy "documents admin delete" on public.event_documents for delete using (public.current_role() = 'admin');

insert into storage.buckets (id, name, public) values ('event-documents','event-documents', true) on conflict (id) do nothing;
create policy "authenticated document downloads" on storage.objects for select to authenticated using (bucket_id = 'event-documents');
create policy "admin document uploads" on storage.objects for insert to authenticated with check (bucket_id = 'event-documents' and public.current_role() = 'admin');
create policy "admin document deletes" on storage.objects for delete to authenticated using (bucket_id = 'event-documents' and public.current_role() = 'admin');
