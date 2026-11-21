-- Endless improvements are announced through the same Discord tracker.
--
-- `tracker_config` already carries the webhook and the two speedrun templates.
-- An endless score is a distance, so reusing a message that says "on track
-- {track} with {time}s" would be wrong. It gets its own two templates: a run that
-- takes rank 1 posts the record template, every other improvement posts the
-- position template. The `run` function picks between them.
--
-- Apply this before (or with) the `run` function deploy. Until the columns exist,
-- the function's tracker select fails and an endless improvement is stored
-- without an announcement - the run is never lost, but the channel stays quiet.

alter table public.tracker_config
  add column if not exists endless_record_message text not null
    default '{player} took the endless lead with {metres}m',
  add column if not exists endless_message text not null
    default '{player} reached {metres}m on the endless board (rank {rank} of {total})';

-- The templates are not secrets, exactly like `wr_message` and `pos_message`.
-- `webhook_url` stays service-role only.
grant select (endless_record_message, endless_message)
  on public.tracker_config to authenticated;

-- The old three-argument signature must go, or PostgREST sees two functions of
-- the same name and cannot choose between them.
drop function if exists public.set_tracker_config(text, text, text);

create or replace function public.set_tracker_config(
  p_webhook_url text,
  p_wr_message  text default null,
  p_pos_message text default null,
  p_endless_record_message text default null,
  p_endless_message text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'not an admin' using errcode = '42501';
  end if;

  update public.tracker_config
     set webhook_url = p_webhook_url,
         wr_message  = coalesce(p_wr_message, wr_message),
         pos_message = coalesce(p_pos_message, pos_message),
         endless_record_message = coalesce(p_endless_record_message, endless_record_message),
         endless_message = coalesce(p_endless_message, endless_message),
         updated_at  = now()
   where id = 1;
end;
$$;

revoke execute on function public.set_tracker_config(text, text, text, text, text) from public, anon;
grant  execute on function public.set_tracker_config(text, text, text, text, text) to authenticated;

-- PostgREST caches the table shape and the function signature. Without this it
-- keeps serving the old three-argument RPC and rejects a select of the new
-- columns until the next restart.
notify pgrst, 'reload schema';
