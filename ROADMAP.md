# Sling Drift — forward roadmap

A working plan to take the project from "feature-complete port" to "a game people
can find, learn, keep playing, and trust". It is written against the repository as
it stands on `main` (commit `9a6a918`), not against an imagined rewrite.

The order matters more than the list. The first phase exists because the project
currently has **no automated verification in CI** and ships to players on every
push; adding features before fixing that is how a good codebase loses a weekend.

---

## 1. How to read this

- **IDs** (`P0-1`, `B3`, …) are stable; refer to them in issues and commits.
- **Effort**: S ≤ 2 days, M 3–5 days, L 1–2 weeks, XL > 2 weeks (one engineer).
- **Every item has an acceptance test.** "Done" means the test exists and passes,
  not that the screen looked right once.
- **Phases are sequential; workstreams inside a phase are parallel.**
- **Nothing in Phase 1+ starts until Phase 0's gates are green.** That is the
  whole point of Phase 0.

---

## 2. Where the project is today

### What is genuinely strong

- **The core loop is done and proven.** `physics/` + `godot/scripts/car.gd` are
  the same game, `tools/parity.gd` pins the port to frozen JS numbers, and
  `tools/test.mjs` currently reports **349 passing assertions**.
- **The leaderboard's integrity model is right.** A client sends button steps,
  never a time; the `run` Edge Function replays them (`replayRun`) and stores the
  tick count. RLS makes the service role the only writer.
- **Determinism is treated as a product feature.** Fixed 1/120s tick, seeded
  track geometry, endless difficulty as a pure function of road position.
- **The UI is a real app shell**, not a card floating over the road, and it has
  unusually specific layout tests (`verify_ui`, `verify_editor`, `verify_keys`).
- **Offline-first upload queue** and per-account local storage already exist.

### What is missing or fragile (evidence, not vibes)

| Area | Finding | Evidence |
|---|---|---|
| CI | No workflow runs the tests. Only deploy workflows exist. | `.github/workflows/` has `build-godot-android.yml`, `deploy-godot-web.yml`, `deploy-functions.yml`; no `verify.yml`. |
| Local dev | Godot is not installed in this environment; the verifiers cannot run here. | `which godot` → not found. |
| Release truth | The game reports `v1.6`, the Android preset says `1.3` / code `3`. | `godot/scripts/app.gd:5`, `godot/export_presets.cfg:34-35`. |
| Docs | `godot/README.md` still says endless leaderboards "should be added soon" and the track list lives behind a "Tracks button"; both are false. | `godot/README.md` vs `AGENTS.md` "The menu is a tabbed app shell". |
| Security | **Any authenticated user can overwrite `tracker_config.webhook_url` and the message templates.** The old client-side `0404` gate is gone, but the RLS policy still trusts any signed-in user. | `supabase/migrations/0002_tracker.sql`: `tracker_write ... for update to authenticated using (true) with check (true)`. |
| Board integrity | Endless scores are client-reported distances, not replayed. A modified client can post any number under the cap. | `supabase/functions/run/index.ts` endless branch; `AGENTS.md` acknowledges it. |
| Game feel | **Closed in Phase 1.** Audio, haptics, a first-run tutorial, PB/WR deltas, a progress bar, a real settings screen and focus pause now ship. | `godot/scripts/audio.gd`, `haptics.gd`, `app.gd` HUD/settings/tutorial; `verify_audio.gd`, `verify_hud.gd`. |
| Retention | No medals, daily challenge, achievements, streaks, or unlocks. A finished track is just a time. | No matching code or UI. |
| Reach | Portrait-only, no PWA/offline install, no localization, no accessibility settings. | `project.godot` orientation `1`; `progressive_web_app/enabled=false`; no `tr()` usage. |
| Durability | Saves are written by truncating the target file in place. A crash mid-write can lose PBs and custom tracks. | `Storage._write` / `Account._write_session` open `WRITE` directly. |
| Architecture | `app.gd` is 2,144 lines and owns every screen; `track_editor.gd` is 999. | `wc -l godot/scripts/app.gd`. |
| Ops | No post-deploy smoke test; the AGENTS file still tells a human to `curl` the board. | `AGENTS.md` "Check the endpoint after deploying". |

### The strategic read

The game's *engine* is ahead of its *product*. The physics and the leaderboard
model are the hard parts and they are done well. What is missing is the layer
that turns a good prototype into a game: guardrails so it cannot regress, sound
and teaching so it feels finished, reasons to come back, and a release path that
is not debug-signed.

---

## 3. North-star principles (do not trade these away)

1. **A client never sends a time.** Extend this to endless if at all possible.
2. **The physics is the contract.** A tuning change is a different game; every
   stored run is a run of the old one. Either freeze the numbers or version them
   (P2-1).
3. **Determinism is a feature.** A seed, a step sequence and a tick count must
   reproduce a run on every device, forever.
4. **Nothing online blocks play.** Uploads are best-effort and queued.
5. **Every change has a headless proof.** If it cannot be asserted without a
   human tapping, add the harness first.
6. **The phone is the primary screen.** Every layout decision is validated at
   420×820 first, then desktop.

---

## 4. Phase 0 — Guardrails and truth (week 1–2)

**Goal:** make it impossible to merge or ship a regression, and make the docs
describe the game that actually exists.

### A1. CI verification workflow — M — [x]

Add `.github/workflows/verify.yml` triggered on `pull_request` and `push` to
`main`, with jobs:

