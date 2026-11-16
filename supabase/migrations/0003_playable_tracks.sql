-- Tracks 6-20 are gone.
--
-- The playable set is no longer 1..25: it is {1-5, 21-25}, and the numbers are
-- kept as they were so an existing run on track 1 is still a run on track 1. That
-- makes the track column a set membership rather than a range, and `between 1 and
-- 25` would happily accept a run on a road the game no longer shows.
--
-- Runs on the removed tracks cannot be reached by any client any more (the menu
-- does not offer them and the verifier refuses them), so they are deleted rather
-- than kept: leaving them would only fail the new constraint.

delete from public.runs where track not in (1, 2, 3, 4, 5, 21, 22, 23, 24, 25);

alter table public.runs
  drop constraint if exists runs_track_check;

alter table public.runs
  add constraint runs_track_check
  check (track in (1, 2, 3, 4, 5, 21, 22, 23, 24, 25));
