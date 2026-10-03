-- =====================================================================
--  Power Moon Logic Charts — video submissions backend (Supabase)
-- =====================================================================
--  SETUP (about 5 minutes, all free tier):
--
--  1. Create a project at https://supabase.com (New project).
--  2. SQL Editor -> New query -> paste this whole file.
--     !! First change 'you@example.com' below (it appears ONCE) to YOUR email. !!
--     Then press Run.
--  3. Authentication -> Users -> "Add user" -> "Create new user".
--     Use that same email + a strong password, tick "Auto Confirm User".
--  4. Authentication -> Sign In / Providers -> Email: turn OFF "Allow new users
--     to sign up" (so nobody else can make accounts).
--  5. Project Settings -> API: copy the Project URL and the "anon public" key
--     into VIDEO_SUBMIT.supabaseUrl / supabaseAnonKey in index.html.
--     (Never put the service_role key in the website.)
--
--  HOW IT WORKS
--   * Anyone can UPLOAD a clip + add a "pending" row (that's the Submit button).
--   * Nobody except you can list, download, approve or delete anything.
--     That is enforced here by row-level security, not by the web page.
-- =====================================================================


-- ---------- 1. Who is the owner? (EDIT THE EMAIL) ----------------------
create or replace function public.is_owner()
returns boolean
language sql
stable
as $$
  select coalesce((auth.jwt() ->> 'email') = 'you@example.com', false);
$$;
grant execute on function public.is_owner() to anon, authenticated;


-- ---------- 2. Submissions table ---------------------------------------
create table if not exists public.submissions (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  filename    text   not null check (filename ~ '^[a-z0-9]{1,200}\.(mp4|webp)$'),
  file_path   text   not null check (char_length(file_path) <= 300),
  kingdom     text   not null check (char_length(kingdom) <= 60),
  moon        text   not null check (char_length(moon) <= 200),
  tier        text   not null check (char_length(tier) <= 20),
  branch      int    not null check (branch between 1 and 100),
  submitter   text   check (submitter is null or char_length(submitter) <= 40),
  size_bytes  bigint check (size_bytes is null or size_bytes <= 52428800),
  status      text   not null default 'pending' check (status in ('pending','approved','rejected'))
);

create index if not exists submissions_status_created_idx
  on public.submissions (status, created_at);

alter table public.submissions enable row level security;

grant insert on public.submissions to anon, authenticated;
grant select, update, delete on public.submissions to authenticated;

drop policy if exists "anyone can submit"  on public.submissions;
drop policy if exists "owner can read"     on public.submissions;
drop policy if exists "owner can update"   on public.submissions;
drop policy if exists "owner can delete"   on public.submissions;

create policy "anyone can submit" on public.submissions
  for insert to anon, authenticated
  with check (status = 'pending');

create policy "owner can read" on public.submissions
  for select to authenticated using (public.is_owner());

create policy "owner can update" on public.submissions
  for update to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "owner can delete" on public.submissions
  for delete to authenticated using (public.is_owner());


-- ---------- 3. Private storage bucket for the clips --------------------
-- 52428800 bytes = 50 MB (the Free plan's per-file ceiling), mp4/webp only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('submissions', 'submissions', false, 52428800, array['video/mp4', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "anyone can upload submissions" on storage.objects;
drop policy if exists "owner can read submissions"    on storage.objects;
drop policy if exists "owner can delete submissions"  on storage.objects;

create policy "anyone can upload submissions" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'submissions');

create policy "owner can read submissions" on storage.objects
  for select to authenticated
  using (bucket_id = 'submissions' and public.is_owner());

create policy "owner can delete submissions" on storage.objects
  for delete to authenticated
  using (bucket_id = 'submissions' and public.is_owner());
