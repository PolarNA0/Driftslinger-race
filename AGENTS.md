# Sling Drift

A one-button car-drifting game (a Sling Drift clone). Hold to sling the car
round a pillar, let go to fly straight to the next one. Leave the road and the
run ends. Two modes: **speedrun** (a finite ~10s track, scored by time) and
**endless** (an infinite road, scored by distance in metres).

## Working on this repo

Commit finished work and **push straight to `main`** - do not ask, do not open a
PR, do not sit on a branch. `origin/main` is the one line of development. If a
push is rejected, pull/rebase and push again rather than opening a PR.

## One build, and one piece of JavaScript

**The Godot build (`godot/`) is the game.** The web build served to players and
the Android app both come from it. New work goes there.

The original JavaScript client (`index.html`, `css/`, `js/`, `sw.js`, the WebView
`android/` shell) has been **removed**. What is left of that era is `physics/`:
the five modules `{config,util,track,car,tracks}.js`, kept for exactly two reasons.

1. **It is the leaderboard's verification engine.** The Supabase Edge Function
   replays every uploaded run through this physics, vendored by
   `tools/sync-physics.mjs` (see "The shared leaderboard runs on Supabase"). The
   rule that a client sends button steps and never a time depends on this. Do not
   delete `physics/` while the online leaderboard exists.
2. **It is the reference the port is verified against.** `godot/tools/parity.gd`
   asserts the Godot physics against numbers this physics produced (frozen as
   golden values), so it is what tells us the Godot physics is right.

It is not a client. `physics/` has no rendering, no game loop, no UI - just the
road, the car and the tunables the server needs to re-simulate a run. The Godot
build is the only client.

## Layout

### Godot build (primary)

- `godot/scripts/cfg.gd` — all tunables (`CFG`), port of `physics/config.js`.
  Start here before changing feel.
- `godot/scripts/track.gd` — the road: a staircase of straight legs joined by
  quarter-turn circular-arc corners, sampled into `road[]` (points) and `rs[]`
  (arc-length per point).
- `godot/scripts/tracks.gd` — the menu tracks: the ten ported time-attack
  tracks (`PLAYABLE_TRACKS`), plus the reattach showcase tracks 26–28. Tracks
  6–20 were removed, so the numbers are not a contiguous range. `PLAYABLE_TRACKS`
  and `MENU_TRACKS` are *derived* from the `ADVANCED`/`REATTACH_TRACKS` tables, so
  a new track is one entry and it joins the menu at once.
- `godot/scripts/car.gd` — the physics. `step(dt, held)` is pure and testable.
- `godot/scripts/game.gd` — fixed 1/120s tick, modes, records, replays.
- `godot/scripts/render.gd` — top-down orthographic view, road themes, the
  car sprites, and the responsive zoom (see "Fitting every screen").
- `godot/scripts/app.gd` — the shell: the tabbed menu, overlays, leaderboard,
  history, accounts, car picker, the track editor and the custom-track picker,
  the round restart button.
- `godot/scripts/customtracks.gd` — `CustomTracks`, the model behind the Editor
  tab: a custom track is an ordered op list (`Track.build_ops` shape), authored,
  stored per account, validated, transformed and resolved to `Track` opts. Ids
  start at `ID_BASE` (1000) so they can never collide with a built-in number.
- `godot/scripts/track_editor.gd` — `TrackEditor`, the full-screen editor
  overlay: a blank grid with the piece palette pinned along the bottom, a sheet
  for the selected piece's controls and the colours, undo and rename. See "The
  track editor (the Editor tab)".
- `godot/scripts/track_preview.gd` — `TrackPreview`, the editor's map: a top-down
  view of the road with a pan/zoom camera (`fit`, `zoom_by`, `pan_by`,
  `focus_index`), a placement grid, two-finger pinch and tap-to-select
  (`pick_at`). Built from a real `Track`, so the plan matches the drive, and
  painted with the track's own colours.