1. `physics`: `node tools/test.mjs` and `node tools/sync-physics.mjs --check`.
2. `godot`: install Godot 4.5.2 + export templates (reuse the exact block from
   `deploy-godot-web.yml`), `--import`, then run every verifier:
   `parity`, `verify_tracks`, `verify_reattach`, `verify_endless`,
   `verify_board`, `verify_online`, `verify_guard`, `verify_editor`,
   `verify_ui`, `verify_cars`, `verify_keys`.
3. `export`: build Web and Android debug (no deploy) so an export break is caught
   on a PR, not on `main`.
4. `lint`: `godot --headless --check-only` on every script, plus a docs/version
   consistency check (A3).

**Acceptance:** a deliberately broken `car.gd` (e.g. change `SPEED` by 1) fails
the `godot` job; a stale `_shared/physics` copy fails `physics`; a broken export
preset fails `export`.

**Shipped:** `.github/workflows/verify.yml` runs `node tools/test.mjs`,
`node tools/sync-physics.mjs --check`, `node tools/version.mjs --check`, the
tracker SQL test, and all fourteen Godot verifiers on `push` to `main`, every
pull request, and manual dispatch. It downloads Godot 4.5.2, imports the
project, and runs each verifier in its own log group.

The deploy gate is done: `verify.yml` is callable (`workflow_call`), and all
three deploy workflows call it and set `deploy: needs: verify`, so `main` cannot
deploy red. A `web-export` job now builds the Web preset (and asserts
`index.html`, `index.pck` and `index.wasm` exist) on every verify run, so an
export break is caught before the merge. The Android export is still exercised by
its build workflow rather than on the PR, because it needs the SDK and a
keystore.

### A2. One source of version truth — S — [x]

Create `tools/version.mjs` (or `tools/version.sh`) that reads the version from
one place and:

- writes `godot/export_presets.cfg` `version/name` and increments `version/code`,
- writes `App.VERSION`,
- fails `--check` if they disagree.

Today `app.gd` says `1.6` and the APK says `1.3`. Decide the next version (1.7),
set it once, and make CI enforce it. Add a `VERSION` file if that is cleaner than
parsing GDScript.

**Acceptance:** `node tools/version.mjs --check` is green on `main`; changing
only one of the three fails.

**Shipped:** `VERSION` at the repo root is the source. `node tools/version.mjs`
prints where it is used, `--check` fails on any disagreement (the `physics` CI
job runs it), and `--set 1.8` writes both copies and increments `version/code`.
The build is `1.7` (version/code `4`).


### A3. Docs truth pass — S — [x]

Fix the known drift:

- `godot/README.md`: endless board is shipped (remove "should be added soon");
  the "Tracks button" section is obsolete (Play tab grid); track counts and
  verifier list.
- `AGENTS.md`: line-number references that no longer match; "players x 25" in
  `0001_init.sql` is now 13 tracks; add the version rule.
- `README.md`: point at this roadmap and the verify command.
- Add a `docs-check` grep in CI for phrases that are known to be stale, or a
  short "docs drift" checklist in the PR template.

**Acceptance:** a new contributor reading `godot/README.md` can run the game and
every verifier without being told something false.

**Shipped:** `godot/README.md` no longer describes the old Tracks button, says the
endless board is shipped (with the separate-table design), describes the editor
as a palette and a map rather than Build/Look/Help pages, lists `verify_audio`,
`verify_hud` and `verify_storage`, and has a current layout table. `README.md`
gains a Verifying section, the Makefile and links to `ROADMAP.md` and
`PHYSICS.md`. `AGENTS.md` carries the one-source version rule, the current
commands and the shot flags. `tools/docs-check.mjs` (run in CI) fails on known
stale phrases, a verifier that exists but is not in CI or `godot/README.md`, and
a layout-table path that does not exist.

### A4. Local one-command verification — S — [x]

Add `tools/dev-setup.sh` (install Godot 4.5.2 + templates into `~/.local/bin`
and the template dir) and a `Makefile` (or `justfile`) with:

```
make test      # node physics tests + sync check
make verify    # all Godot verifiers
make check     # test + verify + version + docs
make web       # export web
make apk       # export android
```

**Acceptance:** a clean checkout on Linux can go from clone to green `make check`
with two commands.

**Shipped:** `tools/dev-setup.sh` installs Godot 4.5.2 and the export templates
(Linux x86_64, idempotent), and the `Makefile` provides `setup`, `test`, `verify`,
`check`, `web`, `apk` and `clean`. `make check` runs the JS physics tests, the
vendored-copy check, the version check, the docs check and all fourteen Godot
verifiers. The tracker SQL test needs a database, so it stays in CI.

### A5. Fix the tracker RLS hole — S — [x]

Add `supabase/migrations/0006_admin.sql`:

- an `admins` table (or `profiles.is_admin boolean not null default false`),
  populated by the service role only;
- replace `tracker_write` with a policy that requires
  `exists (select 1 from public.admins a where a.user_id = auth.uid())`;
- keep `webhook_url` unreadable by clients;
- revoke the `update` grant on `tracker_config` from `authenticated` and grant it
  only to `service_role`, with a security-definer `set_tracker_config` function
  if an admin UI is still wanted.

**Acceptance:** a pgTAP/SQL test signs in as a normal user and asserts the update
is refused (42501); the service role can still set it.

