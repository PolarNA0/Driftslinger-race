# Sling Drift

A one-button car-drifting game (a Sling Drift clone). Hold to sling the car
round a pillar, let go to fly straight to the next one. Leave the road and the
run ends. Two modes: **speedrun** (a finite ~10s track, scored by time) and
**endless** (an infinite road, scored by distance in metres).

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
  6–20 were removed, so the numbers are not a contiguous range.
- `godot/scripts/car.gd` — the physics. `step(dt, held)` is pure and testable.
- `godot/scripts/game.gd` — fixed 1/120s tick, modes, records, ghosts.
- `godot/scripts/render.gd` — top-down orthographic view, road themes, and both
  the vector cars and the sprite cars.
- `godot/scripts/app.gd` — the shell: menu, overlays, leaderboard, history,
  accounts, car picker, the round restart button.
- `godot/scripts/{ghostrun,ghostdata,replay,storage,leaderboard,account}.gd` —
  the ported support modules.
- `godot/scripts/{net,netconfig,api}.gd` — the online layer's transport, config
  and leaderboard client (see "The online layer").
- `godot/scenes/main.tscn`, `godot/project.godot` — scene and project settings.
- `godot/tools/` — headless verifiers (`parity.gd`, `verify_tracks.gd`,
  `verify_reattach.gd`, `verify_board.gd`, `verify_online.gd`,
  `verify_guard.gd`) and the ghost baker (`bake_ghosts.gd`). See
  `godot/README.md`.

### JavaScript (the server's physics)

- `physics/config.js` — all tunables (`CFG`). The single source of the feel; the
  Godot `cfg.gd` mirrors it.
- `physics/track.js` — procedural road: a staircase of straight legs joined by
  quarter-turn circular-arc corners, sampled into `road[]` (points) and `rs[]`
  (arc-length per point). Takes `opts` (`corners`, `radius`, `leadIn`,
  `finishLen`, `segLens`, `targetTime`) so a finite track can have its own shape;
  endless play passes none and gets the uniform `CFG` lengths.
- `physics/tracks.js` — the ten playable time-attack tracks (`PLAYABLE_TRACKS`:
  1–5 and 21–25; 6–20 were removed). `trackDef(n)` is a pure
  function of the track number: radius, corner count, lead-in and the straight
  rhythm all come out of `n`, so a track is identical on every device (which the
  leaderboard and replays rely on). `targetTime` makes `Track.buildFinish` size
  the closing straight to land the clock on ~10s.
- `physics/car.js` — the physics. `step(dt, held)` is pure and testable.
- `physics/util.js` — `angDiff`, `mulberry32` (bit-exact with the Godot port).
- `tools/test.mjs` — headless tests for the physics and the server's run
  verifier. Must stay green.
- `tools/sync-physics.mjs` — vendors `physics/` into the Edge Function, and
  `--check` fails if the copies drift.

## Commands

```sh
# Godot build (the game)
godot --path godot                                        # play
godot --headless --path godot --import                    # first-time import
godot --headless --path godot --script res://tools/parity.gd          # physics vs golden JS numbers
godot --headless --path godot --script res://tools/verify_tracks.gd   # all tracks finish
godot --headless --path godot --script res://tools/verify_reattach.gd # reattach pillar
godot --headless --path godot --script res://tools/verify_board.gd    # board paging
godot --headless --path godot --script res://tools/verify_online.gd   # online layer (offline paths)
godot --headless --path godot --script res://tools/verify_guard.gd    # holding/mashing must lose
godot --headless --path godot --script res://tools/bake_ghosts.gd     # regenerate ghostdata.gd (slow)

# Physics + server verifier (JavaScript, must stay green)
node tools/test.mjs            # headless core tests
node tools/sync-physics.mjs    # vendor physics into the Edge Function
node tools/sync-physics.mjs --check  # fail if the vendored copies are stale
```

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
- **Android build: `screen/immersive_mode=true` is a second suspect.** Immersive
  mode keeps the app fullscreen and can stop the soft keyboard from showing for a
  focused `LineEdit` on some devices and Android versions. Godot 4.5 should force
  the keyboard for a focused line edit regardless, but if the APK still refuses to
  raise it, turn immersive mode off (accepting the status/nav bars) and retest
  before digging deeper.

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
- **A reattach pillar reopens on an early release.** A normal pillar is spent the
  instant you let go (`Car.release` sets `spent = corner`). A pillar whose fillet
  carries `reattach: true` is spent only when you ride the arc to its end
  (`done()`); bail out partway and it stays live, so the same pole can be caught
  again after you fly off and come back. The re-grab unwraps the orbit onto the
  angle you left from (`released_angle`), not the arc start, so your progress
  round the corner is kept instead of reset. Riding every arc out - the clean
  line - spends the pillars exactly as before, which is why ordinary play is
  unchanged. Tracks 26-28 (`Tracks.REATTACH_TRACKS`) showcase it; the renderer
  paints a live reattach pillar amber and a spent one bronze.

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
- **The Godot menu must fit a phone, and the overlays must scroll.** The project
  viewport is 420x820 with `canvas_items` stretch and `expand` aspect. The old menu
  packed a 13-cell track grid plus a 13-swatch car row into one card, so the card
  measured 664x851 - wider *and* taller than the viewport. Anything past the bottom
  edge cannot be tapped, which is why players could not reach **Sign in**. Two rules
  keep it fixed: every overlay card lives inside a `ScrollContainer`
  (`_new_overlay`), so a tall card scrolls instead of clipping; and no menu row is
  allowed to be as wide as its content (`_mode_button` wraps, the car swatches and
  the track list are `GridContainer`s). Tracks moved off the menu onto their own
  **Tracks** button. If you add a row, re-measure: a card taller than 820 or wider
  than 420 is the bug coming back. A headless check that presses Sign in and asserts
  every menu button's `get_global_rect()` is inside the viewport is the cheapest
  guard.
