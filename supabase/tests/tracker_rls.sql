-- Proof that the tracker is admin-only, run against a throwaway database.
--
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/tracker_rls.sql
--
-- CI runs this on a postgres service container (see the `sql` job in
-- .github/workflows/verify.yml). It applies the real migrations, then acts as a
-- normal signed-in player and as an admin.

\set ON_ERROR_STOP on

-- The Supabase pieces the migrations assume exist.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

\ir ../migrations/0001_init.sql
\ir ../migrations/0002_tracker.sql
\ir ../migrations/0003_playable_tracks.sql
\ir ../migrations/0004_reattach_tracks.sql
\ir ../migrations/0005_endless.sql
\ir ../migrations/0006_admin.sql

-- Two players: one ordinary, one admin. Profiles and the admin row are written
-- by the service role, which is the only writer in the real system too.
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');
insert into public.profiles (id, username) values
  ('11111111-1111-1111-1111-111111111111', 'player'),
  ('22222222-2222-2222-2222-222222222222', 'admin');
insert into public.admins (user_id) values ('22222222-2222-2222-2222-222222222222');

-- ---------------------------------------------------------------------------
-- A normal player
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

do $$
begin
  begin
    update public.tracker_config set webhook_url = 'https://evil.example/hook' where id = 1;
    raise exception 'FAIL: a normal player could update tracker_config';
  exception when insufficient_privilege then
    raise notice 'ok: a normal player cannot update tracker_config (42501)';
  end;
end $$;

do $$
begin
  begin
    perform public.set_tracker_config('https://evil.example/hook');
    raise exception 'FAIL: a normal player could call set_tracker_config';
  exception when insufficient_privilege then
    raise notice 'ok: a normal player cannot call set_tracker_config (42501)';
  end;
end $$;

do $$
declare n int;
begin
  select count(*) into n from public.tracker_config;
  if n <> 1 then
    raise exception 'FAIL: a player cannot read the tracker templates';
  end if;
  raise notice 'ok: a player can still read the tracker templates';
end $$;

do $$
begin
  begin
    perform webhook_url from public.tracker_config;
    raise exception 'FAIL: a normal player could read the webhook';
  exception when insufficient_privilege then
    raise notice 'ok: the webhook stays unreadable (42501)';
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- An admin
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select public.set_tracker_config('https://discord.example/hook', 'wr {player}', 'pos {player}');

reset role;

do $$
declare hook text; wr text; pos text;
begin
  select webhook_url, wr_message, pos_message into hook, wr, pos
  from public.tracker_config where id = 1;
  if hook <> 'https://discord.example/hook' or wr <> 'wr {player}' or pos <> 'pos {player}' then
    raise exception 'FAIL: the admin write did not land (% / % / %)', hook, wr, pos;
  end if;
  raise notice 'ok: an admin can set the tracker through set_tracker_config';
end $$;

-- The service role keeps its direct write path (SQL and the Edge Function).
update public.tracker_config set webhook_url = 'https://discord.example/other' where id = 1;

do $$
begin
  if (select webhook_url from public.tracker_config where id = 1) <> 'https://discord.example/other' then
    raise exception 'FAIL: the service role could not write the tracker';
  end if;
  raise notice 'ok: the service role can still write the tracker directly';
end $$;

select 'TRACKER RLS PASS' as result;