**Shipped:** `0006_admin.sql` adds `public.admins` (RLS on, no policies, no client
grants), drops `tracker_write`, and revokes both the table-level and the
column-level `update` grants from `authenticated`. An admin sets the tracker
through the security-definer `set_tracker_config`, which checks the admin row
itself. `supabase/tests/tracker_rls.sql` applies the real migrations on a
throwaway database and asserts a normal player's update and RPC are refused
(42501), the templates stay readable, the webhook stays unreadable, an admin's
write lands, and the service role can still write directly. The `sql` CI job runs
it on a `postgres:17` service.

### A6. Physics-change protocol, written down — S — [x]

Add a short `PHYSICS.md` (or a section of `AGENTS.md`) that says: any change to
`cfg.gd`, `car.gd`, `physics/config.js`, `physics/car.js`, `track.gd` or
`tracks.js` requires (a) both test suites, (b) a re-simulation of at least three
real board rows per affected track, recorded in the PR, and (c) a decision on
whether the change is a new physics version (P2-1).

**Acceptance:** the template exists; the next physics PR follows it.

**Shipped:** `PHYSICS.md` states what counts as a physics change, the five-step
checklist (both sides, both suites, three real rows, a version decision, no
tuning to a row), and why the goldens cannot catch every tunable.
`tools/replay-row.mjs` replays a stored row and fails on a tick mismatch, so
step 3 is one command. `.github/pull_request_template.md` carries the checklist
and the row table.

### A7. Post-deploy smoke tests — S — [x]

Extend `deploy-godot-web.yml` and `deploy-functions.yml` with a final job:

- `GET /` → 200 and contains the game title;
- `GET /index.wasm` → 200, body starts with `\0asm` (this catches the gzip
  double-encoding trap);
- `GET /android` → 302 to the release;
- `GET functions/v1/board?track=1` → 200 JSON with a `rows` array (catches the
  `steps`-on-the-view 500);
- `GET functions/v1/board?track=1&mode=endless` → 200.

**Acceptance:** a deliberately broken worker or board function fails the deploy
job after it ships, and the job is red.

**Shipped:** `tools/smoke.mjs` does both halves: `web` checks `/` is 200 and
names the game, `/index.wasm` is 200 `application/wasm` and starts with
`00 61 73 6d`, and `/android` 302s to the release; `board` checks both board
modes return 200 with a `rows` array. Each deploy workflow has a `smoke` job that
`needs:` its deploy. The Android build also smoke-checks that the rolling release
still has a non-trivial APK. The web and board checks pass against the live site
today.

### A8. Quick wins found during the audit — S each

- Fix the `0001_init.sql` comment that says `(players x 25)`. **[x]** It now
  says "players x playable tracks", so it cannot go stale again.
- Remove or archive `supabase/functions/_shared/physics/physics.js` if it is not
  imported by anything (it re-exports `verify.js`; keep it only if a function
  needs the barrel). **[x]** Nothing imported it, and it was not one of the five
  synced files, so it could drift; removed.
- Make `Storage` and `Account` writes atomic (write `*.tmp`, then rename) — this
  is small and belongs in Phase 0 because it protects every later feature.
  **[x] shipped:** both write a sibling `.tmp` and rename it over the target;
  `verify_storage.gd` proves a second write replaces the first, a stale temp is
  ignored, and no temp file is left behind.
- Add a `LICENSE` decision (currently only car art is credited). If the repo is
  public, say what others may do. **[x]** MIT for the code (`LICENSE`), with the
  bundled art and audio staying CC0 and credited; the README says so.

**Phase 0 exit gate:** `make check` green locally; CI green on a PR and on
`main`; deploy blocked on red; no known false statement in the top-level docs.

---

## 5. Phase 1 — Make it feel like a game (week 3–5) — SHIPPED

**Goal:** a first-time player understands the mechanic, hears what is happening,
and can put the phone down without losing the run.

**Status:** shipped on `main`. The implementation is in `godot/scripts/audio.gd`,
`haptics.gd`, the HUD/settings/tutorial additions in `app.gd`, and the new
`verify_audio.gd` / `verify_hud.gd` verifiers. The notes below keep the original
acceptance criteria and record what actually shipped.

### B1. Audio system — L — [x]

Create `godot/scripts/audio.gd` (`Audio`, an autoload or a child of `App`) with
an `AudioServer` bus layout (`Music`, `SFX`), pooled `AudioStreamPlayer`s, and
these cues:

- engine loop whose pitch/volume follows `car.speed_scale` and whether the car
  is drifting or flying;
- tyre scrape while `car.grabbed`, with intensity from radius change;
- release whoosh, grab click, reattach slingshot;
- crash, finish, new-best jingle;
- UI tap/back;
- optional music loop (CC0).

Rules: every cue has a volume pref; the web build unlocks audio on the first
pointer event (browser autoplay policy); `AudioServer.set_bus_mute` follows a
mute pref; no audio node is created before the tree is up (same trap as `Net`).
Use CC0 assets and add them to `godot/assets/audio/CREDITS.md`.

**Acceptance:** `verify_audio.gd` asserts every cue has a stream, every bus
exists, the volume pref clamps to 0..1, and a muted bus is silent. Manual check
on web + Android.

