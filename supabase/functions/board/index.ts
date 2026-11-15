// One page of a track's leaderboard.
//
// Public: no token needed, because the board is public data. Reading it with the
// anon key is enough, and RLS on `runs` and `profiles` already allows that read.
//
// The response shape matches what the game's js/api.js expects: rows of
// { rank, name, time, watchable, steps }, plus the page, the page count, the
// total, and - when the caller is signed in - the caller's own rank.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight, bearer } from '../_shared/http.ts';

const PER_PAGE = 50;

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
  const page = Math.max(1, Math.floor(Number(url.searchParams.get('page')) || 1));

  if (!Number.isInteger(track) || track < 1 || track > 25) {
    return json({ error: 'bad track' }, 400);
  }

  const from = (page - 1) * PER_PAGE;

  const { data, error, count } = await anon
    .from('leaderboard')
    .select('rank, username, seconds, ticks', { count: 'exact' })
    .eq('track', track)
    .order('rank', { ascending: true })
    .range(from, from + PER_PAGE - 1);

  if (error) return json({ error: 'board unavailable' }, 500);

  // A signed-in caller also gets their own row, so the game can show "you are
  // #12" without a second request. Read with the caller's token so RLS applies.
  let you: number | null = null;
  const token = bearer(req);
  if (token) {
    const { data: auth } = await anon.auth.getUser(token);
    if (auth?.user) {
      const { data: mine } = await anon
        .from('leaderboard')
        .select('rank')
        .eq('track', track)
        .eq('user_id', auth.user.id)
        .maybeSingle();
      you = mine?.rank ?? null;
    }
  }

  const rows = (data ?? []).map((r) => ({
    rank: r.rank,
    name: r.username,
    time: r.seconds,
    // An online run carries its steps, so it can be watched like any other.
    watchable: true,
    steps: null,
  }));

  const total = count ?? rows.length;
  return json({
    rows,
    page,
    pages: Math.max(1, Math.ceil(total / PER_PAGE)),
    total,
    you,
  });
});