- Themes live in `godot/scripts/render.gd` (`THEMES`, `theme_for(seed)`);
  `Game.load` calls `renderer.set_seed(seed)` so each road has its own palette.
  Keep `road` and `ground` contrasting, or the ribbon disappears.
- `tools/` holds only `test.mjs` (physics + server verifier) and
  `sync-physics.mjs`. The old JS dev harnesses (`sim.mjs`, `serve.mjs`, the
  `.html` test pages, `ref/`) are gone with the client.

## Leaderboard, ghosts and accounts

- The **head** of each board is real and watchable: `godot/tools/bake_ghosts.gd`
  runs the ghost policy over many ids and writes the fastest few per track to
  `godot/scripts/ghostdata.gd` as `[time, ghost_id, name]`.
  `godot/scripts/ghostrun.gd` turns an id into a deterministic button policy, so a
  ghost's replay is re-simulated on demand.
- The **tail** of the board is generated from a monotonic curve in
  `godot/scripts/leaderboard.gd` and is *not* watchable (`row.watchable == false`). This is
  the deliberate trade: a watchable ghost needs a real simulation behind it, and
  only the world record and the few runs behind it are ever actually watched. A
  whole 50,000-run watchable field is slow to bake and large to ship.
- The physics only allows a finishing run inside a narrow band of times (about
  0.25s of distinct times per track, with ties beyond that), so a large field has
  many tied times. That is why the field is baked rather than invented: a made-up
  time would have no run behind it, and a ghost you cannot watch is not a ghost.
- `godot/scripts/leaderboard.gd` pages over the field (`board_page`, 50
  rows/page), slots the player in by time (`player_rank`), and exposes the fastest
  ghost (`world_record`).
  The real head is a sorted array; the generated tail is a monotonic curve, so
  both rank by binary search and the whole board is sorted by construction.
- **Ghosting**: pick Off / World record / Your best in the menu. The ghost is a
  second `Car` stepped in lockstep inside the fixed-step loop
  (`Game.set_ghost_replay` / `set_ghost_self`), drawn translucent by the
  renderer. It shares the track and the clock with the player, so the two are
  directly comparable.
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

Any change to `drift` or `fly` invalidates `godot/scripts/ghostdata.gd`: the
baked ghosts are real runs of the real physics. Re-run
`godot --headless --path godot --script res://tools/bake_ghosts.gd` after a
physics change, or every ghost fails to reproduce its claimed time.

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
exactly what the `steps`-on-the-view bug would have done. Check the endpoint after
deploying:

```bash
curl -s "https://pleotpbgzeohxbuxffiq.supabase.co/functions/v1/board?track=1" \
  -H "apikey: <anon key>" | head -c 300
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
announced rather than only the admin's. RLS lets a signed-in player write
`webhook_url` but not read it back, so the credential goes up and never comes down,
and the `run` function only ever posts to discord.com.

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
- **The board is one board, not two.** `Leaderboard.board_page` merges the server's
  real runs into the baked ghost field by time, so a real run displaces the ghosts
  it beats and its rank is its merged position. `verify_online.gd` checks that
  merge against reference values recorded from the old JS `boardPage`, so the port
  still agrees with the original.

A real submitted run has no ghost id, so it cannot be re-simulated from an id the
way a baked ghost can. It carries its own `steps` instead, and `Game.set_ghost_steps`
races it. Anything that watches a board row has to dispatch on that: see
`_watch_wr`, `_watch_steps` and the board row button in `app.gd`.

The account UI asks for an email and a password now (Supabase Auth owns the
credentials), not a username and a password. The username is a separate, public
`profiles` row: register collects it, and a sign-in that lands on an account with
no profile yet asks for one.

**Tracks 26-28 cannot be uploaded yet.** The server validates `1..25`
(`supabase/functions/board/index.ts`, and `TRACK_COUNT` in the vendored physics),
while the Godot build has 28 tracks, and the reattach physics exists only in
`godot/scripts/car.gd`. A reattach run is therefore rejected with a 422 and dropped
from the queue. Teaching the server the reattach physics is the work that unblocks
it; until then those three tracks are local-only.
