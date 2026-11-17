// The Discord record tracker.
//
// This runs on the server, not in the player's client, and that is the whole
// point: the webhook is one URL the admin sets once, and every player's run is
// announced through it. A client-side tracker only ever announced the admin's
// own runs, because only the admin's device held the webhook.
//
// The webhook URL never leaves the server. It is a credential - anyone holding
// it can post to the channel - so it is stored in `tracker_config` (service role
// only) and never returned to a client.

const TIMEOUT = 8000;

export type TrackerConfig = {
  webhook_url: string | null;
  wr_message: string;
  pos_message: string;
};

/** The message a new world record posts, when the admin has not set their own. */
export const DEFAULT_WR_MESSAGE =
  '{player} set a new world record on track {track} with {time}s [WR -{delta}]';

/** The message any other improvement posts. */
export const DEFAULT_POS_MESSAGE =
  '{player} took position {rank} on track {track} with {time}s [WR +{delta}]';

/**
 * Fill a message template.
 *
 * Placeholders are `{name}`. An unknown placeholder is left alone rather than
 * blanked, so a typo shows up in the channel instead of silently eating text.
 * A template with no placeholders still works - it just posts as written.
 */
export function formatMessage(template: string, vars: Record<string, string | number>): string {
  return String(template).replace(/\{(\w+)\}/g, (whole, key) =>
    key in vars ? String(vars[key]) : whole);
}

/** Seconds to three decimals - the precision the board ranks by. */
export const fmtTime = (seconds: number) => Number(seconds).toFixed(3);

/**
 * How far a run is from the world record, and which way to show it.
 *
 * A run that beat the old record reports how much it beat it by, with a minus:
 * `[WR -0.017]`. Every other run - including one that only equalled the record -
 * reports how far behind the record it sits, with a plus: `[WR +0.000]`. Equalling
 * the record is a place on the board, not a new best, so it must not read as
 * "beat the record by 0.000". The magnitude is always positive; only the sign differs.
 */
export function recordDelta(
  runTicks: number, wrBeforeTicks: number | null, wrAfterTicks: number | null,
): { sign: '-' | '+'; delta: number } {
  if (wrBeforeTicks !== null && runTicks < wrBeforeTicks) {
    return { sign: '-', delta: (wrBeforeTicks - runTicks) / 120 };
  }
  const wr = wrAfterTicks ?? runTicks;
  return { sign: '+', delta: Math.abs(runTicks - wr) / 120 };
}

/** Build the two variables a template needs, from a finished run. */
export function messageVars(opts: {
  player: string; track: number; ticks: number; rank: number;
  wrBeforeTicks: number | null; wrAfterTicks: number | null;
}): Record<string, string | number> {
  const { sign, delta } = recordDelta(opts.ticks, opts.wrBeforeTicks, opts.wrAfterTicks);
  return {
    player: opts.player,
    track: opts.track,
    time: fmtTime(opts.ticks / 120),
    rank: opts.rank,
    delta: fmtTime(delta),
    sign,
  };
}

/** Post `content` to a webhook. Returns true only if Discord accepted it. */
export async function postWebhook(url: string | null, content: string): Promise<boolean> {
  if (!url) return false;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ content: String(content).slice(0, 1900) }),
      signal: ctl.signal,
    });
    return res.ok;
  } catch {
    return false;                    // offline, DNS, timeout, or a dead webhook
  } finally {
    clearTimeout(timer);
  }
}
