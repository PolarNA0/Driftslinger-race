import { Game } from './game.js';
import { fmtDist } from './util.js';
import {
  getRecord, bestDistance, getBestTime, getReplay, getPref, setPref,
  getRuns, allRuns,
} from './storage.js';
import { TRACK_COUNT } from './tracks.js';
import { boardPage, pageForRank, playerRank, worldRecord } from './leaderboard.js';
import { CAR_COLOURS } from './render.js';
import { enqueue, flush, fetchBoard, clientId, queueLength } from './api.js';
import { encodeSteps } from './replay.js';
import {
  currentAccount, currentEmail, listAccounts, register, login, logout,
  ensureProfile,
} from './account.js';

const $ = (id) => document.getElementById(id);
const TRACKS = Array.from({ length: TRACK_COUNT }, (_, i) => i + 1);

const canvas = $('view');
const game = new Game(canvas, { onChange: onGameChange, onTick: onTick });

let menuSeed = Number(localStorage.getItem('slingdrift.track')) || 1;
if (!TRACKS.includes(menuSeed)) menuSeed = 1;
let menuMode = localStorage.getItem('slingdrift.mode') || 'speedrun';
if (menuMode !== 'endless') menuMode = 'speedrun';
// Which ghost to race alongside: 'off', 'wr' (world record) or 'self' (your best).
let ghostMode = getPref('ghostMode', 'off');
if (!['off', 'wr', 'self'].includes(ghostMode)) ghostMode = 'off';

