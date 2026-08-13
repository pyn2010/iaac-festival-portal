-- Separate /group and /admin portal support plus a reserved organiser test Group ID.

alter table public.group_ids add column if not exists is_test_reserved boolean not null default false;
insert into public.group_ids (code, status, is_test_reserved, notes)
values ('PUIFF26-TEST01', 'available', true, 'Reserved organiser test Group ID; same Group workflow and permissions, not a production Group ID.')
on conflict (code) do update set
  is_test_reserved = true,
  notes = coalesce(public.group_ids.notes, excluded.notes),
  updated_at = now();
