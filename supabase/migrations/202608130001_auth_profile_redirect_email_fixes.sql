-- Repair Auth-to-profile provisioning for Admin/Group accounts and support email-confirmed Group signup.
-- Apply this in Supabase after 202608120001 and 202608120002.

create or replace function public.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_group_code text := nullif(upper(trim(new.raw_user_meta_data->>'group_id')), '');
  claimed_group_id uuid;
begin
  if lower(new.email) <> 'info@iaac.in' and requested_group_code is not null then
    update public.group_ids
    set status = 'claimed', claimed_by = new.id, claimed_at = now(), updated_at = now()
    where upper(code) = requested_group_code
      and status = 'available'
      and claimed_by is null
    returning id into claimed_group_id;

    if claimed_group_id is null then
      raise exception 'Group ID is invalid, disabled, replaced, or already claimed';
    end if;

    insert into public.group_id_events(group_id, actor_id, event_type, details)
    values (claimed_group_id, new.id, 'claimed_at_signup', jsonb_build_object('code', requested_group_code));
  end if;

  insert into public.profiles (id, email, role, group_id)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'info@iaac.in' then 'admin'::public.app_role else 'group'::public.app_role end,
    claimed_group_id
  )
  on conflict (id) do update set
    email = excluded.email,
    role = case when lower(excluded.email) = 'info@iaac.in' then 'admin'::public.app_role else public.profiles.role end,
    group_id = coalesce(public.profiles.group_id, excluded.group_id),
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.profiles (id, email, role)
select
  u.id,
  u.email,
  case when lower(u.email) = 'info@iaac.in' then 'admin'::public.app_role else 'group'::public.app_role end
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

update public.profiles
set role = 'admin'::public.app_role, updated_at = now()
where lower(email) = 'info@iaac.in' and role <> 'admin'::public.app_role;

create or replace function public.claim_group_id(group_code text) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare claimed_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in is required to claim a Group ID';
  end if;

  insert into public.profiles (id, email, role)
  select id, email, case when lower(email) = 'info@iaac.in' then 'admin'::public.app_role else 'group'::public.app_role end
  from auth.users
  where id = auth.uid()
  on conflict (id) do nothing;

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

  update public.profiles
  set role = 'group'::public.app_role, group_id = claimed_id, updated_at = now()
  where id = auth.uid();

  insert into public.group_id_events(group_id, actor_id, event_type, details)
  values (claimed_id, auth.uid(), 'claimed', jsonb_build_object('code', upper(trim(group_code))));

  return claimed_id;
end;
$$;
