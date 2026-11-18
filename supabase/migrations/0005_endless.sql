-- Endless mode gets its own board: player + distance.
--
-- Endless cannot share the speedrun table. A speedrun row is a *verified* run: it
-- carries the button steps and the tick count the function replayed to get them,
-- and the board ranks lowest-first. An endless row is a distance, ranked
-- highest-first, with no steps and no replay - the run is not re-simulated (the
-- server has no endless ramp in its physics, and does not need one: a distance
-- board is not a record that a forged value can steal, it is a score the player
-- reports). Folding it into `runs` would mean a nullable ticks/steps for endless
-- and a nullable metres for speedrun, plus a ranking that flips direction by row.
-- A separate table keeps both simple.
--
-- This is the one place the "a client never sends a score" rule is relaxed, and
-- deliberately so: it applies to the *verified* speedrun board. The endless board
-- is a distance leaderboard, and the client is trusted for it. Nothing here can
-- write to `runs`, so the speedrun board's guarantee is unchanged.

create table public.endless_runs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  -- The road everyone races. Endless is pinned to one seed in the client so two
  -- players are on the same road; the column keeps that explicit and leaves room
  -- for a second road later.
  seed       int  not null check (seed > 0),
  -- Distance in whole metres. The score is a distance, not a time, so it ranks
  -- highest-first; storing it as an integer keeps ties exact.
  metres     int  not null check (metres >= 0),
  created_at timestamptz not null default now()
);

-- One row per player per road: the board wants each player's best, and this keeps
-- the table bounded at (players x seeds) rows however many times they play.
create unique index endless_runs_one_best_per_user_seed
  on public.endless_runs (user_id, seed);

-- The board reads a seed ordered by distance, so index exactly that.
create index endless_runs_seed_metres_idx
  on public.endless_runs (seed, metres desc, created_at);

-- ---------------------------------------------------------------------------
-- The endless board
-- ---------------------------------------------------------------------------

-- Ranked bests, furthest first. `rank()` so equal distances share a place; the
-- tiebreak by created_at means the earlier run sorts first within a tie.
create view public.endless_leaderboard as
select e.seed,
       e.user_id,
       p.username,
       e.metres,
       e.created_at,
       rank() over (partition by e.seed order by e.metres desc, e.created_at asc) as rank
from   public.endless_runs e
join   public.profiles p on p.id = e.user_id;

alter view public.endless_leaderboard set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------

alter table public.endless_runs enable row level security;

-- The board is public data: anyone, signed in or not, may read names and distances.
create policy endless_runs_read on public.endless_runs for select using (true);

-- Deliberately absent, exactly as for `runs`: no insert or update policy, so a
-- client POSTing a distance straight to PostgREST is refused. Only the function,
-- which holds the service role, may write.
grant select on public.endless_runs, public.endless_leaderboard to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Submitting an endless run
-- ---------------------------------------------------------------------------

-- Store a distance and report the resulting rank, in one transaction. Endless
-- ranks highest-first, so a new run replaces the old one only when it is further,
-- and the rank counts the runs that went further rather than faster.
create or replace function public.submit_endless_run(
  p_user   uuid,
  p_seed   int,
  p_metres int
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
  select metres into v_prev
  from   endless_runs
  where  user_id = p_user and seed = p_seed;

  if v_prev is null then
    insert into endless_runs (user_id, seed, metres)
    values (p_user, p_seed, p_metres);
    v_improved := true;
  elsif p_metres > v_prev then
    update endless_runs
    set    metres = p_metres, created_at = now()
    where  user_id = p_user and seed = p_seed;
    v_improved := true;
  end if;

  -- Competition rank: everyone on the same distance shares a place, which matches
  -- what `rank()` in the view reports, so the two never disagree.
  select count(*) + 1 into v_rank
  from   endless_runs
  where  seed = p_seed
    and  metres > (select metres from endless_runs where user_id = p_user and seed = p_seed);

  select count(*) into v_total from endless_runs where seed = p_seed;

  return jsonb_build_object(
    'improved', v_improved,
    'metres',   (select metres from endless_runs where user_id = p_user and seed = p_seed),
    'rank',     v_rank,
    'total',    v_total
  );
end;
$$;

-- Only the service role (i.e. the Edge Function) may submit.
revoke execute on function public.submit_endless_run(uuid, int, int) from public, anon, authenticated;
grant  execute on function public.submit_endless_run(uuid, int, int) to service_role;
