-- The tracker's webhook is a credential, and 0002 let *any* signed-in player
-- overwrite it. A player could point the record announcements at their own
-- Discord channel, or blank the templates, and every other player's runs would
-- post there. The old client-side 0404 code was never the gate; this is.
--
-- Now only a row in `admins` may change the tracker, and the admin list is
-- writable only by the service role. A normal player's UPDATE is refused before
-- any policy runs, because the write grant itself is gone.

create table if not exists public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

-- Deliberately no policies and no grants: a client can neither read nor write
-- the admin list. The service role (SQL, Edge Functions) bypasses RLS and is the
-- only way to add an admin.
revoke all on public.admins from anon, authenticated;

-- 0002's policy trusted every authenticated user. Drop it, and revoke both the
-- table-level and the column-level UPDATE grants it handed out - revoking only
-- the table grant would leave the column grants (webhook_url, wr_message,
-- pos_message) in place.
drop policy if exists tracker_write on public.tracker_config;
revoke update on public.tracker_config from authenticated;
revoke update (webhook_url, wr_message, pos_message) on public.tracker_config from authenticated;

-- An admin sets the tracker through this function. It checks the admin table
-- itself and is security-definer, so the caller never needs write access.
create or replace function public.set_tracker_config(
  p_webhook_url text,
  p_wr_message  text default null,
  p_pos_message text default null
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
         updated_at  = now()
   where id = 1;
end;
$$;

revoke execute on function public.set_tracker_config(text, text, text) from public, anon;
grant  execute on function public.set_tracker_config(text, text, text) to authenticated;
