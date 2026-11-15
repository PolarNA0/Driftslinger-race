/**
 * Accounts.
 *
 * The game is offline and serverless, so these are *local* accounts: the password
 * is checked against a hash kept on this device, not against anything remote. They
 * exist so a shared phone or tablet can keep separate scores and replays, and so
 * the leaderboard can show a name instead of "You".
 *
 * Passwords are never stored. Each account keeps a random salt and the SHA-256 of
 * salt + password, so the plaintext password is not recoverable from storage. This
 * is honest, not bulletproof: anyone with the device could tamper with the file, so
 * it protects against a casual snoop, not a determined attacker. The UI says so.
 */
const ACC_KEY = 'slingdrift.accounts.v1';
const SESSION_KEY = 'slingdrift.session.v1';

function readAccounts() {
  try {
    return JSON.parse(localStorage.getItem(ACC_KEY)) || {};
  } catch {
    return {};
  }
}
function writeAccounts(all) {
  try { localStorage.setItem(ACC_KEY, JSON.stringify(all)); } catch { /* not persisted */ }
}

const norm = (u) => String(u || '').trim();

async function hash(password, salt) {
  const bytes = new TextEncoder().encode(`${salt}\u0000${password}`);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function randomSalt() {
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
}

/** Every account name on this device, oldest first. */
export function listAccounts() {
  const all = readAccounts();
  return Object.keys(all).sort((a, b) => all[a].createdAt - all[b].createdAt);
}

export function hasAccount(username) { return !!readAccounts()[norm(username)]; }

/** The signed-in username, or null. */
export function currentAccount() {
  try { return localStorage.getItem(SESSION_KEY) || null; } catch { return null; }
}

/** Create an account and sign in. Returns { ok } or { ok:false, error }. */
export async function register(username, password) {
  const name = norm(username);
  if (name.length < 3) return { ok: false, error: 'Username needs at least 3 characters.' };
  if (name.length > 16) return { ok: false, error: 'Username is at most 16 characters.' };
  if (!/^[A-Za-z0-9_.-]+$/.test(name)) return { ok: false, error: 'Letters, numbers, _ . - only.' };
  if (String(password || '').length < 4) return { ok: false, error: 'Password needs at least 4 characters.' };
  const all = readAccounts();
  if (all[name]) return { ok: false, error: 'That username is taken on this device.' };
  const salt = randomSalt();
  all[name] = { salt, hash: await hash(password, salt), createdAt: Date.now() };
  writeAccounts(all);
  signIn(name);
  return { ok: true };
}

/** Check a password and sign in. */
export async function login(username, password) {
  const name = norm(username);
  const all = readAccounts();
  const acc = all[name];
  if (!acc) return { ok: false, error: 'No such account on this device.' };
  if (await hash(password, acc.salt) !== acc.hash) return { ok: false, error: 'Wrong password.' };
  signIn(name);
  return { ok: true };
}

function signIn(name) {
  try { localStorage.setItem(SESSION_KEY, name); } catch { /* not persisted */ }
}

export function logout() {
  try { localStorage.removeItem(SESSION_KEY); } catch { /* nothing to clear */ }
}