- `godot/scripts/menu_shell.gd` — `MenuShell`, the full-screen menu frame:
  top bar, content sheet, bottom tab bar (see "The menu is a tabbed app
  shell").
- `godot/scripts/theme.gd` — `UiTheme`, the one `Theme` for the whole UI
  (palette, button/toggle variations, panels, scrollbars).
- `godot/scripts/ui_icon.gd` — `UiIcon`, the tab and action icons drawn as
  geometry, because the theme font has no icon glyphs.
- `godot/assets/ui/boot_splash.png` — the boot splash, set in `project.godot`.
- `godot/web/shell.html` — the web export's HTML shell (the custom loader).
- `godot/scripts/{replay,storage,leaderboard,account}.gd` — the ported support
  modules.
- `godot/scripts/{net,netconfig,api}.gd` — the online layer's transport, config
  and leaderboard client (see "The online layer").
- `godot/scenes/main.tscn`, `godot/project.godot` — scene and project settings.
- `godot/tools/` — headless verifiers (`parity.gd`, `verify_tracks.gd`,
  `verify_reattach.gd`, `verify_endless.gd`, `verify_board.gd`, `verify_online.gd`,
  `verify_guard.gd`, `verify_ui.gd`, `verify_editor.gd`, `verify_cars.gd`,
  `verify_keys.gd`). See `godot/README.md`.

### JavaScript (the server's physics)

- `physics/config.js` — all tunables (`CFG`). The single source of the feel; the
  Godot `cfg.gd` mirrors it.
- `physics/track.js` — procedural road: a staircase of straight legs joined by
  quarter-turn circular-arc corners, sampled into `road[]` (points) and `rs[]`
  (arc-length per point). Takes `opts` (`corners`, `radius`, `leadIn`,
  `finishLen`, `segLens`, `targetTime`) so a finite track can have its own shape;
  endless play passes none and gets the uniform `CFG` lengths.
- `physics/tracks.js` — the playable time-attack tracks (1–5 and 21–25; 6–20
  were removed) plus the reattach showcase tracks 26–28. `PLAYABLE_TRACKS` is
  *derived* from the track tables (the staircase base plus the `ADVANCED` and
  `REATTACH` op-list tables), so adding a track is one entry in one table and it
  joins the menu, the server verifier and the upload path at once. `trackDef(n)`
  is a pure
  function of the track number: radius, corner count, lead-in and the straight
  rhythm all come out of `n`, so a track is identical on every device (which the
  leaderboard and replays rely on). `targetTime` makes `Track.buildFinish` size
  the closing straight to land the clock on ~10s.
- `physics/car.js` — the physics. `step(dt, held)` is pure and testable. Carries
  the reattach pillar (a live pillar reopens on an early release; a paying re-catch
  is a slingshot), so the server can verify a run on tracks 26–28.
- `physics/util.js` — `angDiff`, `mulberry32` (bit-exact with the Godot port).
- `tools/test.mjs` — headless tests for the physics and the server's run
  verifier. Must stay green.
- `tools/sync-physics.mjs` — vendors `physics/` into the Edge Function, and
  `--check` fails if the copies drift.

## Commands

```sh
make setup      # once: install the pinned Godot + export templates (Linux x86_64)
make test       # JS physics, vendored copies, version, docs
make verify     # every Godot verifier below
make check      # test + verify
make web        # export the web build
make apk        # export the Android debug APK

# Godot build (the game)
godot --path godot                                        # play
godot --headless --path godot --import                    # first-time import
godot --headless --path godot --script res://tools/parity.gd          # physics vs golden JS numbers
godot --headless --path godot --script res://tools/verify_tracks.gd   # all tracks finish
godot --headless --path godot --script res://tools/verify_reattach.gd # reattach pillar
godot --headless --path godot --script res://tools/verify_endless.gd  # endless ramp + reattach
godot --headless --path godot --script res://tools/verify_board.gd    # board paging
godot --headless --path godot --script res://tools/verify_online.gd   # online layer (offline paths)
godot --headless --path godot --script res://tools/verify_guard.gd    # holding/mashing must lose
godot --headless --path godot --script res://tools/verify_editor.gd   # the track editor's model + roads
godot --headless --path godot --script res://tools/verify_ui.gd       # menu/overlay fit, editor palette + map
godot --headless --path godot --script res://tools/verify_cars.gd     # every car has its own sprite
godot --headless --path godot --script res://tools/verify_keys.gd     # restart/play keybinds
godot --headless --path godot --script res://tools/verify_audio.gd    # audio assets, loop flags, haptics
godot --headless --path godot --script res://tools/verify_hud.gd      # HUD deltas, progress bar, settings
godot --headless --path godot --script res://tools/verify_storage.gd  # atomic saves

# Physics + server verifier (JavaScript, must stay green)
node tools/test.mjs            # headless core tests
node tools/sync-physics.mjs    # vendor physics into the Edge Function
node tools/sync-physics.mjs --check  # fail if the vendored copies are stale
node tools/version.mjs --check       # VERSION vs App.VERSION vs export presets
node tools/docs-check.mjs            # stale docs, unwired verifiers, missing paths
node tools/replay-row.mjs --track N --steps ... --ticks N  # does a stored run still reproduce?
node tools/smoke.mjs web|board       # post-deploy smoke test
```

## The toolchain is pinned in one file

`toolchain.json` is the only place the Godot, Node and Supabase CLI versions
live. The workflows and `tools/dev-setup.sh` read it (Node comes from `.nvmrc`,
which `setup-node` reads directly), and `node tools/toolchain.mjs --check` fails
if any of them hardcodes a version or sets `node-version:` itself. A bump is one
commit. Do not paste a version back into a workflow; a copy that is missed means
CI and a developer build different things.

## Speedrun mode

A finite track with a finish line, scored by time. Built by passing
`{ corners }` to `Track`:

- `CFG.speedrunCorners` (11) sets the corner count and `CFG.speedrunFinish`
  (520px) the closing straight. Each corner costs ~0.70s and the lead-in ~2.48s,
  so 11 corners lands the clock at **~10.4s**.
- `Track.build_finish()` runs a straight on from the last corner's exit and
  records `finish_s`. `car.step` sets `finished` when `s >= finish_s` (checked
  before the wall, so winning on the line is not a crash).
- The clock is the fixed-step count (`Game` advances it only while the car is
  alive), so it is refresh-rate independent. The best time per seed is stored per
  account by `Storage`.
- Endless mode is unchanged: no `corners`, `cornerLimit` is `Infinity`,
  `finishS` is `Infinity`, and nothing about the timer runs.

To retime the track, change `CFG.speedrunCorners` and re-run `tools/test.mjs`:
the speedrun tests assert a clean line finishes in 8–13s, so a bad count fails
loudly.

## Packaging

**The Godot build ships as both the web game and the Android app.** `godot/` has
its own export presets for Web and Android; see `godot/README.md` for the exact
commands and the toolchain the Android export needs.

- **Web.** `.github/workflows/deploy-godot-web.yml` exports the Web preset and
  publishes it to Cloudflare Workers on any push that touches `godot/`, serving
  `https://driftslinger-race.exopolar1.workers.dev/`. It needs the
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repository secrets.
- **Android.** `.github/workflows/build-godot-android.yml` builds a debug-signed
  APK and publishes it to a rolling `android-latest` GitHub release, so
  `releases/download/android-latest/drift-slinger.apk` is always the newest
  build. The web worker redirects `/android` there. It needs no extra secrets
  (it uses the default `GITHUB_TOKEN` with `contents: write`).

**Every deploy is gated on `verify` and smoke-tested after it ships.** The three
deploy workflows call `verify.yml` as a reusable workflow (`workflow_call`) and
their deploy job `needs:` it, so `main` cannot deploy red. After the deploy a
`smoke` job runs `node tools/smoke.mjs`: the web job checks `/` is 200 and names
the game, `/index.wasm` is 200 `application/wasm` and starts with the wasm magic
`00 61 73 6d` (the gzip trap), and `/android` still 302s to the release; the
functions job checks both board modes return 200 with a `rows` array (the
`steps`-on-the-view 500); the Android job checks the rolling release still has a
non-trivial `drift-slinger.apk`. `tools/smoke.mjs web` and
`tools/smoke.mjs board` also run by hand against the live site and project.

### The wasm is served gzipped to fit Cloudflare's 25 MiB asset cap

A static asset on Cloudflare Workers may be at most 25 MiB, and the Godot web
export's `index.wasm` is ~36 MiB, so deploying the export as-is is rejected with
"Asset too large" and the whole deploy fails. The build therefore gzips the wasm
to `index.wasm.gz` (~9 MiB) and deletes the raw file before `wrangler deploy`.

`godot/worker.js` puts the real module back. For `/index.wasm` it fetches
`index.wasm.gz` through the assets binding and streams it through a
`DecompressionStream`, so the browser receives valid wasm at the path Godot asks
for, with `Content-Type: application/wasm`. Every other request is passed
straight to the assets binding.

Two things there are load-bearing:

- **Do not set `Content-Encoding: gzip` on the response.** The stored body is
  already gzip; adding the header encodes it a second time and the browser hands
  Godot a gzip blob it cannot compile. Decompressing in the worker sidesteps the
  header entirely.
- **`run_worker_first` must list `/index.wasm` and `/android`.** Without it the
  asset layer answers those paths first: `/index.wasm` would 404 (only the `.gz`
  exists) and `/android` would fall through to a not-found page.

`wrangler.toml` also carries `main = "worker.js"` and `binding = "ASSETS"`; the
binding is what gives the worker `env.ASSETS.fetch`.

### The old JavaScript app is gone

The legacy JS build, its PWA shell (`sw.js`, `manifest.webmanifest`,
`index.html`, `css/`, `icons/`), the `download.html` landing page, and the
WebView APK (`android/`, `slingdrift.apk`) have all been removed. `godot/` is
the only client. Nothing here needs a rebuild-on-`js/`-change step any more; the
Android app is the Godot export, published to `android-latest` by
`.github/workflows/build-godot-android.yml`.

## The on-screen keyboard (signing in on a phone)

Sign-in needs a keyboard, and on a phone that keyboard is the OS one. Two
different platforms, two different traps:

- **Web build: the export preset must turn it on.**
  `html/experimental_virtual_keyboard` is `false` by default in Godot, and the
  web shell gates the whole thing on it: `library_godot_display.js` returns
  `GodotConfig.virtual_keyboard && 'ontouchstart' in window` from its
  `virtualKeyboard.available()` check. With the flag off there is no text input
  element to focus, so tapping a `LineEdit` on a phone does nothing and the
  account form cannot be filled in. It is `true` in `export_presets.cfg` now. If
  sign-in ever "does nothing" on a phone again, check this first - it is one
  boolean, and desktop is unaffected because those users have a real keyboard,
  which is why the report is "some people".
- **Android build: `screen/immersive_mode` is now `false`, and that is the fix, not
  a preference.** Immersive mode was the last unfixed cause of "the keyboard never
  appears" in the APK. Godot raises the IME from `GodotEditText` with
  `imm.showSoftInput(edit, 0)` - flags `0`, the least reliable form - and while
  immersive is on, `Godot.kt` calls
  `WindowCompat.setDecorFitsSystemWindows(window, !(edgeToEdge || useImmersive))`,
  i.e. `false`, so the window does not resize for the IME and that call silently
  no-ops on many devices. Turning it off costs the status/nav bars and buys a
  keyboard. Do not turn it back on without testing sign-in on a real device.
- **Every `LineEdit` must live in a `ScrollContainer` with `follow_focus = true`.**
  Even with the IME raised, the window shrinks to make room for it and a scroll
  container that does not follow focus leaves the field where it was, underneath the
  keyboard - which players also report as "the keyboard doesn't show up" (upstream
  #87411). There are three such containers (`_new_overlay`, `_new_tab`, the prompt
  dialog) and `verify_ui` walks the tree and fails if any `LineEdit` is outside one
  or the container does not follow focus. That check is what caught the dialog.
- **Web build: the custom shell must not defeat the hidden input.** `web/shell.html`
  is where two WebView traps live, and in-app browsers (Discord, Facebook) are the
  ones that hit them. First, `user-select: none` on `html, body` is inherited by the
  hidden `<input>` Godot injects to raise the keyboard, and a WebView that finds an
  unselectable field may decline to focus it at all - so the shell re-enables
  `user-select`/`touch-action` for `input, textarea`. Godot's own default shell never
  sets `user-select`, which is why this is a custom-shell-only regression. Second,
  Godot only *creates* that input when `'ontouchstart' in window` is true; a WebView
  that reports touch points but omits the hint gets the desktop IME path and raises
  no keyboard, while taps still work (the touch callback is bound unconditionally),
  so the game looks fine and only sign-in fails. The shell restores the hint when
  `navigator.maxTouchPoints > 0`, keyed on that rather than a user-agent so a real
  desktop is never told it has a touchscreen. Upstream Godot issue #117342 is the
  same failure in a browser's Fullscreen API, which this shell never calls; the
  shell does not request fullscreen, so it is not the web path's problem.

`LineEdit` is the right node either way - `Input.virtual_keyboard_show` and
`virtual_keyboard_enabled` only matter for custom `Control`s.

## The one rule that matters

Holding or mashing the button must never trivialise the game. An earlier build
let you clear a lap by spam-holding, and the tests exist so that cannot come
back:

- holding forever crashes within ~2 corners,
- every mash pattern (alternating, 3-on/3-off, 5-on/1-off) dies within ~3,
- a cleanly-timed line survives 120+ corners.

The rule is proved twice, against both physics. `godot/tools/verify_guard.gd`
runs it against the Godot build players actually run; `tools/test.mjs` runs it
against the JS physics the server verifies with. If you touch `car.gd`,
`physics/car.js`, `cfg.gd` or `physics/config.js`, run both.

**Any physics change follows `PHYSICS.md`.** It is short: change both sides, run
both suites, re-simulate at least three real board rows per affected track with
`node tools/replay-row.mjs`, and decide whether the change is the same physics or
a new version. A row that no longer reproduces means it is a different game, and
a board set on the old numbers must not be silently re-ranked.

## Track shape: one corner, one pole, one sling

Every corner is a **quarter turn (90 degrees)** and corners **alternate left and
right**. This is not cosmetic:

- One 90-degree corner has exactly one pole, and the pole spacing (163px with the
  shipped numbers) is far beyond `grabRange` (95px), so only ever one pole is in
  reach. A turn can never read as two slings.
- Alternating directions is what keeps the road from folding. Two 90-degree
  corners the same way would point the road back the way it came and the ribbon
  would cross itself. Alternating keeps each leg perpendicular to the last.
- A 180 would be two poles in one visual turn, so the *staircase* builder never
  emits one. The advanced tracks (21–28) opt out of the staircase and are built
  from an explicit op list, which is what lets a hairpin (180) or a loop (270)
  exist at all; those corners are single arcs round a single pivot, so they still
  read as one pole. See `physics/tracks.js` (`ADVANCED`) and
  `godot/scripts/tracks.gd`.

Because the fillets of a quarter turn are exactly `driftRadius` long, two
neighbouring fillets eat `2*driftRadius` of each `segLen`. `segLen` must clear
`2*driftRadius + minStraight` or `track.js` throws. Straight length trades against
the early-release window: a longer straight is more forgiving of a late release but
is also where a run falls apart, because the car flies its whole length.

A finite track may pass its own `radius` in `opts`, and then the same rule uses
that radius, not `CFG.driftRadius`. A wide corner both needs a longer straight and
eats more of it, so `tracks.js` caps straight lengths (`MAX_VISIBLE_STRAIGHT`):
a long straight is where a run falls apart, because the car flies its whole
length and a small release error accumulates into a wall hit by the far end.

## Grabbing and releasing

- **A grab keeps whatever distance you had.** Holding the button does not snap
  the car onto the swing radius; you can latch from inside or outside the arc and
  the orbit starts where you are. Holding then reels the radius in toward the
  road radius at a fixed rate, so a wide grab slowly tightens. This is why
  holding is not free: reeling in takes time you could have spent turning.
- **Grabbing never moves the car.** `tryGrab` starts the orbit at the distance
  the car already had, so a wide grab does not snap it onto some clamped radius -
  a snap reads as the grapple shoving you toward the wall. The orbit only ever
  reels *in* toward the road radius.
- **Flying steers gently home.** `Car.centre` is a pure-pursuit nudge toward the
  centreline, active only while off it (`CFG.centreDead`). This is what saves a
  late release on the long closing straight: the car curves back instead of
  hitting the wall. It costs time (a curved path is longer), and a centred car is
  left alone, so a perfect line is still the fastest. Tuned to `CFG.centreRate`:
  strong enough to save a ~12-degree late release, weak enough that the clean
  line still wins and a corner cut still loses.
- **A release within one frame of the arc end snaps to the exit point.** The car
  leaves the pole on the tangent at the moment of release, so letting go one
  frame late leaves it up to `speed/radius * FIXED_DT` radians off the road - and
  a straight then turns that sliver into a crash. Snapping only inside a single
  frame keeps the mechanic honest: release much later and you really do swing
  wide into the wall. This is what makes a clean line actually finishable.
- **A reattach pillar stays live until the car is done with its corner.** A
  normal pillar is spent the instant you let go. A pillar whose fillet carries
  `reattach: true` is spent only when you ride the arc to its end (`done()`), or
  when a re-catch pays the slingshot; bail out partway and it stays live, so the
  pole can be caught again - the re-grab unwraps the orbit onto the angle you left
  from (`released_angle`), not the arc start, so your progress round the corner is
  kept instead of reset. A re-catch reaches further than a fresh grab
  (`CFG.REATTACH_GRAB_MULT`), which is what gives the car room to fly a detour and
  still come back - see the slingshot bullet below. The "catchable" state is
  monotonic - a pillar goes live once and spent once - and the renderer reads it as
  `spent_corners.has(k) or k < car.corner`, never a single "last spent" slot,
  which used to flip an earlier pillar back to amber the moment a later one was
  spent. Riding every arc out - the clean line - spends the pillars exactly as
  before, which is why ordinary play is unchanged. Tracks 26-28
  (`Tracks.REATTACH_TRACKS`) showcase it - and endless grows its own past
  `CFG.ENDLESS_REATTACH_AFTER`. The renderer paints a live reattach pillar amber
  and a spent one bronze. `verify_reattach.gd` asserts the monotonic colouring.
- **A reattach pays a slingshot, scaled by the detour.** Bail out of a live
  reattach pillar, fly off, catch the same pole again and carry the arc out, and
  the re-catch lands a burst of speed. The size is set by how far the car actually
  flew between the bail and the re-catch (`Car.detour_px`), from nothing at
  `CFG.REATTACH_MIN_DETOUR` to the full `CFG.REATTACH_BOOST_MAX` at
  `CFG.REATTACH_REF_DETOUR`. A quick release-and-recatch - the spam line - flies
  almost nowhere and earns nothing; a long, committed detour earns the most; a
  detour past the pillar's reach means the re-catch never happens and the run is
  lost. That is the whole mechanic: a real risk/reward curve, not a flat per-pillar
  bonus.
  - **Do not change the boost numbers without re-checking the recorded runs.** The
    curve is linear (`t` straight into `lerp`), and a *front-loaded* curve
    (`t ** 0.6`) was tried and reverted: it makes the detour stronger, which is
    enough to change a real line's trajectory. The board's 9.925 on track 28
    re-simulates to 1191 ticks on this physics and on the server's, but under the
    front-loaded curve those same steps leave the road at 7.68s. The physics is
    part of the leaderboard's contract: a tuning change is a different game, and
    every stored replay is a run of the old one. `tools/parity.gd` and
    `tools/test.mjs` only pin the *shared* numbers - they will not catch a change
    to `REATTACH_BOOST_MAX`/`REATTACH_EFFECT_TIME`, so re-simulate a real board
    row after touching them.
  - **A reattach pillar reaches further than a normal one.** `try_grab` widens the
    range for a re-catch of a live reattach pillar by `CFG.REATTACH_GRAB_MULT`.
    Without it a pole radius (~86px) leaves only a sliver of flight before the car
    is past `grabRange` (95px), so there would be no room to detour at all - the
    old numbers produced a flat ~0.017s for every bail point.
  - **At most one payoff per pillar.** A paying re-catch spends the pillar
    (`spent_corners[corner] = true`), so grinding one pole cannot stack the boost.
    A paying release also stops counting as a reattach, so the plain clean-line
    release that ends every arc stays exactly as it was.
  - The multiplier rides in `Car.speed_scale`, folded into one step's travel by
    `drift` and `fly` (and into the release snap), so the speed change is real but
    short-lived (`CFG.REATTACH_EFFECT_TIME`). It lives in both physics: the Godot
    build (`car.gd`) and the verified JS `physics/` (`car.js`, the `reattach*`
    numbers in `config.js`). The JS port is what lets the server verify a run on
    tracks 26-28, so a change here has to be made on both sides and re-vendored with
    `tools/sync-physics.mjs`. `verify_reattach.gd` proves
    spam earns nothing, a longer detour earns more, over-committing loses the run,
    and the clean line is untouched; `tools/test.mjs` proves the same on the JS
    physics, plus that a reattach run round-trips through the server verifier.

## Endless mode ramps

Endless is one road that gets harder the further you get. Three things rise with
distance, all driven by road position so they stay a pure function of how far the
run has got - which is what keeps a replay reproducible:

- **The car speeds up.** `CFG.ENDLESS_SPEED_MAX` (1.35x) at the top, folded in by
  `Car._speed()` alongside the reattach slingshot.
- **The corners tighten.** `CFG.ENDLESS_RADIUS_MIN` (46px) at the top, via
  `Track.current_radius()`.
- **The straights shorten.** `CFG.ENDLESS_SEG_MIN` (178px) at the top, via
  `Track.current_seg_len()`, so the corners crowd together.

Everything ramps over `CFG.ENDLESS_RAMP_LEN` (9000px) of road. The ramp is
gentle enough that a clean line still survives a long run - `verify_endless.gd`
drives 200 corners on several seeds and `verify_guard.gd` re-proves that holding
and mashing still lose on the ramped road.

**Reattach pillars appear on their own.** Past `CFG.ENDLESS_REATTACH_AFTER`
(2400px), every `CFG.ENDLESS_REATTACH_EVERY`th corner (every 3rd) is a reattach
pillar, so the opening stretch is ordinary play and the pillars read as a change
of pace later. They use exactly the same slingshot as tracks 26-28.

**Only endless ramps.** `Track.endless` is true for a plain `Track.new(seed)` and
false for any track built from `opts` (every speedrun track), so the fixed tracks
are bit-identical to before - the parity goldens are untouched.

**The road is a pure function of distance, not of the line driven.** The
staircase is grown incrementally as the car advances (`extend_ahead`), but each
corner's radius and straight length depend only on the road position at the time
it is added, never on the car's inputs. Two different lines over the same seed
therefore build the same corners, which is what a replay and a ghost need.
`verify_endless.gd` proves this by building the same seed along two different
lines and comparing every fillet.

## Gotchas

- **The view is top-down orthographic, NOT 3D.** Sling Drift is a flat overhead
  game. The reference frames prove it: the road band is the same width at the top
  of the screen as the bottom (449px of 1242 at both y=0.10 and y=0.80 in one
  capture). A perspective camera cannot do that. There is no horizon, no fog and
  no vanishing point. `toScreen` rotates the world so the car's heading points up
  the screen; `ROAD_W_FRAC` (the share of the screen width the road fills, ~0.358)
  sets the zoom. Do not reintroduce a chase camera.
- **The car is rotated by its heading relative to the camera, not by its world
  angle.** `drawCar` rotates by `car.angle - cam.angle`. The camera has already
  rotated the world so the car's heading points up the screen, so using the raw
  world angle (`car.angle + PI/2`) leaves the car visibly slanted whenever it is
  not pointing along `baseHeading`. It looked like a wrong sprite, not a math bug.
- **Rotate the road normal, not just the points.** The band is built by offsetting
  each centreline sample along its normal. That normal is in world space, so it has
  to go through the same camera rotation as the points (`samples()` does this and
  stores `snx`/`sny`). Offset along the raw world normal and the road is skewed and
  the wrong width on any non-axis-aligned stretch - it looked like a broken
  projection rather than a math bug.
- **The Godot road band is triangles, not a filled polygon, and it has to stay
  that way.** `Renderer2D._band` emits an explicit triangle list. It used to build
  one outline (down the +normal edge, back along the -normal edge) and hand it to
  `draw_colored_polygon`. On a road that crosses itself - the hairpin and loop
  tracks 21-25 - that outline is self-intersecting, and Godot's ear-clip
  triangulation refuses it outright with `Invalid polygon data, triangulation
  failed`, dropping the **whole** band for that frame. The road visibly flashes as
  the car crosses its own path, which is exactly the bug reported after the port.
  The JS build never had it because canvas `fill()` uses nonzero winding and fills a
  self-intersecting path happily. Emitting the quads directly skips triangulation,
  so an overlap just overdraws. Do not "simplify" this back to a polygon.
- **Measure the band, do not eyeball it.** The road half-width is
  `CFG.roadHalfWidth` (46px); the drawn band should be a constant
  `2*roadHalfWidth*scale` at every row. `syncSize()` re-reads the canvas rect on
  every draw because the WebView lays the page out after the module runs, so the
  zoom worked out in the constructor is wrong until the first real resize.
- **The Godot menu must fit every screen, and the overlays must scroll.** The
  project viewport is 420x820 with `canvas_items` stretch and `expand` aspect.
  The old menu packed everything into one card that measured 664x851 - wider
  *and* taller than the viewport, so the buttons past the bottom edge could not
  be tapped (players could not reach **Sign in**). The menu is now a full-screen
  shell with a scrolling content sheet (see "The menu is a tabbed app shell"),
  and every modal overlay is a `ScrollContainer` (`_new_overlay`) so a tall card
  scrolls instead of clipping. A row must never be as wide as its content: grid
  and segment buttons set `clip_text` and `SIZE_EXPAND_FILL` so they shrink
  instead of pushing the column past the viewport. `tools/verify_ui.gd` builds
  the real menu at phone and desktop sizes and fails if any control's
  `get_global_rect()` leaves the viewport - run it after any menu change.
- **The editor's live slider callback must not emit `changed`.** `_apply_live`
  repaints the map and the status line; it deliberately does *not* emit
  `changed`. That signal's listener rebuilds the menu's custom-track list - up
  to 100 buttons, each re-validated - and `value_changed` fires on every slider
  step, so emitting there rebuilt the whole list every frame while a length
  slider was dragged. On a phone that read as the editor seizing. Nothing the
  list shows (the name, the corner count) changes during a length drag, so the
  list is refreshed when the drag ends (`HSlider.drag_ended` emits `changed`)
  and on `_commit`. `verify_editor.gd` asserts 10 live slider values cause 0
  list rebuilds.


## The menu is a tabbed app shell

The menu is not a card floating over the road. `godot/scripts/menu_shell.gd`
(`MenuShell`) builds the frame a phone app has - a top bar, a content sheet, and
a bottom tab bar - and fills the whole window at every size. `app.gd` owns the
tab pages and populates them; the shell owns no game state.

- **Four tabs, plus Settings in the top bar.** Garage, Editor, Play, Account
  across the bottom; the gear in the top-right opens Settings as a modal card (it
  holds the key bindings and the build version). The old "Tracks" button is gone -
  the track chooser lives on the Play tab as a grid of numbers, with the selected
  track and its best above it, and the player's own tracks in a "My tracks" picker
  underneath. Editor is a making-things tab, so it sits next to Garage.
- **Endless hides the track chooser.** Endless is one open road, so the whole
  track section (`track_section`) is hidden in that mode rather than shown and
  ignored; `verify_ui.gd` asserts it is gone and unreachable. Speedrun shows it.
- **Three rebindable keys.** Space plays, `R` restarts the run in progress and
  `Esc` pauses and resumes it; all three are rebound in Settings, which captures
  the next key press (`_begin_capture` / `_bind_key`) and refuses a binding that
  would collide with another key. `R` and `Esc` only touch a live run - never a
  replay - and are keyboard-only, because on a phone the round restart button and
  the pause button are how a run is restarted and paused. `verify_keys.gd` covers
  all of that.
- **The Settings key rows are built on every device, touchscreen or not.** They
  used to be gated behind `DisplayServer.is_touchscreen_available()` (a tap hint
  on a touchscreen, the rebind rows otherwise). An iPad with a keyboard attached
  reports a touchscreen, so Settings showed the "Controls" heading with nothing
  under it and the keys could not be rebound. The rows are always built
  (`_settings_controls`); the tap hint is added *alongside* them. `verify_keys.gd`
  drives `_settings_controls` directly and asserts the rows exist, which the
  headless UI check cannot do because it has no touchscreen to trip the old gate.
- **`select(name)` is the one entry point.** It toggles the tab buttons, emits
  `tab_changed`, and `App._on_tab_changed` shows the matching page and refreshes
  it. Setting a tab's content state must happen *after* `select()`, because
  `select()` re-runs the refresh (the account form is shown after the refresh,
  or the refresh would reset it to the overview).
- **Content is a centred column that reads from the top.** Each page is a
  `ScrollContainer` holding an `HBoxContainer` with `ALIGNMENT_CENTER` and a
  single width-capped column, so a tall page scrolls and a wide window keeps a
  readable column instead of stretching edge to edge. Do not reintroduce a
  `CenterContainer` - it centres vertically, which floats a short page into the
  middle of the screen.
- **The shell's background absorbs input.** The `ShellBg` panel is
  `MOUSE_FILTER_STOP`, not `IGNORE`: it is opaque, so a click in an empty spot
  must not fall through to the HUD controls (the pause button) underneath it.
- **Icons are geometry, not glyphs.** `ui_icon.gd` (`UiIcon`) draws each icon on
  a 24x24 grid. The theme font has no icon glyphs, so a character like `⚙` or
  `▶` renders as an empty box - the same trap the restart button hit with U+21BB.
- **Buttons that carry a label must be able to shrink.** Grid and segment
  buttons set `clip_text` and `SIZE_EXPAND_FILL`; without it a button reserves
  its full text width as a minimum and pushes the column past the viewport.
- **`clip_text` hides the last digit if the chip is too narrow.** The track list
  is a `GridContainer` of `GridChip` toggles, each carrying the number and the
  player's best time as two child `Label`s. The column count is what decides
  whether those fit: at 7 columns a phone chip has ~28px of content and a
  "10.142s" best needs 32px, so every real PB clipped. It is **5 columns** now,
  which gives 44px and still fits thirteen tracks in three rows with the Play
  button at y=404 of 820. `verify_ui.gd` measures both labels against the chip's
  content width - against a *seeded* realistic time, not the `--` of a fresh
  install - and fails if either clips, because the failure is silent: the button
  still works, it just shows the wrong text.
- **A child `Label` does not inherit a button's `font_pressed_color`.** The
  selected track chip is painted in the gold accent, and the theme swaps the
  *button's* text to `ACCENT_TEXT` for contrast. Labels added as children keep
  their own colour, so a near-white number and an `INK_DIM` best sat at 1.36:1
  and 1.47:1 against the gold - invisible. `_refresh_track_bests` recolours both
  lines from the chip's own `button_pressed`, and `verify_ui.gd` measures the
  selected chip's labels against the accent and fails under 4.5:1. Any new
  button-with-labels needs the same treatment.
- **The version line is on Settings**, not under the Play button.

## The track editor (the Editor tab)

Players build their own roads on the **Editor** tab. The model is
`godot/scripts/customtracks.gd` (`CustomTracks`), the UI is
`godot/scripts/track_editor.gd` (`TrackEditor`, a full-screen overlay) and the
map is `godot/scripts/track_preview.gd` (`TrackPreview`). Nothing here invents
geometry: a custom track is the same ordered op list `Track.build_ops` already
walks for the advanced and reattach tracks, so a hand-built road drives exactly
like a shipped one.

- **A custom track is an op list, not a new kind of road.** `CustomTracks` only
  authors and stores that list; `Track` turns it into a road. This is why the
  preview can be trusted: `TrackPreview` builds a real `Track` from the ops, so
  the shape on screen is the shape the car drives, lead-in and closing straight
  included.
- **Custom ids start at `ID_BASE` (1000).** The record, time, replay and history
  stores are all keyed by the track number, so a custom id must never collide with
  a built-in one. `App` resolves an id to its ops through `Game.opts_provider`, a
  `Callable` App installs, so `Game` stays free of the editor and a built-in track
  needs no provider.
- **A custom track is a speedrun course.** It is finite and timed, so the mode is
  forced to speedrun: `_set_mode("endless")` moves the selection back to a built-in
  track rather than hiding the custom picker with a dead selection behind it, and
  the custom picker is hidden in endless like the built-in grid.
- **Custom runs are local-only.** The server has never heard of a custom id and the
  shape is the player's own, so a finished custom run never uploads and shows no
  leaderboard or world-record row (`App._on_game_change`). The run is still saved
  locally - time, history and replay - which is all a custom track needs. The same
  reason means it cannot be ranked: `Leaderboard` only knows the built-in tracks.
- **Validation is the gate, and it is the same on both sides.** `CustomTracks.validate`
  refuses a road that would fold (a corner angle outside `ANGLES`, a radius or
  straight out of range, fewer than two corners, more than `MAX_CORNERS` corners,
  too many pieces), and the Play button is disabled while it refuses. The editor
  cannot build a road the game cannot drive.
- **`MAX_RADIUS` must stay inside `Cfg.GRAB_RANGE` (95).** A pole is only
  catchable from within `GRAB_RANGE`, so a corner whose arc radius is at or past
  that is *impossible* - the car flies straight past the pole into the wall. The
  editor used to allow radius up to 120 and reported such a track "ready"; it is
  now capped at 92, and `verify_editor.gd` pins `MAX_RADIUS < GRAB_RANGE` and
  drives the widest allowed corners to prove they are catchable. If you ever raise
  `MAX_RADIUS`, raise the proof with it.
- **The direction default keeps the road from folding.** Corners alternate: two
  90-degree corners the same way would point the road back over itself.
  `CustomTracks.next_corner` therefore defaults each new corner to the opposite of
  the last, and the palette offers 90 / 180 / 270 - a single arc over a half turn
  is one pole (see "Track shape").
- **A custom track carries its own colours.** `road` and `ground` are hex strings
  on the stored entry; the stripe and the poles are derived from them
  (`CustomTracks.theme_colors`) so a player picks two colours and gets a coherent
  road. The colours travel to a run on the `Track` opts (`opts(ops, entry)`), and
  `Game.load_track` copies them onto `Renderer2D.theme_override`. A built-in track
  has no theme in its opts, so `theme_override` stays empty and the per-seed
  palette is unchanged. `theme_of` always returns a complete, valid pair (a missing
  or malformed value falls back to `DEFAULT_THEME`), so the renderer never guards a
  half-set palette.
- **The editor is a blank grid and a palette.** The whole surface is the map with a
  grid drawn on it; the piece palette is pinned along the bottom. Tap a palette
  piece to arm it, tap the grid, and the piece is added. That is the entire
  authoring flow - there are no pages, no piece list and no sliders on screen. The
  selected piece's controls, the colours and the help live in a sheet that only
  opens when asked for (`_open_piece`, `_open_look`), so the editing surface is
  never a wall of controls.
- **A new track is an empty canvas, not a starter road.** `CustomTracks.default_ops`
  returns `[]`, so the player places their own first piece instead of deleting a
  seeded S-bend. An empty track is refused as drivable ("Tap a piece below, then tap
  the grid to place it.") but that reads as a hint, not the red error an invalid
  track gets. The preview still builds the road from whatever ops exist, even while
  they are not yet valid, so the canvas shows the track as it grows rather than
  staying blank until it is legal. One trap: with no ops there is no `Track` to ask
  for the road start, and the first piece must still grow from the **end of the
  lead-in**, not the world origin - `TrackPreview._start_world` derives it from
  `Cfg.BASE_HEADING` and `CustomTracks.LEAD_IN`, and `verify_editor.gd` pins it. The
  map also centres on that point (`centre_on_road_start`, called from `_fit_soon`
  because `rebuild` runs before the map has a size) so the grid the player taps is
  the grid the piece lands on.
- **A tap cannot place a piece at an arbitrary point, because the road is
  continuous.** An op is a length or a turn *relative to where the last op ended*,
  so a piece is always appended to the road's end. The tapped cell therefore sets
  how far the next straight runs (its distance from `preview.op_end_world()`).
  Moving a piece to a disconnected spot would need a road made of separate ribbons,
  which is not what the game drives. If the editor is ever asked to "put a piece
  there", this is the constraint to explain first.
- **A turn tile places its own signed angle; the tap does not aim it.** The palette
  carries left and right variants (`90`/`-90`, `270`/`-270`, `reattach`/
  `reattach_l`) because the two are different roads. Placement reads the angle off
  the tile (`PieceIcon.turn_deg`), so the same tile always adds the same turn
  wherever the grid is tapped. Aiming a turn at the tapped cell instead meant one
  tile could place a left or a right corner depending on where the finger landed,
  which is what made the palette feel like it was guessing.
- **The palette art is generated from the arc the piece produces.** `PieceIcon`
  draws the centreline from `Track.build_ops`' own geometry - pivot one radius to
  the side of the entry, sweep by the signed angle - rather than from hand-drawn
  shapes, and fits the arc's bounding box to the tile. The sign of `deg` decides
  which side the pivot sits on, which is what makes a left tile look like a left
  turn; a fixed side drew every turn the same way. `arc_points` is static so
  `verify_editor.gd` can assert each tile exits to the side its label claims and
  stays inside its box, instead of testing a copy of the arithmetic.
- **The grid is drawn last and adapts to the ground.** It has to survive a bright
  ground: the theme presets run from near-black (Night) to amber (Sunset), and a
  fixed light ink at 7% alpha measured a contrast of 0.073 against Sunset - the
  grid was drawn and simply invisible. It is now the final draw (over the road, so
  it never gets painted out) and picks dark lines on a light ground, light lines on
  a dark one. `verify_editor.gd` checks the contrast on every preset.
- **One piece per pick.** Placing a piece clears `_armed`, so the next grid tap
  cannot silently add a second piece. Pick, tap, pick, tap - the player is never
  made to place something they did not choose.
- **A finish line is enough to play.** `validate` used to require 2 corners, which
  refused a road that drives perfectly well: a straight into a finish builds and
  the car crosses the line in ~3.5s. The only hard requirement is a finish, because
  without one the road has no end.
- **The map is a camera and an editing surface.** `TrackPreview` pans (drag),
  zooms (pinch / wheel / the `+`/`-` buttons), `fit`s the whole road, and
  `focus_index` centres a piece. With no piece armed, a tap (not a drag) picks the
  piece under the finger and opens it. `verify_editor.gd` checks the camera math,
  that a piece's midpoint picks that piece, and that Fit brings the road on screen.
- **A touch drag arrives twice, so handle one family only.** Godot's
  `input_devices/pointing/emulate_mouse_from_touch` is **on** by default (Android
  and iOS need it), so one finger drag is delivered as *both* an
  `InputEventScreenDrag` and an emulated `InputEventMouseMotion`. `TrackPreview`
  handled both, so every drag panned the map at double speed - the reported "the
  canvas panning is super sensitive". Emulated events carry
  `InputEvent.DEVICE_ID_EMULATION`, so `_gui_input` ignores emulated mouse events
  and lets the touch events do the work; a real mouse is not emulated, so the
  wheel, drag and click still work on desktop. `verify_editor.gd` drives the real
  `_gui_input` with a touch drag, an emulated mouse drag and a pinch and asserts
  only the first two move the camera as intended (the emulated drag must not pan).
- **Pinch is read from the raw touches, not from `InputEventMagnifyGesture`.**
  That gesture only exists when
  `input_devices/pointing/android/enable_pan_and_scale_gestures` is on, which it is
  not in this project, and the web export never emits it at all - so the old
  `InputEventMagnifyGesture`-only handler meant **pinch did not work anywhere**,
  which is what players reported. `TrackPreview` now tracks the touches in
  `_touches` and derives the pinch itself: one finger pans, two fingers zoom by the
  ratio of their span. Two rules make it behave: while a second finger is down the
  map **never pans** (otherwise a pinch drags the map sideways), and a release
  never taps unless that finger was alone and barely moved. The gesture is captured
  once, when the second finger lands (`_pinch_zoom`, `_pinch_mid`, `_pinch_world`),
  and every drag recomputes the zoom absolutely from that start - `zoom =
  _pinch_zoom * span / _pinch_dist` - then puts `_pinch_world` back under the
  midpoint. Accumulating a ratio per event compounds rounding and makes the map
  twitch as the fingers wobble; `verify_editor.gd` asserts a jittery pinch lands on
  the same zoom as a clean one.
  `enable_pan_and_scale_gestures` is deliberately left off: turning it on would
  make Godot emit the gesture *and* keep sending the touches, so the zoom would be
  applied twice.
- **Pan is measured from the finger's `position`, never from the drag's
  `relative`.** `relative` is scaled by whatever transform the platform applies to
  the event, so a build that scales `position` but not `relative` - or that
  delivers a drag twice - pans at a multiple of the finger's travel. That is the
  "pan is WAY too sensitive" report, and it is invisible in a headless run, where
  the scale is 1.0. `position` is the field tap picking already trusts, so a pan
  derived from it moves exactly as far as the finger did on every platform. The
  delta is taken against `_last_pos`, a per-finger record of the previous position
  (`PAN_GAIN` is 1.0; the map is not a slider and needs no multiplier).
  `verify_editor.gd` asserts a 30px drag moves the camera 30px, not 60, and that a
  drag whose `relative` disagrees with its `position` follows `position`.
- **`_last_pos` must be updated on the pinch path too.** Lifting one finger leaves
  the other panning from `_last_pos`, so if the pinch never recorded where the
  fingers had got to, the whole distance they travelled during the pinch lands in
  one step the instant the second finger comes up - a 65px jump in the test. The
  pinch branch writes `_last_pos` for every finger before returning.
- **`verify_ui.gd` guards the fit.** It presses New track, asserts every palette
  button and every pinned button (header + camera row) is inside the viewport,
  drives every palette piece through a grid tap and checks the right op was
  appended, checks a two-finger pinch zooms about the fingers without sliding the
  map, opens the colours sheet and checks its controls fit, then drives the custom
  road to its finish and asserts the finish card is local-only.
- **`CustomTracks.duplicate_track`, not `duplicate`.** A `static func duplicate`
  collides with the built-in `Resource.duplicate` and GDScript picks the wrong one.
- **`TrackEditor.palette` / `TrackPreview.palette`, not `theme`.** `theme` is a
  built-in `Control` member (`Control.theme`); naming the field that fails to
  compile with "Member theme redefined".
- **`set_anchors_and_offsets_preset`, not `set_anchors_preset`, for a full-rect node
  that is already in the tree.** The editor overlay is built and added to `ui_root`
  in `App._ready`, so when its `_ready` runs it is already parented. The
  anchors-only call keeps the node's current rect and only rewrites the anchors, so
  the overlay stayed **0x0** - and because the map and the control panel are its
  children, they collapsed too (the map drew a sliver and a drag missed it, which
  reads as "the camera is static"). The `and_offsets` call sets the offsets as well
  and the overlay fills the viewport. `verify_ui.gd` now asserts the overlay and
  the map are both a usable size, and drives a real drag through
  `TrackPreview._gui_input` to prove the camera moves.

## UI look, boot splash and fitting every screen

- **All UI colour comes from `godot/scripts/theme.gd` (`UiTheme`).** `App._ready`
  applies one built `Theme` to the whole UI tree, so nothing falls back to the
  engine's default grey. The palette is deep-navy panels with a warm-gold accent
  (the accent does not collide with any road theme, one of which is near-white).
  `app.gd` reaches into it for the few colours it sets per-label
  (`UiTheme.INK_DIM`, `UiTheme.DANGER`, ...) — do not hard-code a new colour in
  `app.gd`, add it to `UiTheme`.
- **The boot splash is the game's, not Godot's.** `project.godot`
  (`boot_splash/image`) points at a square `assets/ui/boot_splash.png`; a square
  reads on both portrait and landscape. `godot/web/shell.html` is the custom web
  shell (`html/custom_html_shell` in `export_presets.cfg`): full-viewport canvas,
  `dvh` sizing, safe-area padding, no page scroll or pinch-zoom, and a branded
  progress bar. Boot → loader → menu is meant to be one continuous look.
- **Comment `project.godot` with `;`, never `#`.** Godot's `ConfigFile` parser
  treats only `;` as a comment. A `#` line is not a comment: it is glued onto the
  next key, so `# ...` before `boot_splash/image=...` renames that key to
  `application/#...boot_splash/image` and the real setting parses as **empty**.
  Godot then silently falls back to the engine's built-in Godot-logo splash, and
  the web loader's `index.png` ships that robot instead of the game's mark - the
  game itself boots fine, so it looks like a web-only splash bug. `#` comments in
  `project.godot` are the trap; `;` is correct (Godot's own `; Engine
  configuration file` first line uses it). Same rule for any `.cfg`/`.import`
  parsed by ConfigFile.
- **The zoom is capped so a desktop window does not fill with tarmac.**
  `render.gd` picks `_scale = min(width_frac_zoom, _h / MIN_WORLD_H)`.
  `ROAD_W_FRAC` (0.358) and `MIN_WORLD_H` (500) are chosen to agree at the
  420x820 design size, so the phone look is unchanged and a wide window reveals
  more road at the same zoom instead of zooming in. Do not raise the width zoom
  alone — that is the "only good on a phone" bug.
- **Overlay cards track the viewport width.** `App._layout_cards` sets each
  card's `custom_minimum_size.x` to `clampf(vw * 0.46, 320, 520)`; every overlay
  is a `ScrollContainer` so a tall card scrolls instead of clipping. A new menu
  row still has to fit the card — see the phone-fit gotcha above.
- **The car is a sprite, always.** `Renderer2D.CAR_MODELS` is sprite-only
  (`assets/cars/*.png`, nose-up, sharing the -Y nose convention); the flat vector
  bodies were removed as placeholders. `assets/cars/CREDITS.md` lists the CC0
  sources. `render.gd` scales a car from its own aspect ratio.
- **The restart button is bottom-centre and its icon is drawn, not typed.** The
  in-run restart is a round ghost chip pinned to `PRESET_CENTER_BOTTOM`
  (`App._round_icon_button`), carrying `scripts/retry_icon.gd` - a `Control` that
  paints a ring plus an arrowhead. It used to be a top-left button showing the
  character `U+21BB`, which rendered as a missing-glyph box because the theme font
  (Open Sans SemiBold, the engine default) has no rotation arrow, and neither do
  the neighbouring codepoints. Do not go back to a glyph without checking
  `Font.has_char` on the actual theme font; draw the icon instead.
- **The verifiers are excluded from exports** (`exclude_filter` in
  `export_presets.cfg` lists `tools/*`), so the headless scripts do not ship in
  the web pck or the APK. Keep them out of the player-facing builds.
- **The build version has one source: `VERSION` at the repo root.** Never edit
  `App.VERSION` or `export_presets.cfg` by hand. `node tools/version.mjs --set
  <version>` writes both and increments `version/code`; `--check` (run in CI)
  fails on any disagreement. The menu shows it so a bug report can name the
  build.
- **Headless layout check.** `--shot <path> [--shot-menu|--shot-tab
  <garage|editor|play|account|settings>|--shot-overlay
  <tracks|board|history|account|tutorial|editor>]` saves one frame and quits, so
  a card can be checked at any resolution without a human driving the menu.

- Themes live in `godot/scripts/render.gd` (`THEMES`, `theme_for(seed)`);
  `Game.load` calls `renderer.set_seed(seed)` so each road has its own palette.
  Keep `road` and `ground` contrasting, or the ribbon disappears.
- `tools/` holds only `test.mjs` (physics + server verifier) and
  `sync-physics.mjs`. The old JS dev harnesses (`sim.mjs`, `serve.mjs`, the
  `.html` test pages, `ref/`) are gone with the client.

## Leaderboard, ghosts and accounts

- **The board is real runs and nothing else.** Every row is a player's own run,
  verified by the server, and every row is watchable from the `steps` it carries.
  There is no baked ghost head and no generated tail - the old "fake bots" were
  exactly those two (an invented 10-name field per track plus a ~50k-row curve),
  and they were removed. `godot/scripts/leaderboard.gd` ranks and pages the real
  runs the client fetched from the server, plus the local best that has not
  uploaded yet.
- `godot/scripts/leaderboard.gd` pages (`board_page`, 50 rows/page), slots the
  player in by time (`player_rank(time, reals)`), and exposes the fastest run
  (`world_record(reals)`). Ranks are competition ranks, so ties share a rank and
  the next distinct time skips. The server rows arrive already ordered; the local
  best is merged in by time, so the whole board is sorted by construction.
- **A row is watchable only if it carries `steps`.** A real submitted run has no
  ghost id to regenerate from, so its own button sequence is what replays it
  (`_watch_steps` in `app.gd`, decoded and fed to `Game` as a replay). The one row
  that can be un-watchable is the local best, which the server has not seen yet
  (`watchable == false`).
- **Ghosting**: pick Off / Your best in the menu. The ghost is a second `Car`
  stepped in lockstep inside the fixed-step loop (`Game.set_ghost_self`), drawn
  translucent by the renderer. It shares the track and the clock with the player,
  so the two are directly comparable. The world-record ghost option is gone with
  the baked field; a board row is watched directly instead.
- **History**: every finish is appended to `storage.addRun`, namespaced per
  account. The History overlay lists them newest first and flags personal bests.
- `godot/scripts/account.gd` talks to Supabase Auth; the session (tokens, expiry,
  the public name) lives on disk. `godot/scripts/storage.gd` namespaces
  records/times/replays per account (`guest` when signed out). Preferences stay
  global.
- **Records are keyed by the username, so a session that loses its name reads the
  guest bucket.** A Supabase token refresh returns a session with *no* username on
  it; storing that verbatim resolved the account to `null` and every PB vanished
  until the next sign-in. The name is now carried across a refresh, remembered by
  user id (`idnames.v1` in the account store) as a fallback, and healed at boot
  (`resolve_account`). If you ever key records by something else, key them by user
  id, not by a name the server may not resend.
- Guest PBs do **not** migrate into an account on sign-in: the `guest` bucket and
  the account bucket are separate. Guest runs do still queue and upload
  (`godot/scripts/api.gd`), but the local best time stays under `guest`.
- **Sign in, then refresh - never the other way round.** `_after_sign_in` awaits
  `_sync_my_runs` before it calls `_refresh_track_list`. `_sync_my_runs` is what
  merges the account's server times into the local store, so refreshing first
  drew the chips with the previous account's (usually empty) times and nothing
  redrew them: a player signing in on a fresh device saw `--` under every track
  and concluded their PBs were gone, even though the board held them. The merge
  is `_merge_my_runs` / `_merge_my_endless`, split out from the fetch so the
  ordering can be tested without a network.
- The run clock is `Car.time` (the simulated time). Do not add a second clock:
  the HUD, the saved best and a ghost's time must all be the same number, or a
  run and a ghost of that run disagree by a step (8ms) - enough to change a rank.

## Speed is constant - do not let the reel add to it

The car moves at exactly `CFG.speed`, always. When the orbit radius reels toward
the road radius, the inward motion and the around-the-arc motion are two
components of *one* velocity, not two motions to add. `Car.drift` splits one
step's travel between them (`tangential = sqrt(total^2 - dR^2)`). Adding them
instead injects free tangential speed while the radius closes, which made the
widest possible grab - exactly what holding the button down from the start
produces - the fastest line on every track. If you touch `drift`, keep the total
at `speed`, and re-check that a wide grab is not faster than a clean one
(`tools/test.mjs`, "grabbing wide is allowed and reels back to the road").

Any change to `drift` or `fly` changes what a run is worth, so the server's
verifier and the client must be re-checked together: run `node tools/test.mjs`
and `godot --headless --path godot --script res://tools/parity.gd`. A board row's
`steps` are re-simulated on the server through the same physics, so a run that no
longer reproduces its time is dropped rather than shown.

## The shared leaderboard runs on Supabase

Accounts and uploaded times live in a Supabase project, not on the device. The
schema is `supabase/migrations/0001_init.sql`; the two Edge Functions are `run`
(verify and store an upload) and `board` (serve a page of a track's board).

The design rule that matters: **a client never sends a time.** It sends the button
steps, and `run` replays them through the game's own physics to find out what the
run was worth. A forged time has nothing to attach to. Keep it that way - the
moment a time becomes an input, the board is worthless.

Three consequences worth knowing before editing:

- **The physics is vendored into the function.** Deno cannot import across the
  function directory, so `tools/sync-physics.mjs` copies `physics/{config,util,
  track,car,tracks}.js` into `supabase/functions/_shared/physics/`. Never edit
  those copies; edit `physics/` and re-run the script.
  `node tools/sync-physics.mjs --check` fails if they are stale, so run it in CI.
- **Runs are stored as whole ticks, not seconds.** The clock is `ticks / 120`
  exactly. The client's own accumulated `car.time` drifts by ~4e-15 over a run,
  which is enough to reorder a tie; the step count does not drift.
- **The database enforces access, not just the function.** RLS is on with read
  policies for the board and *no* insert or update policy on `runs`, so a client
  POSTing straight to PostgREST gets a 42501. `submit_run` is security-definer and
  revoked from `anon`/`authenticated`, so only the service role can write. If you
  add a write path, add it as a function, not a policy.

### Auth settings that bite

`mailer_autoconfirm` is **false** on this project: a new player must click the
confirmation email before they can sign in. `site_url` was left at
`http://localhost:3000`, so confirmation links point at a dead host - set both in
the dashboard (Authentication -> URL Configuration) before real players sign up.
`@example.com` addresses are rejected by Supabase as a reserved domain, so use a
real domain for test accounts.

### Where the client finds the project

`godot/scripts/netconfig.gd` holds the project URL and the public anon key. There
is no build step and no secret, because the anon key is designed to be visible and
RLS is what constrains it. Override them without editing the file via
`user://slingdrift.net.json` or the `--net-url`/`--net-key` command-line flags. To
point the game at a different project, change the defaults in `netconfig.gd`.

The player's session and the upload queue live under `user://` (see
`godot/scripts/storage.gd`). Bumping a filename suffix deliberately invalidates
whatever the old shape was, which is why the versions are there.

### Deploying the functions

`supabase/functions/**` deploys itself: `.github/workflows/deploy-functions.yml`
runs `supabase functions deploy board` on any push that touches that path. The
management token lives in the `SUPABASE_ACCESS_TOKEN` repository secret, so no one
has to paste one in by hand.

Two things the CLI needs in CI. `--yes`, because a hosted change refuses to
proceed without it and there is no one at a prompt to answer. And `--remote=<ref>`
rather than `--project-ref`, which is deprecated and warns.

Deploying by hand, if the workflow is ever unavailable:

```bash
export SUPABASE_ACCESS_TOKEN=...   # supabase.com/dashboard/account/tokens
supabase functions deploy board --remote=pleotpbgzeohxbuxffiq --yes
```

A wrong deploy here does not degrade quietly. The board is what the game reads for
real runs, so a function that 500s takes the whole leaderboard with it - which is
exactly what the `steps`-on-the-view bug would have done. The workflow's `smoke`
job checks both boards after deploying; to check by hand:

```bash
node tools/smoke.mjs board
```

### The `leaderboard` view has no `steps`

`public.leaderboard` is a view over `runs` joined to `profiles`, and it carries
`track, user_id, username, ticks, seconds, created_at, rank` - and nothing else.
`steps` lives on `runs`, the table underneath.

This matters because the obvious-looking query is wrong:

```ts
// Fails with "column steps does not exist", so the whole board 500s.
.from('leaderboard').select('username, seconds, steps')
```

The board function therefore reads twice: the view for the ranking the game
trusts, and `runs` for the button sequence, joined on `user_id`. `runs` holds one
row per player per track, so that join is one-to-one. RLS allows the public read
on both, so the anon key is enough and no service key is needed.

The failure mode is worth remembering: the wrong query does not degrade, it takes
the entire board down with a 500. If the board ever goes blank, check the select
list before anything else.

### The record tracker, and the client settings that are gone

The record tracker posts from the server, not the browser. The `run` Edge Function
(`supabase/functions/run/index.ts`) reads the webhook and the two message templates
from `tracker_config` and announces an improvement itself, so every player's run is
announced rather than only the admin's. The webhook is writable only through
`set_tracker_config`, which checks a row in `public.admins` (0006), and no client
can read `webhook_url` back - so the credential goes up and never comes down, and
the `run` function only ever posts to discord.com. `supabase/tests/tracker_rls.sql`
proves a normal player's update and RPC call are refused (42501), an admin's
succeed, and the service role can still write directly; CI runs it on a postgres
service container.

The old JS client had a settings screen (zoom, the hook colour) and an admin code
(`0404`, checked in the client - a lock on a cupboard, not a safe) that revealed the
webhook field and the message templates, plus a "Send test" button
(`js/discord.js`). None of that is in the Godot build; the tracker is server-only
now. If an in-game admin panel is wanted again, treat "admin" as a UI convenience
and keep anything that matters gated on the server, never on a client-side code.

## The online layer (Godot)

The Godot build talks to the same Supabase project the server runs. The online
layer lives in four files, and the split is deliberate:

- `godot/scripts/net.gd` — the transport. One shared `HTTPRequest`, one request in
  flight at a time, 8s timeout, every call resolving to
  `{ok, status, body, error}` so no caller has to catch anything.
- `godot/scripts/netconfig.gd` — the project URL and public anon key, plus the
  headers and endpoint helpers.
- `godot/scripts/api.gd` — the run queue and the board client.
- `godot/scripts/account.gd` — Supabase Auth.

Four things are load-bearing and easy to break:

- **The web export is built without threads** (`variant/thread_support=false` in
  `export_presets.cfg`, which makes Godot demand `web_nothreads_release.zip`).
  `HTTPRequest.use_threads` must stay `false`, and every call has to go through a
  node that is *in the tree* - a request from outside the tree fails with
  `ERR_UNCONFIGURED`. `Net.shared()` is created unparented and `_send` attaches it
  once the tree is up, because a caller can arrive from `_init` before the tree
  exists.
- **Nothing online blocks play.** A finished run is saved locally first and the
  upload is best-effort; if it cannot go out it stays in the queue
  (`user://slingdrift.queue.v2.json`, capped at 50) and is retried on the next
  flush. A guest's run queues too and is sent after they sign in.
- **The client still never sends a time.** It sends the button steps and the server
  replays them through the vendored `physics/`. Do not add a time field.
- **The board is the server's real runs.** `Leaderboard.board_page` merges them
  with the local best by time, so a run's rank is its position among the real
  runs. There is no local field to merge against any more - the board is only
  what players actually did. `verify_online.gd` checks that merge.

A real submitted run carries its own `steps`, and watching it replays those
steps. Anything that watches a board row dispatches on that: see `_watch_wr`,
`_watch_steps` and the board row button in `app.gd`.

The account UI asks for an email and a password now (Supabase Auth owns the
credentials), not a username and a password. The username is a separate, public
`profiles` row: register collects it, and a sign-in that lands on an account with
no profile yet asks for one.

**Tracks 26-28 upload, and a new track joins the tracker for free.** The server
validates a run against the game's own track set: `PLAYABLE_TRACKS` in the vendored
physics (`supabase/functions/_shared/physics/tracks.js`), which is derived from the
track tables, and `isPlayableTrack` guards both the `run` and `board` functions. A
reattach run verifies because the reattach pillar is now in the verified JS physics
(`physics/car.js`), not only in `godot/scripts/car.gd`.

Adding a track is therefore one entry in one track table (`physics/tracks.js` for
the server, `godot/scripts/tracks.gd` for the game) and nothing else: both sides
*derive* their playable set from those tables, the tracker announces any accepted
run with no list of its own, and `runs.track` no longer carries a hard-coded set
(`0004` relaxes it to `track > 0`, leaving the function as the authority). Do not
reintroduce a hand-written track list in `PLAYABLE_TRACKS`, the DB constraint, or
the `board`/`run` functions - that is exactly what left 26-28 unuploadable.

The one place the two physics must stay in step is the reattach numbers: change
`physics/car.js` + `physics/config.js` and `godot/scripts/car.gd` + `cfg.gd`
together, then `node tools/sync-physics.mjs`. `tools/test.mjs` and
`verify_reattach.gd` assert the same claims on each side.

### The endless board is player + distance

Endless has its own online board now, and it is deliberately the simple one: it
lists **the player and the distance**, furthest first. It is not the speedrun
board and it does not share a table with it.

**Why its own table.** A speedrun row is a *verified* run: it carries the button
steps and the tick count the `run` function replayed to get them, and the board
ranks lowest-first. An endless row is a distance, ranked highest-first, with no
steps and no replay. Folding it into `runs` would mean nullable columns for both
modes and a ranking that flips direction per row. So `endless_runs`
(`supabase/migrations/0005_endless.sql`) holds `(user_id, seed, metres)`, one row
per player per seed, and `endless_leaderboard` ranks it
`rank() over (partition by seed order by metres desc, created_at asc)`.

**This is the one place a client sends a score, and only here.** The rule "a
client never sends a time" still holds for the *verified* speedrun board, and
nothing in this path can write to `runs`. An endless run is not re-simulated:
there is no endless ramp in the server's `physics/`, and a distance board does not
need one. The `run` function accepts `{mode:'endless', track:<seed>, metres:<n>}`
and calls `submit_endless_run`, which keeps the higher `metres`; the `board`
function takes `?mode=endless` and reads `endless_leaderboard`. Both are still
service-role only for writes.

**Endless is pinned to one shared seed.** A distance board only compares anything
if everyone drives the same road, so `Game.ENDLESS_SEED` (7) is the road, not the
player's track preference: `game.gd:load_track` ignores the passed seed in endless
and the board is keyed by that constant. Change the constant to change the endless
road for everyone at once.

**Endless runs are not watchable.** There are no steps behind a row, so the board
row is a plain label - no Replay button - and `board` sends `steps: null`,
`watchable: false`. The client's `_render_endless_board` draws rank, name and
`_fmt_dist(metres)`, and appends the player's own local best if the server has not
listed it yet.

**The score is a distance, and it depends on the line.** `Car.distance()` counts
what was actually travelled, not `time x base speed`: the endless ramp and a
reattach slingshot both make the car faster than base speed. That is the client's
number and the server stores it as given.

The upload path is best-effort like everything else: `Api.enqueue_endless` keeps
only the furthest distance per seed in the queue, so a later shorter run cannot
overwrite a better one still waiting to send, and `_sync_my_runs` pulls the
player's endless bests back down on sign-in.

