// The real runs on a track, for the game to merge into its ghost field.
//
// Public: no token needed, because the board is public data. Reading it with the
// anon key is enough, and RLS on `runs` and `profiles` already allows that read.
//
// This returns the real runs rather than a rendered board. The board a player
// sees is one board: the game holds a 50,000-entry ghost field locally and slots
// these runs into it by time. Paginating here would fight that, because the game
// needs every real run to place them all, and the ghost field is what supplies
// the depth.
//
// `steps` travels with each row so a real run can be watched. A baked ghost is
// regenerated from its id, but a real run has no id to regenerate from.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight, bearer } from '../_shared/http.ts';

// A track is not expected to hold more real runs than this. The cap bounds the
// response; the ghost field behind it is unbounded and never travels.
const MAX_ROWS = 1000;

// The anon key is public by design; it ships in the browser. Using it here means
// this read goes through RLS exactly as a browser would, rather than around it.
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

  if (!Number.isInteger(track) || track < 1 || track > 25) {
    return json({ error: 'bad track' }, 400);
  }

  const { data, error } = await anon
    .from('leaderboard')
    .select('username, seconds, steps, user_id')
    .eq('track', track)
    .order('seconds', { ascending: true })
    .limit(MAX_ROWS);

  if (error) return json({ error: 'board unavailable' }, 500);

  // A signed-in caller also learns which row is theirs, so the game can mark it
  // without a second request. Read with the caller's token so RLS applies.
  let me: string | null = null;
  const token = bearer(req);
  if (token) {
    const { data: auth } = await anon.auth.getUser(token);
    if (auth?.user) me = auth.user.id;
  }

  const rows = (data ?? []).map((r) => ({
    name: r.username,
    time: r.seconds,
    steps: r.steps,
    you: me !== null && r.user_id === me,
  }));

  return json({ rows });
});
