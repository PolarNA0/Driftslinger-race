-- The endless leaderboard.
--
-- Endless is one road, scored by distance: the furthest run wins. There are no
-- per-track boards here, because there is only one endless road - the seed only
-- mirrors the staircase, so every run is comparable. That makes this a single
-- global board rather than the per-track boards `leaderboard` serves.
--
-- The same anti-cheat rule applies as for speedrun: a client never sends a
-- distance. It sends the button steps, and the `run` Edge Function replays them
-- through the game's own physics to find out how far the run got. A forged
-- distance has nothing to attach to.
--
-- Distance is stored as whole ticks, exactly like a speedrun time. The run is
-- `ticks / 120` seconds long, so the metres derive from the step count and two
-- runs one step apart are one step apart - a tie is exact, not equal to 15
-- decimal places. Seconds and metres are computed on read.

create table public.endless_runs (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  ticks      int  not null check (ticks > 0),
  steps      text not null check (steps ~ '^[01]+$' and length(steps) <= 36000),
  created_at timestamptz not null default now()
);

-- The board reads ordered by distance, so index exactly that. Higher is better.
create index endless_runs_ticks_idx on public.endless_runs (ticks desc, created_at asc);

-- Ranked bests, furthest first. `rank()` (not `row_number()`) so equal distances
-- share a rank, which is the honest reading; the tiebreak by created_at means the
-- earlier run sorts first within a tie.
create view public.endless_board as
select r.user_id,
       p.username,
       r.ticks,
       -- Metres: the run is ticks/120 seconds at the game's constant speed, over
       -- the pixels-per-metre the HUD uses. Kept in step with CFG.pxPerMetre.
       (r.ticks / 120.0) * 290 / 50 as metres,
       r.created_at,
       rank() over (order by r.ticks desc, r.created_at asc) as rank
from   public.endless_runs r
join   public.profiles p on p.id = r.user_id;

alter view public.endless_board set (security_invoker = true);

alter table public.endless_runs enable row level security;

-- Public data: anyone may read the distances and names.
create policy endless_read on public.endless_runs for select using (true);

-- Deliberately absent: an insert or update policy. With RLS on and no such
-- policy, a client POSTing straight to PostgREST is refused; the service role
-- bypasses RLS, so the Edge Function is the only writer.
grant select on public.endless_runs to anon, authenticated;
grant select on public.endless_board to anon, authenticated;

-- Store a verified endless run and report the resulting rank, in one
-- transaction. Kept separate from `submit_run` because the ranking is the other
-- way round (more is better) and there is no track.
create or replace function public.submit_endless(
  p_user  uuid,
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
  from   endless_runs
  where  user_id = p_user;

  if v_prev is null then
    insert into endless_runs (user_id, ticks, steps)
    values (p_user, p_ticks, p_steps);
    v_improved := true;
  elsif p_ticks > v_prev then
    update endless_runs
    set    ticks = p_ticks, steps = p_steps, created_at = now()
    where  user_id = p_user;
    v_improved := true;
  end if;

  -- Competition rank: everyone on the same distance shares a place, matching the
  -- view's `rank()`.
  select count(*) + 1 into v_rank
  from   endless_runs
  where  ticks > (select ticks from endless_runs where user_id = p_user);

  select count(*) into v_total from endless_runs;

  return jsonb_build_object(
    'improved', v_improved,
    'ticks',    (select ticks from endless_runs where user_id = p_user),
    'rank',     v_rank,
    'total',    v_total
  );
end;
$$;

revoke execute on function public.submit_endless(uuid, int, text) from public, anon, authenticated;
grant  execute on function public.submit_endless(uuid, int, text) to service_role;
