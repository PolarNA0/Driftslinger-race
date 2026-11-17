// The real runs on a track. The board is exactly these runs and nothing else.
//
// Public: no token needed, because the board is public data. Reading it with the
// anon key is enough, and RLS on `runs` and `profiles` already allows that read.
//
// This returns the real runs rather than a rendered board, so the client ranks and
// pages them itself. The whole track is returned in one response because a track
// holds one run per player, so there is no unbounded field behind it to paginate
// around.
//
// `steps` travels with each row so a run can be watched: a real run has no ghost
// id to regenerate from, so its own button sequence is what replays it.
//
// `steps` lives on `runs`, not on the `leaderboard` view - the view carries the
// rank, the seconds and the name, and nothing else. So this reads both: the view
// for the ranking the game trusts, and `runs` for the button sequence. Asking the
// view for `steps` fails outright, which is why the two reads are separate.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight, bearer } from '../_shared/http.ts';
import { isPlayableTrack } from '../_shared/physics/tracks.js';

// A track is not expected to hold more real runs than this. The cap bounds the
// response so a runaway client cannot pull an unbounded list.
const MAX_ROWS = 1000;

// The anon key is public by design; it ships in the client. Using it here means
// this read goes through RLS exactly as a client would, rather than around it.
const anon = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_ANON_KEY')!,
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);

  const url = new URL(req.url);
  const track = Number(url.searchParams.get('track'));

  if (!isPlayableTrack(track)) {
    return json({ error: 'bad track' }, 400);
  }

  // The ranked board, from the view that owns the ranking rules.
  const { data, error } = await anon
    .from('leaderboard')
    .select('rank, username, seconds, ticks, user_id')
    .eq('track', track)
    .order('rank', { ascending: true })
    .limit(MAX_ROWS);

  if (error) return json({ error: 'board unavailable' }, 500);

  // The button sequences, keyed by user. `runs` holds one row per player per
  // track, so this joins back onto the board one-to-one.
  const { data: runRows, error: runErr } = await anon
    .from('runs')
    .select('user_id, steps')
    .eq('track', track);

  if (runErr) return json({ error: 'board unavailable' }, 500);

  const stepsFor = new Map((runRows ?? []).map((r) => [r.user_id, r.steps]));

  // A signed-in caller also learns which row is theirs, so the game can mark it
  // without a second request. Read with the caller's token so RLS applies.
  let me: string | null = null;
  let myRank: number | null = null;
  const token = bearer(req);
  if (token) {
    const { data: auth } = await anon.auth.getUser(token);
    if (auth?.user) {
      me = auth.user.id;
      const { data: mine } = await anon
        .from('leaderboard')
        .select('rank')
        .eq('track', track)
        .eq('user_id', me)
        .maybeSingle();
      myRank = mine?.rank ?? null;
    }
  }

  const rows = (data ?? []).map((r) => {
    const steps = stepsFor.get(r.user_id) ?? null;
    return {
      rank: r.rank,
      name: r.username,
      time: r.seconds,
      // A run is only watchable if its steps actually travelled. A row with no
      // steps still ranks; it just cannot be replayed.
      steps,
      watchable: !!steps,
      you: me !== null && r.user_id === me,
    };
  });

  // The pagination fields are kept because the older paginated client reads them
  // for its "you are #N" line and its page count. The current client ignores
  // them and merges `rows` into its own field instead.
  const total = rows.length;
  return json({
    rows,
    page: 1,
    pages: 1,
    total,
    you: myRank,
  });
});