const fmtTime = (s) => (s == null ? '--' : `${s.toFixed(3)}s`);
const fmtRank = (n) => (n == null ? '--' : `#${n.toLocaleString('en-US')}`);
const fmtCount = (n) => n.toLocaleString('en-US');
const fmtAgo = (at) => {
  const s = Math.max(0, (Date.now() - at) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
};

// Car skin, remembered across sessions.
let carSkin = Number(getPref('carSkin', 0));
if (!Number.isInteger(carSkin) || carSkin < 0 || carSkin >= CAR_COLOURS.length) carSkin = 0;
game.carSkin = carSkin;

// Leaderboard view state, and what (if anything) we are currently watching.
let boardSeed = 1;
let boardPageNo = 1;
let watching = null;   // { kind:'ghost'|'self', seed, ghostId, name, time, label, tag, sub }

function showOverlay(id) {
  for (const el of document.querySelectorAll('.over')) el.hidden = el.id !== id;
}
function hideOverlays() {
  for (const el of document.querySelectorAll('.over')) el.hidden = true;
}

function showRoundButton(on) { $('btn-restart-round').hidden = !on; }

function showWatchBadge(text) {
  $('watch-label').textContent = text;
  $('watch-badge').hidden = false;
}
function hideWatchBadge() { $('watch-badge').hidden = true; }

const playerName = () => currentAccount() || 'You';

// --- menu lists --------------------------------------------------------------
function buildCarList() {
  const list = $('car-list');
  list.innerHTML = '';
  CAR_COLOURS.forEach((c, i) => {
    const b = document.createElement('button');
    b.className = 'car' + (i === carSkin ? ' is-active' : '');
    b.setAttribute('aria-label', c.name);
    b.title = c.name;
    const sw = document.createElement('span');
    sw.className = 'car__sw';
    sw.style.background = `rgb(${c.body.join(',')})`;
    sw.style.borderColor = `rgb(${c.dark.join(',')})`;
    b.appendChild(sw);
    b.addEventListener('click', () => {
      carSkin = i;
      setPref('carSkin', i);
      game.carSkin = i;
      game.renderer.setCar(i);
      buildCarList();
    });
    list.appendChild(b);
  });
}

function buildAccountBar() {
  const bar = $('acct-bar');
  bar.innerHTML = '';
  const who = currentAccount();
  const email = currentEmail();

  const label = document.createElement('span');
  label.className = 'acct__who';
  // Three states, not two: signed in with a leaderboard name, signed in without
  // one yet, and a guest. The middle case is reachable when a project has email
  // confirmation on and the profile was never finished.
  label.textContent = who ? `Signed in as ${who}`
    : email ? `Signed in as ${email} - pick a name to race`
    : 'Playing as guest';
  bar.appendChild(label);

  const btn = document.createElement('button');
  btn.className = 'btn btn--small';
  btn.textContent = who ? 'Switch' : email ? 'Pick a name' : 'Sign in';
  btn.addEventListener('click', () => {
    if (email && !who) openAccount('name');
    else openAccount(who ? 'switch' : 'login');
  });
  bar.appendChild(btn);

  if (who || email) {
    const out = document.createElement('button');
    out.className = 'btn btn--small btn--ghost';
    out.textContent = 'Sign out';
    out.addEventListener('click', () => {
      logout();
      buildAccountBar();
      buildTrackList();
    });
    bar.appendChild(out);
  }
}

function buildGhostList() {
  for (const b of document.querySelectorAll('#ghost-list .mode')) {
    b.classList.toggle('is-active', b.dataset.ghost === ghostMode);
  }
}

function buildModeList() {
  for (const b of document.querySelectorAll('#ghost-list .mode')) {
  b.addEventListener('click', () => {
    ghostMode = b.dataset.ghost;
    setPref('ghostMode', ghostMode);
    buildGhostList();
  });
}

for (const b of document.querySelectorAll('#mode-list .mode')) {
    b.classList.toggle('is-active', b.dataset.mode === menuMode);
  }
}

function buildTrackList() {
  const list = $('seed-list');
  list.innerHTML = '';
  for (const seed of TRACKS) {
    const b = document.createElement('button');
    b.className = 'seed' + (seed === menuSeed ? ' is-active' : '');
    const best = menuMode === 'speedrun' ? getBestTime(seed) : null;
    const rec = menuMode === 'speedrun' ? null : getRecord(seed);
    const sub = menuMode === 'speedrun'
      ? (best == null ? '--' : fmtTime(best))
      : (rec.dist > 0 ? fmtDist(rec.dist) : '--');
    b.innerHTML = `Track ${seed}<small>${sub}</small>`;
    b.addEventListener('click', () => {
      menuSeed = seed;
      localStorage.setItem('slingdrift.track', String(seed));
      buildTrackList();
    });
    list.appendChild(b);
  }
}

// --- game callbacks ----------------------------------------------------------
function onGameChange(g, extra) {
  if (g.isReplay) {
    if (extra && extra.died) { endWatching(); toMenu(); return; }
    if (extra && extra.finished) {
      $('replay-tag').textContent = watching ? watching.tag : 'Replay';
      $('replay-sub').textContent = watching ? watching.sub : 'That run, replayed.';
      // Keep `watching` (so "Watch again" works) but drop the badge, which would
      // otherwise float above the overlay.
      hideWatchBadge();
      showOverlay('over-replay-done');
      return;
    }
    return;
  }
  if (extra && extra.died) {
    if (g.mode === 'speedrun') {
      $('dead-tag').textContent = 'Crashed';
      $('dead-dist').textContent = fmtTime(g.time);
      $('dead-sub').textContent = `best ${fmtTime(g.record.time)}`;
    } else {
      const beat = g.metres > extra.prev.dist;
      $('dead-tag').textContent = beat ? 'New best' : 'Crashed';
      $('dead-dist').textContent = fmtDist(g.metres);
      const best = Math.max(extra.prev.dist, g.metres);
      $('dead-sub').textContent = `best ${fmtDist(best)} · ${g.car.grabbed} corners`;
    }
    showOverlay('over-dead');
    $('hint').hidden = true;
    showRoundButton(false);
  }
  if (extra && extra.finished) {
    const beat = extra.prev === null || g.time < extra.prev;
    $('finish-tag').textContent = beat ? 'New best time' : 'Finished';
    $('finish-time').textContent = fmtTime(g.time);
    const best = extra.prev === null ? g.time : Math.min(extra.prev, g.time);
    $('finish-sub').textContent = `best ${fmtTime(best)}`;
    const rank = playerRank(g.seed, best);
    $('finish-rank').textContent = rank ? `${fmtRank(rank)} on Track ${g.seed}` : '';
    $('btn-watch').hidden = !getReplay(g.seed);
    $('btn-finish-wr').hidden = !worldRecord(g.seed);
    showOverlay('over-finish');
    $('hint').hidden = true;
    showRoundButton(false);
    // Queue the run, then try to send it. The local board is already correct, so
    // this only ever adds a real rank on top of it.
    enqueue({ track: g.seed, steps: encodeSteps(g.steps), name: playerName() });
    submitQueued(g.seed);
  }
}

/** Send queued runs and, if one lands, show the player's real server rank. */
async function submitQueued(seed) {
  const res = await flush();
  if (!res || res.track !== seed) return;
  const el = $('finish-rank');
  if (el) el.textContent = `${fmtRank(res.rank)} of ${fmtCount(res.total)} online`;
}

function onTick(g) {
  if (g.isReplay) {
    $('hud-dist').textContent = fmtTime(g.time);
    $('hud-sub').textContent = watching
      ? `${watching.label} · Track ${g.seed}` : `replay · Track ${g.seed}`;
    return;
  }
  if (g.mode === 'speedrun') {
    $('hud-dist').textContent = fmtTime(g.time);
    const best = g.record.time;
    $('hud-sub').textContent = best == null ? 'best --' : `best ${fmtTime(best)}`;
  } else {
    $('hud-dist').textContent = fmtDist(g.metres);
    $('hud-sub').textContent = `best ${fmtDist(Math.max(g.record.dist, g.metres))}`;
  }
  if (g.car.grabbed > 0 || g.car.time > 1.2) $('hint').hidden = true;
}

function hudReset(g) {
  if (g.isReplay) {
    $('hud-dist').textContent = '0.000s';
    $('hud-sub').textContent = watching
      ? `${watching.label} · Track ${g.seed}` : `replay · Track ${g.seed}`;
  } else if (g.mode === 'speedrun') {
    $('hud-dist').textContent = '0.000s';
    const best = getBestTime(g.seed);
    $('hud-sub').textContent = best == null ? 'best --' : `best ${fmtTime(best)}`;
  } else {
    $('hud-dist').textContent = '0 m';
    $('hud-sub').textContent = `best ${fmtDist(getRecord(g.seed).dist)}`;
  }
}

// --- starting runs -----------------------------------------------------------
function startRun(seed) {
  endWatching();
  hideOverlays();
  game.load(seed, menuMode);
  applyGhost(seed);
  hudReset(game);
  $('hint').hidden = false;
  showRoundButton(true);
  // Going back to the menu stops the loop, so a run started from a button has to
  // restart it. (Tapping the canvas restarts it in pressDown instead.)
  if (!game.running) game.run();
  game.start();
}

/**
 * Put the chosen ghost on the track, if there is one to race. Called after
 * game.load(), which clears any previous ghost. Only speedrun has a ghost: the
 * endless road is the same for everyone, so a pace car would be meaningless.
 */
function applyGhost(seed) {
  if (menuMode !== 'speedrun' || ghostMode === 'off') return;
  if (ghostMode === 'self') { game.setGhostSelf(seed); return; }
  const wr = worldRecord(seed);
  if (wr) game.setGhostReplay(seed, wr.ghostId, wr.name, wr.time);
}

function watchOwnReplay(seed) {
  if (!getReplay(seed)) return;
  const best = getBestTime(seed);
  watching = {
    kind: 'self', seed, ghostId: null, name: null, time: best,
    label: `${playerName()}'s best`, tag: 'Your best run',
    sub: `Track ${seed} · ${fmtTime(best)}`,
  };
  hideOverlays();
  if (!game.loadReplay(seed)) { endWatching(); return; }
  hudReset(game);
  $('hint').hidden = true;
  showRoundButton(false);
  showWatchBadge(`Watching your best · ${fmtTime(best)}`);
  if (!game.running) game.run();
  game.start();
}

function watchGhost(seed, ghostId, name, time) {
  watching = {
    kind: 'ghost', seed, ghostId, name, time,
    label: `${name}'s ghost`, tag: 'Ghost run',
    sub: `${name} · Track ${seed} · ${fmtTime(time)}`,
  };
  hideOverlays();
  if (!game.loadGhostReplay(seed, ghostId)) { endWatching(); toMenu(); return; }
  hudReset(game);
  $('hint').hidden = true;
  showRoundButton(false);
  showWatchBadge(`Watching ${name} · ${fmtTime(time)}`);
  if (!game.running) game.run();
  game.start();
}

function endWatching() { watching = null; hideWatchBadge(); }

/** Watch a run submitted to the server, replayed from the steps stored with it. */
function watchGhostSteps(seed, steps, name, time) {
  watching = {
    kind: 'ghost', seed, name, time,
    label: `${name}'s ghost`, tag: 'Ghost run',
    sub: `${name} · Track ${seed} · ${fmtTime(time)}`,
  };
  hideOverlays();
  if (!game.loadStepsReplay(seed, steps)) { endWatching(); toMenu(); return; }
  hudReset(game);
  $('hint').hidden = true;
  showRoundButton(false);
  showWatchBadge(`Watching ${name} · ${fmtTime(time)}`);
  if (!game.running) game.run();
  game.start();
}

// --- leaderboard -------------------------------------------------------------
function renderBoard() {
  const seed = boardSeed;
  const best = getBestTime(seed);
  const me = best == null ? null : { name: playerName(), time: best };
  const page = boardPage(seed, boardPageNo, { player: me });
  boardPageNo = page.page;

  $('lb-title').textContent = `Track ${seed}`;
  $('lb-note').textContent = page.playerRank
    ? `You are ${fmtRank(page.playerRank)} of ${fmtCount(page.total)}`
    : `${fmtCount(page.total)} racers · set a time to join`;

  // World-record banner: the fastest ghost, and the way to watch it.
  const wr = worldRecord(seed);
  $('lb-wr').hidden = !wr;
  if (wr) {
    $('lb-wr-name').textContent = wr.name;
    $('lb-wr-time').textContent = fmtTime(wr.time);
    $('lb-wr').dataset.ghostId = String(wr.ghostId);
    $('lb-wr').dataset.name = wr.name;
    $('lb-wr').dataset.time = String(wr.time);
  }

  drawBoardRows(seed, page.rows, page.page, page.pages);
  // Then, if the server has real runs for this track, swap in the real board.
  // Local rendering happens first so the board is never blank while it loads.
  overlayOnline(seed, page.page);
}

/** Replace the local board with the server's, when the server has entries. */
async function overlayOnline(seed, pageNo) {
  const online = await fetchBoard(seed, pageNo);
  if (!online || !online.rows || !online.rows.length) return;
  if (boardSeed !== seed) return;              // the player moved on
  $('lb-note').textContent = online.you
    ? `You are ${fmtRank(online.you)} of ${fmtCount(online.total)} online`
    : `${fmtCount(online.total)} online · set a time to join`;
  drawBoardRows(seed, online.rows, online.page, online.pages);
}

function drawBoardRows(seed, rows, pageNo, pages) {
  const body = $('lb-rows');
  body.innerHTML = '';
  for (const r of rows) {
    // Only a run with real steps behind it can be watched: a baked head row is
    // regenerated from its ghost id, an online row replays its stored steps, and
    // the player's own best is on the device. A generated row has no ghost, so it
    // is a plain row - offering "Watch" on a run that does not exist would be a lie.
    const canWatch = r.you || r.watchable;
    const row = document.createElement(canWatch ? 'button' : 'div');
    row.className = 'lb__row' + (r.you ? ' is-you' : '') + (canWatch ? '' : ' is-plain');
    const action = r.you ? 'Replay' : canWatch ? 'Watch' : '';
    row.innerHTML =
      `<span class="lb__rank">${fmtCount(r.rank)}</span>` +
      `<span class="lb__name">${r.name}</span>` +
      `<span class="lb__time">${fmtTime(r.time)}</span>` +
      `<span class="lb__play">${action}</span>`;
    if (canWatch) {
      row.addEventListener('click', () => {
        if (r.you) watchOwnReplay(seed);
        else if (r.steps) watchGhostSteps(seed, r.steps, r.name, r.time);
        else watchGhost(seed, r.ghostId, r.name, r.time);
      });
    }
    body.appendChild(row);
  }
  setBoardPager(pageNo, pages);
}

function setBoardPager(pageNo, pages) {
  $('lb-page').value = String(pageNo);
  $('lb-pages').textContent = `/ ${fmtCount(pages)}`;
  $('lb-prev').disabled = pageNo <= 1;
  $('lb-next').disabled = pageNo >= pages;
}

function showLeaderboard(seed) {
  boardSeed = seed;
  const best = getBestTime(seed);
  boardPageNo = best == null ? 1 : pageForRank(playerRank(seed, best));
  renderBoard();
  showOverlay('over-board');
}

// --- history -----------------------------------------------------------------
function renderHistory() {
  const runs = allRuns();
  $('hist-title').textContent = 'History';
  const who = currentAccount();
  $('hist-sub').textContent = runs.length
    ? `${who || 'Guest'} · ${runs.length} finished run${runs.length === 1 ? '' : 's'}`
    : 'No finished runs yet.';
  const body = $('hist-rows');
  body.innerHTML = '';
  for (const r of runs.slice(0, 60)) {
    const best = getBestTime(r.seed);
    const pb = best != null && Math.abs(r.time - best) < 1e-9;
    const row = document.createElement('div');
    row.className = 'lb__row' + (pb ? ' is-you' : '');
    row.innerHTML =
      `<span class="lb__rank">Track ${r.seed}</span>` +
      `<span class="lb__name">${pb ? 'Personal best' : 'Finished'}</span>` +
      `<span class="lb__time">${fmtTime(r.time)}</span>` +
      `<span class="lb__play">${fmtAgo(r.at)}</span>`;
    body.appendChild(row);
  }
}

function showHistory() {
  renderHistory();
  showOverlay('over-history');
}

// --- accounts ----------------------------------------------------------------
let acctMode = 'login';   // 'login' | 'register' | 'name'

function openAccount(mode) {
  acctMode = mode === 'register' ? 'register' : mode === 'name' ? 'name' : 'login';

  // The username field is only needed to create an account, or to complete one
  // after signing in without a name. On plain sign-in the email is the identity.
  const wantsName = acctMode !== 'login';
  $('acct-user').hidden = !wantsName;
  $('acct-email').hidden = acctMode === 'name';
  $('acct-sub').textContent = acctMode === 'name'
    ? 'Signed in. Choose the name that will appear on the leaderboard.'
    : acctMode === 'register'
      ? 'Create an account to upload your times and race the shared leaderboard.'
      : 'Sign in to upload your times and race the shared leaderboard.';

  $('acct-title').textContent = acctMode === 'name' ? 'Pick a username'
    : acctMode === 'register' ? 'Create an account' : 'Sign in';
  $('acct-submit').textContent = acctMode === 'name' ? 'Save name'
    : acctMode === 'register' ? 'Create account' : 'Sign in';
  $('acct-toggle').hidden = acctMode === 'name';
  $('acct-toggle').textContent =
    acctMode === 'register' ? 'I already have an account' : 'Create an account';
  $('acct-error').textContent = '';
  $('acct-pass').value = '';

  if (acctMode === 'register') {
    // Offer a name seen on this device as a hint, not as an account.
    const known = listAccounts();
    $('acct-user').placeholder = known.length ? `e.g. ${known[0]}` : 'Username';
  }

  showOverlay('over-account');
  setTimeout(() => (wantsName ? $('acct-user') : $('acct-email')).focus(), 30);
}

async function submitAccount() {
  const user = $('acct-user').value;
  const email = $('acct-email').value;
  const pass = $('acct-pass').value;

  if (acctMode === 'name') {
    const res = await ensureProfile(user);
    if (!res.ok) { $('acct-error').textContent = res.error; return; }
    afterSignIn();
    return;
  }

  const res = acctMode === 'register'
    ? await register(user, email, pass)
    : await login(email, pass);

  if (!res.ok) { $('acct-error').textContent = res.error; return; }

  // Registered but the project wants the email confirmed first.
  if (res.pending) {
    $('acct-error').textContent = 'Check your email to confirm, then sign in.';
    $('acct-pass').value = '';
    return;
  }
  // Signed in, but this account has no leaderboard name yet.
  if (res.needsName) { openAccount('name'); return; }

  afterSignIn();
}

function afterSignIn() {
  buildAccountBar();
  buildTrackList();
  showOverlay('menu');
  // Anything raced as a guest can go up now that there is an account to hold it.
  submitQueued(menuSeed);
}

// --- menu --------------------------------------------------------------------
function toMenu() {
  endWatching();
  game.stop();
  game.load(menuSeed, menuMode);
  buildModeList();
  buildAccountBar();
  buildCarList();
  buildTrackList();
  showRoundButton(false);
  showOverlay('menu');
}

// Input: one button. Pointer events cover mouse, touch and pen.
function pressDown(e) {
  if (game.isReplay) return;
  if (game.state === 'dead' || game.state === 'finished') return;
  if (!game.running) game.run();
  if (game.state === 'ready') startRun(game.seed);
  if (!e.target.closest('button')) game.setHeld(true);
}
function pressUp() { game.setHeld(false); }

canvas.addEventListener('pointerdown', (e) => { e.preventDefault(); pressDown(e); });
window.addEventListener('pointerup', pressUp);
window.addEventListener('pointercancel', pressUp);
window.addEventListener('keydown', (e) => {
  if (e.code === 'Space' || e.code === 'ArrowUp') { e.preventDefault(); pressDown(e); }
});
window.addEventListener('keyup', (e) => {
  if (e.code === 'Space' || e.code === 'ArrowUp') pressUp();
});

$('btn-play').addEventListener('click', () => startRun(menuSeed));
$('btn-board').addEventListener('click', () => showLeaderboard(menuSeed));
$('btn-history').addEventListener('click', showHistory);
$('btn-history-close').addEventListener('click', () => showOverlay('menu'));
$('btn-board-close').addEventListener('click', () => { showOverlay('menu'); });
$('btn-again').addEventListener('click', () => startRun(game.seed));
$('btn-menu2').addEventListener('click', toMenu);
$('btn-finish-again').addEventListener('click', () => startRun(game.seed));
$('btn-finish-menu').addEventListener('click', toMenu);
$('btn-finish-board').addEventListener('click', () => showLeaderboard(game.seed));
$('btn-finish-wr').addEventListener('click', () => {
  const wr = worldRecord(game.seed);
  if (wr) watchGhost(game.seed, wr.ghostId, wr.name, wr.time);
});
$('btn-watch').addEventListener('click', () => watchOwnReplay(game.seed));
$('btn-restart-round').addEventListener('click', (e) => { e.stopPropagation(); startRun(game.seed); });
$('btn-replay-again').addEventListener('click', () => {
  if (!watching) return;
  if (watching.kind === 'self') watchOwnReplay(watching.seed);
  else watchGhost(watching.seed, watching.ghostId, watching.name, watching.time);
});
$('btn-replay-board').addEventListener('click', () => showLeaderboard(game.seed));
$('btn-replay-menu').addEventListener('click', toMenu);
$('btn-watch-exit').addEventListener('click', toMenu);
$('btn-watch-close').addEventListener('click', hideWatchBadge);
$('btn-pause').addEventListener('click', () => {
  if (game.state === 'running') { game.state = 'paused'; showOverlay('over-pause'); showRoundButton(false); }
});
$('btn-resume').addEventListener('click', () => {
  hideOverlays(); game.state = 'running'; showRoundButton(!game.isReplay);
});
$('btn-restart').addEventListener('click', () => startRun(game.seed));
$('btn-menu').addEventListener('click', toMenu);

// Leaderboard pager.
$('lb-prev').addEventListener('click', () => { boardPageNo--; renderBoard(); });
$('lb-next').addEventListener('click', () => { boardPageNo++; renderBoard(); });
$('lb-page').addEventListener('change', () => {
  const n = parseInt($('lb-page').value, 10);
  boardPageNo = Number.isFinite(n) ? n : 1;
  renderBoard();
});
$('lb-wr').addEventListener('click', () => {
  const el = $('lb-wr');
  watchGhost(boardSeed, Number(el.dataset.ghostId), el.dataset.name, Number(el.dataset.time));
});

// Accounts.
$('acct-submit').addEventListener('click', submitAccount);
$('acct-toggle').addEventListener('click', () => openAccount(acctMode === 'register' ? 'login' : 'register'));
$('acct-close').addEventListener('click', () => showOverlay('menu'));
$('acct-pass').addEventListener('keydown', (e) => { if (e.key === 'Enter') submitAccount(); });
$('acct-email').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('acct-pass').focus(); });
$('acct-user').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('acct-email').focus(); });