**Shipped:** `GameAudio` owns a 10-player one-shot pool, engine/tyre loops and a
music channel, with `Music`/`SFX` buses and a limiter on Master. The cue set is
engine, tyre, grab, release, slingshot, crash, finish, PB, UI click/back, menu
music and race music. Every file is CC0 and listed in
`godot/assets/audio/CREDITS.md`. `verify_audio.gd` proves every stream loads,
every loop is marked to loop, the credits name every file, the mixer mutes and
unmutes, and the volume round-trips. The web build gets its first gesture from
the UI tap, which is also what resumes the browser audio context.

### B2. Haptics — S — [x]

`Input.vibrate_handheld(ms)` on grab, release, crash, and PB, behind a pref and
`DisplayServer.is_touchscreen_available()`. Never on web.

**Acceptance:** `verify_haptics.gd` asserts the pref gates every call (use a
test seam that records calls instead of vibrating).

**Shipped:** `godot/scripts/haptics.gd` is a separate `RefCounted` with a static
`fire(kind)` and a `log_only` test seam. It is gated by the `haptics` pref, by
`OS.has_feature("web")` and by `DisplayServer.is_touchscreen_available()`. The
patterns are grab 12ms, release 8ms, slingshot 20+26ms, crash 180ms, finish
60ms, PB 40+35ms. The call recording lives in `verify_audio.gd` (the audio and
haptics layer is tested together).

### B3. First-run tutorial — M — [x]

A first-run overlay that teaches the whole loop in one card:

1. **Hold** — the car latches at its current distance and reels in.
2. **Release** — it leaves on the tangent as the arc ends.
3. **Fly straight** — a small nudge steers home, but a clean line is fastest.
4. **Find the rhythm** — speedrun is timed; endless ramps.

"Try it now" drops straight into a run; "Back to menu" returns. The tutorial is
shown once, stored as the `tutorialDone` pref (device-level, not per account),
and can be reopened from Settings. It is skipped in headless runs so the
screenshot and UI checks still see the menu.

**Acceptance:** `verify_ui.gd` opens the tutorial at phone and desktop sizes and
checks the card fits; `verify_hud.gd` opens it, takes the back path, takes the
start path and asserts the pref and the run start.

**Shipped:** the overlay is `_build_tutorial` in `app.gd`, with a four-row
`_tutorial_step` layout and `_tutorial_start` / `_tutorial_back` actions. The
first-run gate is `tutorial_done` plus a headless guard.

### B4. In-run feedback and juice — M — [x]

- A live delta to your PB during a run (green/red), and a finish card that says
  `-0.043s PB` or `+0.120s`.
- A live WR delta next to the PB delta, plus a speedrun progress bar.
- A short screen flash and camera shake on a crash, a softer flash on a finish,
  and a subtle zoom pulse on a slingshot.
- Reduced-motion pref disables shake, flash and pulses.
- Deferred to Phase 2: a 3-2-1 countdown / GO flash, and speed lines that follow
  `speed_scale`. They are polish, not a correctness gap.

**Acceptance:** `verify_hud.gd` asserts the delta math and colours, the progress
bar, that a crash reaches the renderer, that a slingshot pulses the zoom, and
that reduced motion suppresses shake. The run clock is untouched because these
are renderer-only effects.

### B5. Pause on focus loss and Android back — S — [x]

Handle `NOTIFICATION_APPLICATION_FOCUS_OUT` (and `NOTIFICATION_WM_CLOSE_REQUEST`
where relevant) by pausing a live run, not a replay. Android back opens the
pause card first, then the menu. Never let a backgrounded run keep ticking into
a wall.

**Acceptance:** `verify_pause.gd` simulates focus-out during a run and asserts
`state == "paused"` and the clock stops; a second back press returns to the menu.

**Shipped:** `App._notification` handles `NOTIFICATION_APPLICATION_FOCUS_OUT`
and `NOTIFICATION_APPLICATION_PAUSED` by pausing a live, non-replay run.
`_on_back_request` walks up one level: close dialog, leave editor, resume pause,
leave a card, then leave the app. `verify_hud.gd` drives focus-out on a run, a
replay, and the pause resume. `NOTIFICATION_WM_CLOSE_REQUEST` is intentionally
left to the OS: closing a desktop window is a deliberate quit, not a tab-out.

### B6. Settings that a player expects — M — [x]

Extend the Settings modal with:

- master / music / SFX volume sliders (persisted);
- haptics toggle;
- reduced motion toggle;
- ghost on/off (already on Play, keep one source of truth);
- "Replay tutorial";
- "Export my data" / "Reset local data" (see E5).

Keep every row inside the card; `verify_ui.gd` already measures overflow.

**Acceptance:** `verify_ui.gd` opens Settings at phone and desktop sizes, moves
each slider, and asserts every control is inside the viewport.

**Shipped:** master / music / effects sliders, haptics toggle, reduce-motion
toggle, the three rebindable keys, a "How to play" entry and the version line.
`verify_ui.gd` opens Settings at 420x820 and 1024x768 and checks every key row is
in view; `verify_hud.gd` moves the master slider, checks it reaches `GameAudio`
and `Storage`, and drives both toggles. The ghost picker stays on the Play tab
as the single source of truth. "Export my data" / "Reset local data" are
deferred to the save-durability work (E3/E5); they need a confirm flow and a
backup format, not a button that deletes a PB.

### B7. HUD clarity — S — [x]

Show the mode and track name in-run, the corner count in endless, the current
speed multiplier when it is not 1.0, and the PB delta. Keep the HUD out of the
thumb zone.

**Acceptance:** `verify_ui.gd` asserts the HUD labels exist and fit at both
sizes.

