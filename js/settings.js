import { getPref, setPref } from './storage.js';
import { hexToRgb, rgbToHex, MIN_ZOOM, MAX_ZOOM } from './render.js';
import { DEFAULT_WR_MESSAGE, DEFAULT_POS_MESSAGE } from './tracker.js';

/**
 * Player settings, and the admin login behind them.
 *
 * Everything here lives on the device: zoom, the hook colour and the admin flag
 * are preferences, not account data, so they work offline and do not need a
 * sign-in. The one thing that leaves the device is the Discord webhook, and only
 * because the server has to post to it.
 *
 * The admin code is checked here, in the client. That is enough to keep the
 * settings out of the way of a normal player, and nothing more: the code ships in
 * this file, so anyone who opens devtools can read it. It is a lock on a cupboard,
 * not a safe. The real gate on anything that matters is on the server - a webhook
 * only does something if the server is willing to post to it - so treat this as
 * "keep the UI tidy", not "this is a security boundary".
 */

export const ADMIN_CODE = '0404';

const DEFAULT_ROPE = '#ffffff';
const ZOOM_KEY = 'zoom';
const ROPE_KEY = 'ropeColour';
const ADMIN_KEY = 'admin';
const WEBHOOK_KEY = 'discordWebhook';
const WR_MSG_KEY = 'trackerWrMessage';
const POS_MSG_KEY = 'trackerPosMessage';

/** Clamp a zoom multiplier to the range the renderer accepts. */
export function clampZoom(z) {
  const n = Number(z);
  if (!Number.isFinite(n)) return 1;
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, n));
}

/** Is this the admin code? Compared as a string so leading zeros survive. */
export function isAdminCode(input) {
  return String(input).trim() === ADMIN_CODE;
}

/**
 * Is this a Discord webhook URL?
 *
 * Checked on the client so an obvious typo is caught before the server ever sees
 * it. It is deliberately narrow: only discord.com's webhook path, over https, so
 * a mistyped field cannot be used to point the server at some other host.
 */
export function validWebhook(url) {
  const s = String(url).trim();
  if (!s) return false;
  let u;
  try { u = new URL(s); } catch { return false; }
  if (u.protocol !== 'https:') return false;
  if (u.hostname !== 'discord.com' && u.hostname !== 'discordapp.com') return false;
  return /^\/api\/(v\d+\/)?webhooks\/\d+\/[\w-]+$/.test(u.pathname);
}

/** The saved settings, with anything malformed repaired rather than trusted. */
export function loadSettings() {
  const zoom = clampZoom(getPref(ZOOM_KEY, 1));
  const rawRope = getPref(ROPE_KEY, DEFAULT_ROPE);
  const rope = /^#[0-9a-f]{6}$/i.test(String(rawRope)) ? String(rawRope).toLowerCase() : DEFAULT_ROPE;
  return {
    zoom,
    rope,
    ropeRgb: hexToRgb(rope),
    admin: getPref(ADMIN_KEY, false) === true,
    webhook: getPref(WEBHOOK_KEY, '') || '',
    wrMessage: messageOr(getPref(WR_MSG_KEY, ''), DEFAULT_WR_MESSAGE),
    posMessage: messageOr(getPref(POS_MSG_KEY, ''), DEFAULT_POS_MESSAGE),
  };
}

/** A saved template, or the default. A blank or non-string falls back. */
function messageOr(value, fallback) {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

export const saveZoom = (z) => setPref(ZOOM_KEY, clampZoom(z));
export const saveRope = (hex) =>
  setPref(ROPE_KEY, /^#[0-9a-f]{6}$/i.test(String(hex)) ? String(hex).toLowerCase() : DEFAULT_ROPE);
export const saveAdmin = (on) => setPref(ADMIN_KEY, !!on);
export const saveWebhook = (url) => setPref(WEBHOOK_KEY, String(url).trim());

/** Save the two tracker templates. A blank one falls back to the default. */
export function saveTrackerMessages(wr, pos) {
  setPref(WR_MSG_KEY, String(wr || '').trim());
  setPref(POS_MSG_KEY, String(pos || '').trim());
}
export const DEFAULT_ROPE_HEX = DEFAULT_ROPE;
export { rgbToHex, hexToRgb };