for (const b of document.querySelectorAll('#ghost-list .mode')) {
  b.addEventListener('click', () => {
    ghostMode = b.dataset.ghost;
    setPref('ghostMode', ghostMode);
    buildGhostList();
  });
}

for (const b of document.querySelectorAll('#mode-list .mode')) {
  b.addEventListener('click', () => {
    menuMode = b.dataset.mode;
    localStorage.setItem('slingdrift.mode', menuMode);
    buildModeList();
    buildTrackList();
  });
}

window.addEventListener('resize', () => game.renderer.resize());

buildModeList();
buildGhostList();
buildAccountBar();
buildCarList();
buildTrackList();
showOverlay('menu');
game.run();

// Android back button: close the topmost overlay, else let the shell exit.
window.SlingDriftBack = () => {
  if (game.state === 'running' || game.state === 'paused') {
    game.state = 'paused';
    showOverlay('over-pause');
    showRoundButton(false);
    return true;
  }
  if (game.state === 'dead' || game.state === 'finished') { toMenu(); return true; }
  return false;
};

// Offline shell. Registration is best-effort: the game runs fine without it.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  });
}

window.__slingdrift = {
  game, TRACKS, bestDistance, startRun, showLeaderboard, watchOwnReplay, watchGhost,
  worldRecord, boardPage, playerRank, CAR_COLOURS, showRoundButton,
  openAccount, submitAccount, get acctMode() { return acctMode; },
  showHistory, renderHistory, allRuns, getRuns, applyGhost,
  get ghostMode() { return ghostMode; },
  enqueue, flush, fetchBoard, clientId, queueLength,
};