**Shipped:** the HUD names the mode and track (`SPEEDRUN · TRACK 3`, `ENDLESS`,
`CUSTOM · SPEEDRUN`, `REPLAY`), shows the best, the current corner count, the
speed multiplier when it is not 1.0, a PB delta, a WR delta, and a speedrun
progress bar. `verify_hud.gd` covers the delta text and colours, the progress
bar, the mode text and the endless metres. The HUD stays at the top of the
screen, out of the thumb zone.

**Phase 1 exit gate:** a new player can be taught, can hear the game, can pause
and resume, and the settings persist across a restart. **Met.**

**Follow-ups found during Phase 1 (not blockers):**

- The headless verifiers are not yet in CI (Phase 0 A1). This is the next task.
- The tutorial is a card, not an interactive three-step lesson on a track. The
  card teaches the loop; an interactive lesson is a Phase 2 onboarding upgrade.
- Countdown / GO flash and speed lines are deferred; the run still has audio,
  haptics, crash shake/flash, slingshot pulse and reduced motion.
- Export / reset local data are deferred with E3/E5.

---

## 6. Phase 2 — Competition, retention and board integrity (week 6–10)

**Goal:** give players a reason to come back, and close the two integrity gaps
(endless trust, unversioned physics) before the board grows.

### C1. Physics versioning — L (do this before any tuning or new tracks)

The board's contract says a stored run is a run of the physics that produced it.
Today there is exactly one physics. The first tuning change silently makes every
old row unverifiable.

Do one of:

- **Freeze** the physics and never change it (simplest, but blocks feel work), or
- **Version** it: compute `physics_version` from a hash of `config.js`, `car.js`,
  `track.js`, `tracks.js`; store it on `runs`; keep `_shared/physics/v1/` etc.
  and verify an upload with the version it claims (reject unknown versions).

Recommended: version it. Add `physics_version int not null` to `runs` and
`endless_runs`, and have `run` write the current version. Add
`tools/resim-board.mjs` that pulls a board page and re-simulates every row with
the matching physics, reporting mismatches.

**Acceptance:** `tools/resim-board.mjs --track 28 --limit 10` reproduces every
stored row; changing `CFG` without bumping the version fails CI.

### C2. Verified endless — XL (the big one)

The endless board is currently a client-reported distance. That is acceptable
only while the mode is casual; it is the one place the project's own integrity
rule is relaxed.

Port the endless ramp into `physics/` (or a new `physics/endless.js`) so the
server can replay an endless run:

- endless track construction is already a pure function of road position; the JS
  `Track` needs `currentRadius` / `currentSegLen` / `extendAhead`;
- the car already has `speed_scale` for the reattach boost; add the endless
  speed ramp;
- store `steps`, `ticks` and derived `metres` on `endless_runs`; verify on
  upload; make rows watchable.

Fallback if the port is too large for one phase: keep the client score but add
server-side plausibility bounds (max metres/second, minimum ticks per metre) and
a "reported, not verified" label on the board. Do not pretend it is verified.

**Acceptance:** an endless run round-trips through the server verifier; a forged
distance is rejected; a board row can be watched; `tools/test.mjs` covers the
same claims on the JS side and `verify_endless.gd` on the Godot side.

### C3. Medals and per-track goals — M

Derive gold/silver/bronze targets deterministically from each track's
`targetTime` (e.g. gold = target, silver = +3%, bronze = +8%), show the medal on
the track chip and the finish card, and add a "Medals" summary on the Play tab.

**Acceptance:** `verify_board.gd` (or a new `verify_medals.gd`) asserts the
thresholds are ordered, deterministic, and that a real clean line earns gold on
every shipped track.

### C4. Daily challenge — L

A date-derived challenge: one track, one optional modifier (mirror, reverse, no
reattach, tight corners), the same for everyone that day. Start local-only:
`daily.v1.json` stores the date, track, modifier, attempts and best. Then add a
`daily_runs` table and a board if it proves popular.

Use the existing `CustomTracks.mirror` / `reverse` transforms for modifiers so
the geometry stays in the proven op-list system.

**Acceptance:** the same date yields the same challenge on two devices;
yesterday's result is not overwritten; a custom modifier still finishes on every
track (`verify_tracks` extended).

### C5. Custom-track sharing — M

Add a versioned share code: `base64url(zlib(json({v, name, ops, theme})))` with a
checksum. Editor gets **Share** (copy to clipboard) and **Import code**. Import
runs the same `CustomTracks.validate` as local authoring and refuses a code that
folds, exceeds the piece cap, or carries an unknown version. No server needed.

**Acceptance:** `verify_editor.gd` round-trips a track through encode/decode,
rejects truncated and malicious codes, and asserts an imported track drives and
finishes.

### C6. Ghosts and board UX — M

- Race any board row's ghost, not only your own (`_watch_steps` already exists;
  add a "Ghost this run" toggle on the board row).
- Show a live delta against the ghost.
- Board: highlight your row, show the date, and add a "Copy replay code" action
  (steps are already in the row).
- Play tab: show the top 3 and your rank without opening the board.

**Acceptance:** `verify_board.gd` asserts the ghost selection and the merged
rank; `verify_ui.gd` asserts the row actions fit the card.

### C7. Local achievements — M

A small, offline set: first finish, sub-10s, gold on 5 tracks, 1,000 m endless,
first custom track, 100 corners in one endless run. Store in
`achievements.v1.json`; show a grid on the Account tab; toast on unlock. No
server.

