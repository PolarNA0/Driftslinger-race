-- The Discord record tracker, server-side.
--
-- The tracker used to live in the player's browser, which is why only the admin
-- ever posted: only the admin's device held the webhook. Moving the webhook here
-- means one admin sets it once and every player's improvement is announced
-- through it.
--
-- The webhook is a credential - anyone holding it can post to the channel - so it
-- is readable only by the service role, which is the Edge Function. A signed-in
-- player may *write* it (that is how the admin sets it) but cannot read it back,
-- so a curious player cannot pull the URL out of the database and spam the
-- channel. The two message templates are not secret, so they read normally.

create table if not exists public.tracker_config (
  id          int  primary key default 1 check (id = 1),
  webhook_url text,
  wr_message  text not null default '{player} set a new world record on track {track} with {time}s [WR -{delta}]',
  pos_message text not null default '{player} took position {rank} on track {track} with {time}s [WR +{delta}]',
  updated_at  timestamptz not null default now()
);

insert into public.tracker_config (id) values (1) on conflict (id) do nothing;

alter table public.tracker_config enable row level security;

-- The admin gate is the client-side code (see js/settings.js) - a cupboard lock,
-- not a safe, exactly like the rest of the admin surface. What the database
-- enforces is the part that matters: the webhook can be written but not read.
create policy tracker_read on public.tracker_config
  for select to authenticated using (true);
create policy tracker_write on public.tracker_config
  for update to authenticated using (true) with check (true);

-- Column-level grants, so `webhook_url` is neither readable nor writable except
-- by the service role. A select of it is refused outright rather than returned
-- blank, which makes the intent unmistakable. `id` is readable because the admin
-- client targets the single row with `?id=eq.1`, and PostgREST needs to read the
-- column it filters on.
grant select (id, wr_message, pos_message) on public.tracker_config to authenticated;
grant update (webhook_url, wr_message, pos_message) on public.tracker_config to authenticated;
grant select, insert, update on public.tracker_config to service_role;

-- ---------------------------------------------------------------------------
-- submit_run, now reporting the record around the run
-- ---------------------------------------------------------------------------

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
  v_prev      int;
  v_improved  boolean := false;
  v_rank      int;
  v_total     int;
  v_wr_before int;
  v_wr_after  int;
begin
  -- The record as it stood before this run landed, so a beat can be told from a
  -- mere improvement even when the player already held the record.
  select min(ticks) into v_wr_before from runs where track = p_track;

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

  select min(ticks) into v_wr_after from runs where track = p_track;

  return jsonb_build_object(
    'improved',  v_improved,
    'ticks',     (select ticks from runs where user_id = p_user and track = p_track),
    'rank',      v_rank,
    'total',     v_total,
    'wr_before', v_wr_before,
    'wr_after',  v_wr_after
  );
end;
$$;

revoke execute on function public.submit_run(uuid, int, int, text) from public, anon, authenticated;
grant  execute on function public.submit_run(uuid, int, int, text) to service_role;
