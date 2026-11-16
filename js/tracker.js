/**
 * The Discord record tracker's message.
 *
 * Two templates, both editable by the admin: one for a world record, one for any
 * other improvement. The two cases read differently enough to be worth separate
 * wording, and a world record is the one worth interrupting a channel for.
 *
 * Placeholders are `{name}`. A run that beat the record reports how much it beat
 * it by with a minus (`[WR -0.017]`); any other run reports how far behind the
 * record it sits with a plus (`[WR +0.017]`).
 */

export const DEFAULT_WR_MESSAGE =
  '{player} set a new world record on track {track} with {time}s [WR -{delta}]';

export const DEFAULT_POS_MESSAGE =
  '{player} took position {rank} on track {track} with {time}s [WR +{delta}]';

/**
 * Fill a template. An unknown placeholder is left alone rather than blanked, so a
 * typo shows up in the channel instead of silently eating text.
 */
export function formatMessage(template, vars) {
  return String(template).replace(/\{(\w+)\}/g, (whole, key) =>
    (key in vars ? String(vars[key]) : whole));
}

const fmtTime = (s) => Number(s).toFixed(3);

/**
 * Build the message for a finished run.
 *
 * `wrBefore` is the record as it stood before this run was uploaded, or null when
 * the track had no record yet. A run at or under it is a world record and gets the
 * WR template with a minus delta; anything else gets the position template with a
 * plus delta against the same record (a non-record run cannot have moved it).
 *
 * Returns `{ template, vars, message, isRecord }` so the caller can post the
 * message and a test can check the pieces.
 */
export function recordMessage({ player, track, time, rank, wrBefore }, settings) {
  const isRecord = wrBefore === null || time <= wrBefore;
  const delta = wrBefore === null ? 0
    : isRecord ? wrBefore - time
    : time - wrBefore;
  const vars = {
    player,
    track,
    time: fmtTime(time),
    rank: Number.isFinite(rank) ? rank : '?',
    delta: fmtTime(delta),
    sign: isRecord ? '-' : '+',
  };
  const template = isRecord
    ? (settings?.wrMessage || DEFAULT_WR_MESSAGE)
    : (settings?.posMessage || DEFAULT_POS_MESSAGE);
  return { template, vars, message: formatMessage(template, vars), isRecord };
}
