/**
 * Accounts.
 *
 * These are real accounts on a server, not device-local ones. Supabase Auth owns
 * the credentials - the password is bcrypt-hashed on their side, and reset and
 * confirmation emails come for free - and a `profiles` table owns the public name
 * that the leaderboard shows.
 *
 * The point of moving off the device is that a player can sign in somewhere else
 * and get their times back, which a localStorage account could never do.
 *
 * The session (access token, refresh token, expiry) is kept in localStorage. For
 * a game with no sensitive data behind the login that is the normal trade for a
 * static site, but it does mean anything running on this origin can read the
 * token. It is a leaderboard token, not a bank token.
 */

const SESSION_KEY = 'slingdrift.session.v2';
const PENDING_KEY = 'slingdrift.pending-name.v1';
const NAMES_KEY = 'slingdrift.names.v1';

/** Where the Supabase project lives, from the page's meta tags. */
export function supabaseUrl() {
  const meta = typeof document !== 'undefined' && document.querySelector('meta[name="sling-supabase"]');
  const raw = (meta && meta.content) || (typeof window !== 'undefined' && window.SLING_SUPABASE_URL) || '';
  return String(raw).replace(/\/+$/, '');
}

/** The public anon key. Safe to ship: it is designed to be visible in the page. */
export function supabaseAnonKey() {
  const meta = typeof document !== 'undefined' && document.querySelector('meta[name="sling-supabase-key"]');
  return String((meta && meta.content)
    || (typeof window !== 'undefined' && window.SLING_SUPABASE_ANON_KEY) || '');
}

/** True when the page is configured to talk to a project. */
export const authConfigured = () => !!(supabaseUrl() && supabaseAnonKey());

// --- session storage ---------------------------------------------------------

function readSession() {
  try { return JSON.parse(localStorage.getItem(SESSION_KEY)) || null; } catch { return null; }
}
function writeSession(s) {
  try {
    if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s));
    else localStorage.removeItem(SESSION_KEY);
  } catch { /* private mode: the player stays signed out for this visit */ }
}

const api = (path) => `${supabaseUrl()}${path}`;
const authHeaders = (token) => ({
  apikey: supabaseAnonKey(),
  ...(token ? { authorization: `Bearer ${token}` } : {}),
  'content-type': 'application/json',
});

/** Turn a session response from the auth service into what we store. */
const toSession = (d) => ({
  access_token: d.access_token,
  refresh_token: d.refresh_token,
  expires_at: d.expires_at || Math.floor(Date.now() / 1000) + (d.expires_in || 3600),
  user: { id: d.user.id, email: d.user.email },
});

/** Trade the refresh token for a new access token, or null if it will not. */
async function refreshSession(s) {
  try {
    const res = await fetch(api('/auth/v1/token?grant_type=refresh_token'), {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ refresh_token: s.refresh_token }),
    });
    if (!res.ok) { writeSession(null); return null; }
    const next = toSession(await res.json());
    writeSession(next);
    return next;
  } catch {
    return null;                       // offline: keep the old session, try later
  }
}

/**
 * A usable access token, refreshing it if it is close to expiry.
 *
 * Refreshing a minute early avoids the case where a token is valid when the
 * upload starts and expired by the time it arrives.
 */
export async function authToken() {
  const s = readSession();
  if (!s) return null;
  if (s.expires_at && s.expires_at * 1000 - Date.now() < 60000) {
    const next = await refreshSession(s);
    return next ? next.access_token : null;
  }
  return s.access_token;
}

// --- profiles ----------------------------------------------------------------

/** The signed-in player's public name, or null. */
export function currentAccount() {
  const s = readSession();
  return (s && s.username) || null;
}

/** The signed-in player's email, or null. */
export function currentEmail() {
  const s = readSession();
  return (s && s.user && s.user.email) || null;
}

async function fetchProfile(token, userId) {
  const res = await fetch(api(`/rest/v1/profiles?id=eq.${userId}&select=username`), {
    headers: authHeaders(token),
  });
  if (!res.ok) return null;
  const rows = await res.json();
  return rows.length ? rows[0].username : null;
}

/**
 * Create the profile row for a signed-in user.
 *
 * Returns `{ ok, username }` or `{ ok:false, error }`. A taken name comes back
 * as a 409 from the unique index, which is the honest place to catch it: two
 * people registering at once would both pass a client-side check.
 */