**Acceptance:** `verify_achievements.gd` drives each condition and asserts the
unlock is idempotent and persists.

### C8. Guest → account migration — M

Today guest PBs stay in the `guest` bucket forever (AGENTS.md says so
explicitly). On sign-in, offer "Bring my guest times with you?" and merge the
guest records/times/replays/history/custom tracks into the account, then archive
the guest bucket so a second sign-in cannot double-merge.

**Acceptance:** `verify_online.gd` signs in with a seeded guest bucket, merges,
asserts the account sees the PB, and asserts a second merge is a no-op.

**Phase 2 exit gate:** the board can be trusted for both modes, a returning
player has goals, and custom tracks can travel between devices without a server.

---

## 7. Phase 3 — Platform and reach (week 11–15)

**Goal:** ship like a real app, on more than one kind of device, in more than one
language.

### D1. Android release pipeline — L

- Generate a release keystore; store it and its passwords in repository secrets
  (never in the repo).
- Add a `Release` export preset producing an `.aab` with a monotonically
  increasing `version/code`.
- Add `.github/workflows/release-android.yml` on a tag: build, sign, upload to a
  Play internal-testing track (or a GitHub release until Play is set up).
- Add a privacy policy page and a store listing (screenshots from `--shot`).
- Keep the debug `android-latest` build for quick testing.

**Acceptance:** a tagged build installs from Play internal testing; the version
shown in Settings matches the store listing.

### D2. PWA and offline web — M

Turn on `progressive_web_app` in the Web preset, add a manifest and icons, and
cache the export so a returning player can play offline. Handle the gzipped wasm
path carefully (`worker.js` must not be bypassed) and add an update prompt when a
new `pck` is available.

**Acceptance:** Lighthouse PWA installable; a second load works with the network
off; a new deploy prompts to reload; `/index.wasm` still serves `\0asm`.

### D3. Localization — L

- Move every user-facing string into `godot/localization/strings.csv` and use
  `tr()`.
- Add a language picker in Settings, persisted.
- Ship at least Spanish, Brazilian Portuguese, French and German; add a CJK font
  if Japanese/Chinese are wanted (the theme font has no glyphs, same trap as the
  icons).
- Add a `verify_i18n.gd` that fails on a missing key or an untranslated string in
  a shipped locale.

**Acceptance:** switching language updates the menu, HUD and finish card without
a restart; no key falls back to a raw identifier.

### D4. Accessibility and input breadth — M

- UI scale (100/115/130%) and a high-contrast / colorblind-safe theme option.
- Reduced motion already exists from B4.
- Gamepad and mouse play (the one-button input already accepts mouse and keys;
  add controller buttons).
- Check contrast on every theme and every selected chip, reusing the existing
  contrast test in `verify_ui.gd`.

**Acceptance:** `verify_ui.gd` runs at 130% scale and fails on overflow; contrast
checks pass for every theme/preset pair.

### D5. Layout breadth — M

Decide whether landscape and tablets are supported. If yes, allow the
orientation and make the shell adapt (the `canvas_items`/`expand` setup already
helps). If no, say so in the docs and keep the portrait lock deliberate.

**Acceptance:** `verify_ui.gd` at 820×1180 (tablet) and 1180×820 (landscape)
either passes or is explicitly skipped with a documented reason.

### D6. Web performance budget — M

Measure first-playable on a cold cache. The wasm is ~36 MiB raw / ~9 MiB gzipped;
try Brotli, check whether the pck and textures can shrink, and set a budget
(e.g. < 12 MiB transferred, < 5 s on a mid-range phone). Add a CI check on export
size.

**Acceptance:** the budget is printed in CI and a regression fails it.

**Phase 3 exit gate:** a player can install the game on Android and web, play it
offline, and read it in their language.

---

## 8. Phase 4 — Engineering health (continuous, start in week 1)

These are not a phase you finish; they are the work that keeps the other phases
from becoming expensive.

### E1. Split `app.gd` — L

Extract screens into `godot/scripts/screens/`:

- `play_screen.gd`, `garage_screen.gd`, `account_screen.gd`, `editor_screen.gd`
- `overlays/board_overlay.gd`, `history_overlay.gd`, `settings_overlay.gd`,
  `finish_overlay.gd`, `dead_overlay.gd`, `pause_overlay.gd`
- `hud.gd`

`App` becomes a coordinator: owns `Game`, `Storage`, the shell, and the signal
wiring. No behaviour change; every verifier stays green. Do this **before** C4,
C5 and B6, which all add screens.

**Acceptance:** `app.gd` under ~500 lines; every existing verifier passes
unchanged; a new screen can be added without touching the others.

### E2. Cross-language physics fuzz — M

`parity.gd` pins one scripted run. Add a generator in Node that produces, say,
200 random step sequences across every playable track, dumps the expected final
state, and a Godot script that replays and compares within float tolerance.
Store the generated cases as a fixture so the test is deterministic.

**Acceptance:** a 1-ulp-in-a-different-place bug or a changed reel step is caught.

### E3. Save-data durability — M

- Atomic writes (`.tmp` + rename) everywhere.
- A schema version per file and a migration/fallback path.
- A `.bak` of the previous good file.
- A corrupted file is reported in Settings and does not crash the game.

**Acceptance:** `verify_storage.gd` truncates/corrupts each file and asserts the
game boots, reports the problem, and keeps the backup.

