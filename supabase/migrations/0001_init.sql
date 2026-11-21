-- Sling Drift: accounts, verified runs, and the leaderboard.
--
-- The important rule here is that a client never writes a run directly. A row in
-- `runs` exists only because the submit-run Edge Function re-simulated the button
-- steps and agreed with the time, so a forged time cannot reach the table. The
-- browser holds the anon key, which these policies restrict to reading; only the
-- function holds the service-role key, and only it may insert.

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

-- One row per auth user. Supabase owns the credentials (email + password, hashed
-- with bcrypt server-side); this table owns the public name that appears on the
-- board. `auth.users` is never queried by the game.
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text not null check (username ~ '^[A-Za-z0-9_.-]{3,16}$'),
  created_at timestamptz not null default now()
);

-- Names are unique case-insensitively, so "Ash" and "ash" cannot both exist.
create unique index profiles_username_key on public.profiles (lower(username));

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------

create table public.runs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  track      int  not null check (track between 1 and 25),

  -- The run clock is the simulated time, and the simulation advances in fixed
  -- 1/120 s steps. Storing whole ticks rather than a float is what keeps ranking
  -- honest: two runs one step apart are one tick apart, and a tie is exactly
  -- equal rather than equal-to-15-decimal-places. Seconds are derived on read.
  ticks      int  not null check (ticks > 0),

  -- The button sequence, one character per step. This is the run: the function
  -- replays it to get the time, and the client replays it to draw a ghost.
  steps      text not null check (steps ~ '^[01]+$' and length(steps) <= 7200),

  created_at timestamptz not null default now()
);

-- One row per player per track: a board wants each player's best, and this keeps
-- the table bounded at (players x playable tracks) rows no matter how many
-- times they race.
create unique index runs_one_best_per_user_track on public.runs (user_id, track);

-- The board reads a track ordered by time, so index exactly that.
create index runs_track_ticks_idx on public.runs (track, ticks, created_at);

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

-- Ranked bests. `rank()` (not `row_number()`) so equal times share a rank, which
-- is the honest reading when the physics makes ties common; the tiebreak by
-- created_at means the earlier run sorts first within a tie.
create view public.leaderboard as
select r.track,
       r.user_id,
       p.username,
       r.ticks,
       r.ticks / 120.0 as seconds,
       r.created_at,
       rank() over (partition by r.track order by r.ticks asc, r.created_at asc) as rank
from   public.runs r
join   public.profiles p on p.id = r.user_id;

-- Run the views as the caller, so RLS on the underlying tables still applies.
alter view public.leaderboard set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.runs     enable row level security;

-- The board is public data: anyone, signed in or not, may read names and times.
create policy profiles_read on public.profiles for select using (true);
create policy runs_read     on public.runs     for select using (true);

-- A player may create and rename only their own profile.
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Deliberately absent: an insert or update policy on `runs`. With RLS on and no
-- such policy, a client POSTing a run straight to PostgREST is refused. The
-- service role bypasses RLS, so the Edge Function is the only writer, and it
-- writes only what it has re-simulated.

grant select on public.profiles, public.runs to anon, authenticated;
grant select on public.leaderboard to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Submitting a run
-- ---------------------------------------------------------------------------

-- Store a verified run and report the resulting rank, in one transaction.
--
-- Read-then-write from the Edge Function would race: two runs landing together
-- could both read the old best and both insert. Doing it in one function makes it
-- atomic, and the unique index is the backstop.
--
-- `p_user` is passed in rather than taken from auth.uid() because this is called
-- with the service role, which has already verified the caller's token. The
-- execute grant below is what makes that safe: only the service role may call it.
create or replace function public.submit_run(
  p_user  uuid,
  p_track int,
  p_ticks int,
  p_steps text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev     int;
  v_improved boolean := false;
  v_rank     int;
  v_total    int;
begin
  select ticks into v_prev
  from   runs
  where  user_id = p_user and track = p_track;

  if v_prev is null then
    insert into runs (user_id, track, ticks, steps)
    values (p_user, p_track, p_ticks, p_steps);
    v_improved := true;
  elsif p_ticks < v_prev then
    update runs
    set    ticks = p_ticks, steps = p_steps, created_at = now()
    where  user_id = p_user and track = p_track;
    v_improved := true;
  end if;

  -- Competition rank: everyone on the same time shares a place, which matches
  -- what `rank()` in the view reports, so the two never disagree.
  select count(*) + 1 into v_rank
  from   runs
  where  track = p_track
    and  ticks < (select ticks from runs where user_id = p_user and track = p_track);

  select count(*) into v_total from runs where track = p_track;

  return jsonb_build_object(
    'improved', v_improved,
    'ticks',    (select ticks from runs where user_id = p_user and track = p_track),
    'rank',     v_rank,
    'total',    v_total
  );
end;
$$;

-- Only the service role (i.e. the Edge Function) may submit. Without this the
-- function would be a way for a client to write any run it liked.
revoke execute on function public.submit_run(uuid, int, int, text) from public, anon, authenticated;
grant  execute on function public.submit_run(uuid, int, int, text) to service_role;