export async function ensureProfile(username, token) {
  const tok = token || (await authToken());
  const s = readSession();
  if (!tok || !s) return { ok: false, error: 'Not signed in.' };

  const name = String(username || '').trim();
  const bad = validateName(name);
  if (bad) return { ok: false, error: bad };

  const res = await fetch(api('/rest/v1/profiles'), {
    method: 'POST',
    headers: { ...authHeaders(tok), prefer: 'return=minimal' },
    body: JSON.stringify({ id: s.user.id, username: name }),
  });

  if (res.status === 409) return { ok: false, error: 'That username is taken.' };
  if (!res.ok) return { ok: false, error: 'Could not save that name. Try another.' };

  s.username = name;
  writeSession(s);
  rememberName(name);
  return { ok: true, username: name };
}

function validateName(name) {
  if (name.length < 3) return 'Username needs at least 3 characters.';
  if (name.length > 16) return 'Username is at most 16 characters.';
  if (!/^[A-Za-z0-9_.-]+$/.test(name)) return 'Letters, numbers, _ . - only.';
  return null;
}

// --- names seen on this device (a hint, not an account list) -----------------

export function listAccounts() {
  try { return JSON.parse(localStorage.getItem(NAMES_KEY)) || []; } catch { return []; }
}
function rememberName(name) {
  try {
    const all = listAccounts().filter((n) => n !== name);
    all.unshift(name);
    localStorage.setItem(NAMES_KEY, JSON.stringify(all.slice(0, 5)));
  } catch { /* not persisted */ }
}

// --- sign up, sign in, sign out ----------------------------------------------

/**
 * Create an account. `username` is the public name, `email` the login.
 *
 * If the project has email confirmation on, the auth service returns no session
 * and the player must click the link before they can sign in; the chosen name is
 * remembered so the first sign-in can complete the profile.
 */
export async function register(username, email, password) {
  const name = String(username || '').trim();
  const bad = validateName(name);
  if (bad) return { ok: false, error: bad };
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(email || '').trim())) {
    return { ok: false, error: 'That does not look like an email address.' };
  }
  if (String(password || '').length < 6) {
    return { ok: false, error: 'Password needs at least 6 characters.' };
  }

  let res;
  try {
    res = await fetch(api('/auth/v1/signup'), {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ email: String(email).trim(), password }),
    });
  } catch {
    return { ok: false, error: 'No connection. Check your network and try again.' };
  }

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, error: friendly(body, 'Could not create that account.') };
  }

  if (!body.access_token) {
    // Confirmation is on: no session yet. Keep the name for the first sign-in.
    try { localStorage.setItem(PENDING_KEY, name); } catch { /* fine */ }
    return { ok: true, pending: true };
  }

  // Hold on to whatever session we had. Signing up must never cost a player the
  // account they were already using: if the name turns out to be taken, we put
  // the old session back rather than leaving them signed out.
  const prev = readSession();
  writeSession(toSession(body));
  const made = await ensureProfile(name, body.access_token);
  if (!made.ok) {
    // The auth user exists but has no profile, so it is not lost: signing in
    // later asks for a name (the `needsName` path). Keep the old session.
    writeSession(prev);
    return { ok: false, error: made.error };
  }
  return { ok: true };
}

/** Sign in with an email and password. */
export async function login(email, password) {
  let res;
  try {
    res = await fetch(api('/auth/v1/token?grant_type=password'), {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ email: String(email || '').trim(), password }),
    });
  } catch {
    return { ok: false, error: 'No connection. Check your network and try again.' };
  }

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, error: friendly(body, 'Wrong email or password.') };
  }

  writeSession(toSession(body));

  // Completing a profile left over from a confirmation-flow signup.
  const existing = await fetchProfile(body.access_token, body.user.id);
  if (existing) {
    const s = readSession();
    s.username = existing;
    writeSession(s);
    rememberName(existing);
    return { ok: true };
  }

  let pending = null;
  try { pending = localStorage.getItem(PENDING_KEY); } catch { /* fine */ }
  if (pending) {
    const made = await ensureProfile(pending, body.access_token);
    if (made.ok) {
      try { localStorage.removeItem(PENDING_KEY); } catch { /* fine */ }
      return { ok: true };
    }
  }
  // Signed in, but no username yet: the caller should ask for one.
  return { ok: true, needsName: true };
}

/** Sign out on this device. */
export function logout() {
  writeSession(null);
}

/** A message worth showing, rather than the raw error code. */
function friendly(body, fallback) {
  const raw = String((body && (body.msg || body.error_description || body.message)) || '');
  if (/invalid login credentials/i.test(raw)) return 'Wrong email or password.';
  if (/already registered/i.test(raw)) return 'That email already has an account. Sign in instead.';
  if (/email address .* invalid/i.test(raw)) return 'That email address is not accepted.';
  if (/email not confirmed/i.test(raw)) return 'Confirm your email first - check your inbox.';
  if (/password/i.test(raw)) return 'Password is too short. Use at least 6 characters.';
  if (/rate limit/i.test(raw)) return 'Too many attempts. Wait a minute and try again.';
  return fallback;
}