### E4. Server tests — M

Add Deno tests for the pure parts of `run` and `board`: payload validation,
`replayRun` rejection reasons, the endless bounds, the `steps`-on-the-view query
shape, and CORS. Add a local Supabase + pgTAP job for the RLS policies (A5, C1).

**Acceptance:** `deno test` and `supabase test db` run in CI; a policy regression
fails.

### E5. Account lifecycle — M

- Password reset (Supabase email flow).
- Change display name.
- Delete account (a service-role function that deletes the auth user; cascades
  remove profile/runs).
- Export local data as JSON (settings already has the button from B6).

**Acceptance:** `verify_account.gd` covers the offline state machine; a manual
check covers the email round-trip.

### E6. Observability — M

- A server `/health` endpoint and a post-deploy check (A7).
- Client error reporting to a Supabase `events` table (opt-in, no PII) or a
  hosted error service; a "Report a problem" action that includes the version,
  platform and last 20 log lines.
- Basic counters: runs started, runs finished, uploads queued/failed, board
  latency.

**Acceptance:** a forced error appears in the event table with the version and
platform; the privacy policy says what is collected.

### E7. Dependency and toolchain pinning — S — [x]

- Godot version in one file, used by every workflow.
- Dependabot/Renovate for GitHub Actions.
- Pin the Supabase CLI and Deno versions used in CI.

**Acceptance:** a version bump is one commit and CI proves it.

**Shipped:** `toolchain.json` holds the Godot (editor + templates), Node and
Supabase CLI versions. Every workflow reads it, `setup-node` reads `.nvmrc`, and
`tools/dev-setup.sh` reads the same file. `node tools/toolchain.mjs --check`
(run in CI) fails if a workflow or script hardcodes any of them, sets
`node-version:` directly, or if `.nvmrc` and `toolchain.json` disagree. A bump is
one edit to `toolchain.json` plus `.nvmrc`. Dependabot (`.github/dependabot.yml`)
keeps the GitHub Actions current weekly; the game toolchain is bumped by hand
because a Godot change needs its export templates too.

### E8. Release notes automation — S — [x]

Conventional commits + a `release-notes` job on tag, or the existing
`release-notes` skill run manually. The release body should list gameplay
changes, physics changes (with the re-simulation results), and migration notes.

**Acceptance:** a tag produces a readable release with the version and the
physics version.

**Shipped:** `tools/release-notes.mjs` groups the commits since the previous `v*`
tag (conventional prefixes, with a verb fallback for the older history), prints
the build version from `VERSION` and a fingerprint of the five physics files.
`.github/workflows/release.yml` runs it on a `v*` tag and creates or updates the
GitHub release. The fingerprint becomes a real `physics_version` when C1 lands.

---

## 9. Phase 5 — Content and live operations (ongoing)

### F1. Track pack 29–40 — L

Use the op-list system (`ADVANCED` / `REATTACH` in `physics/tracks.js` and the
mirror in `godot/scripts/tracks.gd`) for new shapes: chicanes, double-apex,
S-bends, reattach chains. Every new track needs:

- one entry in each track table (the playable set is derived, so no server list);
- a clean line that finishes in the target window (`verify_tracks`);
- a reattach proof if it uses reattach pillars (`verify_reattach`);
- a board smoke check (A7);
- a medal threshold (C3).

**Acceptance:** all verifiers green; the new track uploads and appears on the
board without a migration.

### F2. Editor v2 — L

- Test-drive from the editor without leaving it.
- More pieces and a "smart finish" that sizes the closing straight to a target
  time.
- Templates (S-bend, hairpin, loop) and a duplicate/mirror/reverse set.
- Better empty-state guidance and a validation panel that says *where* the road
  fails, not just that it does.

**Acceptance:** `verify_editor.gd` covers each new op, the test-drive path, and
the validation messages.

### F3. Weekly event and cosmetics — M

A weekly seeded challenge (reuse C4) and cosmetic car unlocks tied to medals or
achievements. Cars stay cosmetic only; do not add stats without a physics
version bump.

**Acceptance:** an unlock is earned once, persists, and cannot be equipped before
it is earned.

### F4. Community and moderation — M (only if sharing grows)

If custom tracks become shareable at scale, add a report path, a name filter, and
a server-side validator for shared codes. Until then, keep sharing as a code the
player chooses to send.

---

## 10. Sequencing and critical path

```
Phase 0  A1 CI ── A2 version ── A3 docs ── A4 dev ── A5 RLS ── A7 smoke
              │
              ▼
Phase 1  E1 split app ── B1 audio ── B3 tutorial ── B4 feedback ── B5 pause ── B6 settings
              │
              ▼
Phase 2  C1 physics version ── C2 verified endless ── C3 medals ── C4 daily
                                          │
                                          └── C5 sharing ── C6 ghosts ── C7 achievements ── C8 migration
              │
              ▼
Phase 3  D1 Android release ── D2 PWA ── D3 i18n ── D4 accessibility ── D5 layout ── D6 perf
              │
              ▼
Phase 4  E2 fuzz, E3 storage, E4 server tests, E5 accounts, E6 observability (parallel from week 1)
              │
              ▼
Phase 5  F1 tracks, F2 editor, F3 events, F4 community
```

**Do not reorder these two:**

- **C1 before any physics tuning or new track.** Otherwise every old board row
  becomes unverifiable and the "physics is the contract" rule is broken silently.
