// Upload a finished run.
//
// The client sends the button steps, never a time. This function replays them
// with the game's own physics and stores what the physics produces, so a forged
// time has nothing to attach to. It then returns the player's real rank, which
// the client shows instead of its local estimate.
//
// Auth: the caller's Supabase access token identifies the player. The token is
// verified before anything is written, and the row is attributed to that user, so
// a client cannot post a run as somebody else.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight, bearer } from '../_shared/http.ts';
import { replayRun } from '../_shared/physics/verify.js';
import {
  DEFAULT_POS_MESSAGE, DEFAULT_WR_MESSAGE, formatMessage, messageVars, postWebhook,
} from '../_shared/tracker.ts';

// The service-role key bypasses RLS, which is the point: it is the only writer
// allowed near the `runs` table. It is injected by the platform and never
// reaches the player.
const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

/** Turn the verified physics result into the response the client expects. */
const verdict = (r: { ok: boolean; reason?: string; ticks?: number; time?: number }) =>
  r.ok ? { ok: true, time: r.time } : { ok: false, reason: r.reason };

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const token = bearer(req);
  if (!token) return json({ error: 'missing token' }, 401);

  // Verify the token with the auth service and get the user it belongs to.
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) return json({ error: 'bad token' }, 401);

  let body: { track?: unknown; steps?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  const track = Number(body?.track);
  const steps = body?.steps;

  // A fast shape check before the expensive part. Replaying is about 9ms of CPU,
  // so a malformed payload is rejected before it is paid for.
  if (typeof steps !== 'string' || !/^[01]+$/.test(steps) || steps.length > 7200) {
    return json({ error: 'bad steps' }, 422);
  }

  const result = replayRun(track, steps);
  if (!result.ok) {
    // 422: the run is invalid and re-sending it will not help, so the client's
    // offline queue drops it rather than retrying forever.
    return json({ error: result.reason, ...verdict(result) }, 422);
  }

  const { data, error } = await admin.rpc('submit_run', {
    p_user: user.id,
    p_track: track,
    p_ticks: result.ticks,
    p_steps: steps,
  });

  if (error) {
    // A missing profile is the one error worth naming: it means the account
    // signed up but never picked a username.
    if (error.code === '23503') return json({ error: 'no profile' }, 409);
    return json({ error: 'store failed' }, 500);
  }

  // The tracker posts only on a genuine improvement, and only after the run is
  // safely stored - a webhook failure must never cost a player their run. It is
  // awaited so the serverless runtime is not torn down mid-post, but its result
  // is not part of the response: whether Discord accepted the message has no
  // bearing on the run.
  if (data.improved) {
    await announce({
      userId: user.id, track, ticks: data.ticks, rank: data.rank,
      wrBefore: data.wr_before ?? null, wrAfter: data.wr_after ?? null,
    });
  }

  return json({
    ok: true,
    time: data.ticks / 120,
    rank: data.rank,
    total: data.total,
    improved: data.improved,
  });
});

/**
 * Post an improvement to the admin's Discord channel.
 *
 * The webhook and the two message templates live in `tracker_config`, set once by
 * an admin, so this announces every player rather than only the admin. A world
 * record gets the WR template and a minus delta; any other improvement gets the
 * position template and a plus delta.
 */
async function announce(run: {
  userId: string; track: number; ticks: number; rank: number;
  wrBefore: number | null; wrAfter: number | null;
}) {
  const { data: cfg } = await admin
    .from('tracker_config')
    .select('webhook_url, wr_message, pos_message')
    .eq('id', 1)
    .maybeSingle();

  const url = cfg?.webhook_url;
  if (!url) return;                        // the tracker is off

  // The player's name for the board, falling back to something readable if the
  // profile read fails rather than dropping the announcement.
  const { data: prof } = await admin
    .from('profiles')
    .select('username')
    .eq('id', run.userId)
    .maybeSingle();

  // Strictly under the record is a new record; equalling it is only a place on the
  // board, so it takes the position template (and a +0.000 delta) instead of
  // claiming a new best by zero.
  const isRecord = run.wrBefore === null || run.ticks < run.wrBefore;
  const template = isRecord
    ? (cfg?.wr_message || DEFAULT_WR_MESSAGE)
    : (cfg?.pos_message || DEFAULT_POS_MESSAGE);

  const vars = messageVars({
    player: prof?.username ?? 'A player',
    track: run.track,
    ticks: run.ticks,
    rank: run.rank,
    wrBeforeTicks: run.wrBefore,
    wrAfterTicks: run.wrAfter,
  });

  await postWebhook(url, formatMessage(template, vars));
}
