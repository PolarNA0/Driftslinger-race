-- The track column stops hard-coding the set, so a new track needs no migration.
--
-- 0003 pinned the column to the set that existed then, {1-5, 21-25}. That set has
-- since grown (26-28, the reattach showcase tracks), and every upload on a new
-- track is refused by the constraint before the function can replay it - so a new
-- track ships "cannot be uploaded" until someone remembers to write a migration.
--
-- The exact set is the game's, not the database's: it lives in physics/tracks.js
-- (derived from the track tables) and the `run` function refuses any number the
-- game does not play, before it writes anything. The constraint here is only a
-- sanity floor against a bug or a stray direct write, so it is relaxed to a
-- positive-number check. Adding a track is now one entry in the game's track
-- table and nothing else.
--
-- Access is unchanged and still enforced by the database: RLS leaves `runs` with
-- no insert/update policy, and `submit_run` stays security-definer and revoked
-- from anon/authenticated, so the function is the only writer.

alter table public.runs
  drop constraint if exists runs_track_check;

alter table public.runs
  add constraint runs_track_check
  check (track > 0);