- **E1 before C4/C5/B6.** Adding three screens to a 2,144-line file is how the
  next bug hides.

---

## 11. The first ten working days (concrete)

| Day | Work | Output |
|---|---|---|
| 1 | A1 skeleton: `verify.yml` with `physics` job; A4 `Makefile` | `make test` green locally and in CI |
| 2 | A1 `godot` job: install Godot, import, run all verifiers | a broken `car.gd` fails CI |
| 3 | A1 `export` + `lint` jobs; gate deploy workflows | red `main` cannot deploy |
| 4 | A2 version script; bump to 1.7; fix `export_presets.cfg` | `version --check` green |
| 5 | A5 migration + RLS test; A8 atomic writes | normal user cannot edit the tracker |
| 6 | A3 docs truth pass; A6 physics protocol | docs match the game |
| 7 | A7 post-deploy smoke for web + functions | a bad worker/function is caught |
| 8 | B1 audio spike: bus layout, engine loop, crash, UI tap | audible build on web + Android |
| 9 | B1 finish + `verify_audio.gd` | audio covered by a verifier |
| 10 | E1 first split: extract the board + history overlays | `app.gd` smaller, verifiers green |

At the end of day 10 the project should have: a green, enforced CI, an honest
version, a closed security hole, truthful docs, smoke-tested deploys, and the
first piece of game feel.

---

## 12. Metrics that tell you it is working

Baseline most of these are unknown today; instrument before promising numbers.

| Metric | Why | Target after 2 quarters |
|---|---|---|
| CI pass rate on `main` | Guardrails | 100% |
| Time from red to green | Team health | < 1 day |
| Verifier count / coverage | Confidence | every screen and system has one |
| First-run tutorial completion | Teachability | > 80% |
| Runs per player per session | Fun | > 3 |
| D1 / D7 return | Retention | D1 > 30%, D7 > 10% |
| Median speedrun finish rate | Difficulty | 40–60% (not 5%, not 95%) |
| Board rows that re-simulate | Integrity | 100% |
| Crash-free sessions | Quality | > 99% |
| Cold start to playable (web) | Reach | < 5 s on mid-range mobile |
| Upload queue failure rate | Reliability | < 1% |

---

## 13. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A physics change silently invalidates old rows | High | High | C1 versioning + `resim-board.mjs`; freeze otherwise |
| Verified endless is a bigger port than expected | Medium | High | Timebox to 2 weeks; ship bounds + "unverified" label as fallback |
| Audio assets/licenses become a mess | Medium | Medium | CC0 only, `CREDITS.md`, `verify_audio.gd` checks files exist |
| `app.gd` split breaks a screen | Medium | High | No behaviour change, verifiers unchanged, split one screen per PR |
| Android release signing leaks | Low | High | Secrets only, never a keystore in the repo, rotate on suspicion |
| Localization expands the UI past the phone width | High | Medium | `verify_ui` at 130% scale and every language |
| The tracker hole is exploited before A5 | Medium | Medium | Do A5 in week 1; rotate the webhook once fixed |
| PWA caching serves a stale game | Medium | Medium | Versioned cache + update prompt + smoke test |
| Scope grows faster than the plan | High | High | Phase gates; one workstream per PR; cut from Phase 5 first |

---

## 14. Explicit non-goals (for now)

- **3D, a chase camera, or a horizon.** The top-down orthographic view is the
  game; `AGENTS.md` has the reference-frame proof.
- **Client-sent times.** Never, including "just for endless" if C2 lands.
- **A server-side custom-track marketplace.** Sharing codes are enough until
  there is a moderation story.
- **Monetization.** It changes accounts, privacy and the store path; decide it
  deliberately, not as a side effect.
- **A second game mode that needs new physics.** Reattach and endless already
  stretch the one-button contract; more modes should reuse them.
- **A full rewrite.** The physics and verifiers are the asset; refactor around
  them.

---

## 15. Open decisions for the owner

1. **Physics:** freeze the numbers, or version them (C1)? This blocks all feel
   work.
2. **Endless:** is a client-trusted distance acceptable long-term, or is C2
   required before the board is promoted?
3. **Platforms:** Android + web only, or iOS next? iOS changes the export,
   signing and store work in Phase 3.
4. **Admin:** who may edit the tracker config (A5), and is an in-game admin panel
   wanted at all?
5. **Languages:** which four or five, and is CJK required (font work)?
6. **Analytics:** is opt-in telemetry acceptable, and what does the privacy
   policy need to say?
7. **Landscape/tablet:** supported or explicitly out of scope (D5)?

---

## 16. Definition of done, per phase

- **Phase 0:** CI is required and green; deploys are gated and smoke-tested; the
  version is single-sourced; the tracker hole is closed; docs are true.
- **Phase 1:** a new player is taught, hears the game, can pause, and their
  settings survive a restart.
- **Phase 2:** both boards are trustworthy; a returning player has medals and a
  daily reason to play; custom tracks can be shared by code.
- **Phase 3:** the game installs from a store, works offline, reads in the
  player's language, and meets a performance budget.
- **Phase 4:** the app is modular, saves are durable, the server has tests, and a
  production error is visible.
- **Phase 5:** there is a repeatable pipeline for new tracks, editor pieces and
  events without touching the engine.

---

*This document is a plan, not a promise of dates. Re-estimate after Phase 0:
the CI work will tell you how long a green build actually takes, and that number
should recalibrate everything after it.*
