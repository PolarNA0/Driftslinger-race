# Sling Drift — Godot build

**This is the game.** The Godot build is the primary implementation: the web build
served to players and the Android app both come from here. New work goes here.

It began as a port of an original JavaScript build, which has since been
removed. The only JavaScript left in the repository is `../physics/`, and only
because the Supabase leaderboard replays uploaded runs through it
(`../tools/sync-physics.mjs` vendors it into the Edge Function). `tools/parity.gd`
checks the port against the numbers that physics produces.

Same physics, same ten ported tracks, same top-down look, plus three
reattach showcase tracks and sprite cars.

## Status

Feature-complete. Physics, track generation, all ten ported time-attack tracks,
rendering, the one-button loop, the full menu shell (mode and track pickers, car
skins, ghosts), the leaderboard, run history, accounts, and the online layer
(Supabase upload, the shared board, and replaying another player's uploaded run)
are all ported. The physics matches the JS the server verifies runs with, and
every track finishes near ten seconds in both.

Additions on top of the port:

- **Reattachable pillars.** A normal pillar is spent the moment you let go. A
  reattach pillar stays live if you release partway round its arc, so you can
  fly off, come back, and grab the same pole again. Riding the arc out still
  spends it, which keeps the ordinary clean line working exactly as before.
  Tracks 26–28 showcase it (amber = still catchable, bronze = spent).
- **Sprite cars.** Every car in the picker is its own free CC0 top-down sprite
  (see `assets/cars/CREDITS.md`); `tools/verify_cars.gd` fails if two share one.
- **A restart key.** `R` restarts the run in progress. It can be rebound in
  Settings, where the play key is rebound too.
- **A pause key.** `Esc` pauses and resumes the run in progress. It is rebound in
  Settings alongside the play and restart keys.
- **A menu that fits a phone.** The menu is a tabbed app shell - Garage, Editor,
  Play and Account across the bottom, Settings in the top bar - with a scrolling
  content sheet, so every control is reachable on the 420x820 viewport instead of
  running off the bottom of the screen. The track chooser is a grid on the Play
  tab; there is no separate Tracks button.
- **A track editor.** Players build their own roads from a piece palette on a
  real `Track`, store them per account, and drive them as local-only time trials.
- **A road band that survives a self-crossing.** The band is drawn as explicit
  triangles rather than one filled polygon, so the hairpin/loop tracks (21-25) no
  longer flash as the car crosses its own path. See the gotcha in `../AGENTS.md`.

### Not ported from the old JS client

The old JS client had a few player-facing bits the Godot build does not have.
They were dropped when the client was removed; if they are wanted, they are new
work in `godot/`:

- **Player settings and the admin panel.** The JS client had a settings screen
  (zoom, the hook colour) and an admin code (`0404`, checked in the client, so a
  lock on a cupboard and not a safe) that revealed a Discord webhook field and
  two editable tracker message templates. None of that is in the Godot build.
- **The Discord record tracker.** `js/discord.js` posted a world-record message
  straight to a Discord webhook. The Godot build does not post anywhere but
  Supabase.

The online layer itself *is* ported (see "The online layer" in `../AGENTS.md`):
runs upload, and the shared board is exactly those real runs - every row is a
player's own verified run, watchable from its stored steps. There is no generated
field behind it.

**The endless board is shipped and is deliberately separate.** Endless is scored
by distance, furthest first, and is not re-simulated: `endless_runs` holds
`(user_id, seed, metres)`, `endless_leaderboard` ranks it, and `board?mode=endless`
serves it. Everyone drives the same endless road (`Game.ENDLESS_SEED`), so the
distances compare. See "The endless board is player + distance" in `../AGENTS.md`.

## Export

Both presets ship in `export_presets.cfg`: **Web** and **Android**. The Web
preset sets `html/experimental_virtual_keyboard=true`, which is what raises the
on-screen keyboard when a player taps an account field on a phone - leave it on,
or sign-in is impossible on mobile browsers (see `../AGENTS.md`).

```sh
# Web (static site in build/web)
godot --headless --path . --export-release "Web" build/web/index.html

# Android (signed debug APK)
godot --headless --path . --export-debug "Android" build/android/drift-slinger.apk
```

The web build deploys to Cloudflare Workers
(`https://driftslinger-race.exopolar1.workers.dev/`). Cloudflare caps a static
asset at 25 MiB and the exported `index.wasm` is ~36 MiB, so the deploy gzips it
to `index.wasm.gz` and deletes the raw file; `worker.js` serves the original
bytes back at `/index.wasm` (and redirects `/android` to the APK release). See
the "wasm is served gzipped" section in `../AGENTS.md` before changing either
file. To deploy by hand, from this directory after the export:

```sh
gzip -9 -c build/web/index.wasm > build/web/index.wasm.gz && rm build/web/index.wasm
wrangler deploy
```

The Android build is published to a rolling `android-latest` GitHub release by
`.github/workflows/build-godot-android.yml`, so
`releases/download/android-latest/drift-slinger.apk` is always the newest build.

The Android export needs the Godot 4.5 export templates, a JDK 17, and the
Android SDK (platform-tools + build-tools + platform 35), wired into the editor
settings (`export/android/java_sdk_path`, `export/android/android_sdk_path`, and
`export/android/debug_keystore`). `JAVA_HOME`/`PATH` must include the JDK so
Godot's `apksigner` step can sign the APK.


## Run it

```sh
godot --path .                       # play
godot --headless --path . --import   # first-time import (registers class names)
```

## Verify the port

`tools/parity.gd` runs a scripted input (hold and release in 0.35s phases on track
1) and asserts the end state against the numbers the JS `Car.step` produced, frozen
as golden values before that build was removed:

```sh
godot --headless --path . --script res://tools/parity.gd
```

`tools/verify_tracks.gd` drives a clean line round every track and prints the
finish time and how far off the centreline the car strayed:

```sh
godot --headless --path . --script res://tools/verify_tracks.gd
```

`tools/verify_reattach.gd` checks the new pillar: that a plain pillar stays spent
after release, that a reattach pillar can be caught again after an early bail-out
(and the car still finishes), and that riding an arc to its end still spends it.

```sh
godot --headless --path . --script res://tools/verify_reattach.gd
godot --headless --path . --script res://tools/verify_endless.gd
```

`tools/verify_board.gd` checks the leaderboard: ranking, ties, paging, and that
the board is only the real runs. There is no generated field behind it any more.

```sh
godot --headless --path . --script res://tools/verify_board.gd
```

`tools/verify_guard.gd` proves the one rule that matters: holding or mashing
never beats the game. A clean line survives 120 corners, holding forever crashes
within two, every mash pattern dies within three, and a release up to 15 degrees
early still finishes.

```sh
godot --headless --path . --script res://tools/verify_guard.gd
```

`tools/verify_online.gd` checks the online layer's offline-testable parts: the
board merge of the server's real runs with the local best, the run queue, the
client id, the account rules that must hold with no session, and the net config.
The network paths themselves need a server, so they are not covered here.

```sh
godot --headless --path . --script res://tools/verify_online.gd
```

`tools/verify_ui.gd` checks the menu layout at phone and desktop sizes. It builds
the real scene in a `SubViewport` of each size (headless cannot resize the OS
window), presses the real tabs, and fails if a tab's page does not come up or a
control is wider than the viewport (the bug the old card menu had). It then opens
the track editor and checks it: every pinned control (the header, the camera row
and the palette) is inside the viewport, every palette piece appends the op its
label claims, a pinch zooms about the fingers without sliding the map, the colours
sheet fits, the map has a real road, and `Fit` brings that road on screen. Finally
it loads the custom road into the game, checks the track's own colours reached the
renderer, and drives it to its finish to assert the finish card is local-only (no
leaderboard, no world record).

```sh
godot --headless --path . --script res://tools/verify_ui.gd
```

`tools/verify_editor.gd` checks the track editor's model, `CustomTracks`, and the
roads it produces. A hand-built track goes through the same `Track` the game loads
and the same `Car`: it must build, be driven by a clean line, and finish. It pins
the rule that every corner the editor allows is catchable (`MAX_RADIUS` is inside
`Cfg.GRAB_RANGE`, and the widest allowed corners really are driven), the corner
and piece caps, and the colours (`theme_of` / `set_theme` / `theme_colors`, the
invalid-value fallback, and that `opts_for_id` carries the theme through). It also
exercises the map camera - world/screen round-trip, zoom, pan, `focus_index`, and
that a piece's midpoint picks that piece. The store is checked too - new / rename
/ duplicate / delete, unique ids and names, the track cap, and that a deleted id
resolves to empty so the game can fall back.

```sh
godot --headless --path . --script res://tools/verify_editor.gd
```

`tools/verify_storage.gd` checks that saves are atomic: a write lands, a second
write replaces the first, a stale `.tmp` is ignored and cleared, and no temp file
is left behind - so a crash mid-save cannot truncate the last good one.

```sh
godot --headless --path . --script res://tools/verify_storage.gd
```

`tools/verify_cars.gd` checks that every car in `Renderer2D.CAR_MODELS` names
its own texture and that the texture loads - so a car is never drawn as a
placeholder or a repeat of another.

```sh
godot --headless --path . --script res://tools/verify_cars.gd
```

`tools/verify_keys.gd` checks the rebindable keys: the defaults (Space to play,
R to restart, Esc to pause), that R restarts a run and leaves a replay alone,
that Esc toggles pause on a live run only, and that a rebinding takes effect,
refuses to collide with another key, and can be cancelled with Escape. It also
checks the Settings "Controls" block always builds its rebind rows, so a device
that reports a touchscreen (an iPad with a keyboard) still gets them.

```sh
godot --headless --path . --script res://tools/verify_keys.gd
```

`tools/verify_audio.gd` checks the audio and haptics layer: the shipped assets
load, every looping cue is marked to loop, the mixer mutes without touching the
streams, and the haptic gate records calls but stays off on a desktop (a headless
run has no device, so it tests the decision, not the hardware).

```sh
godot --headless --path . --script res://tools/verify_audio.gd
```

`tools/verify_hud.gd` checks the run HUD and the settings screen: the PB/WR delta
text and colours, the speedrun progress bar, the focus-out pause, and that the
audio and feedback controls reach their owners.

```sh
godot --headless --path . --script res://tools/verify_hud.gd
```

The physics matches the JS the server verifies with: both crash after 334 steps
at `x=657.803120 y=-278.859877 angle=5.652743`, `dead=wall`, `grabbed=2` (the
Godot numbers differ in the last digit or two, which is float32 vs float64).
The track geometry matches too (track 1: length 3074.0, finishS 3074.0, clean 10.3s).

## Layout

| File | Ports |
|---|---|
| `scripts/cfg.gd` | `../physics/config.js` — every tuning number |
| `scripts/util.gd` | `../physics/util.js` — `angDiff`, and `mulberry32` bit-exact via 32-bit `imul` |
| `scripts/track.gd` | `../physics/track.js` — the road |
| `scripts/car.gd` | `../physics/car.js` — the one-button car, plus the reattach pillar |
| `scripts/tracks.gd` | `../physics/tracks.js` — the ten ported tracks, plus the reattach showcase tracks 26–28 |
| `scripts/replay.gd` | the old `js/replay.js` — button-step replays |
| `scripts/storage.gd` | the old `js/storage.js` — records, best times, replays, history, prefs |
| `scripts/leaderboard.gd` | the old `js/leaderboard.js` — paging, ranking, the board |
| `scripts/net.gd` | new — the HTTP transport (one request at a time) |
| `scripts/netconfig.gd` | new — the Supabase URL and anon key, and the endpoints |
| `scripts/api.gd` | the old `js/api.js` — the run queue and the board client |
| `scripts/account.gd` | the old `js/account.js` — Supabase Auth and the `profiles` name |
| `scripts/render.gd` | the old `js/render.js` — themes, camera, road band, vector and sprite cars |
| `scripts/game.gd` | the old `js/game.js` — fixed 1/120s tick, modes, records, the run-in-progress replay |
| `scripts/app.gd` | the old `js/app.js` — the tabbed shell (Garage/Editor/Play/Account), the board/history/settings overlays, leaderboard, history, accounts |
| `scripts/customtracks.gd` | new — `CustomTracks`, the editor's model: ops, validation, transforms, per-account storage |
| `scripts/track_editor.gd` | new — `TrackEditor`, the full-screen editor overlay |
| `scripts/track_preview.gd` | new — `TrackPreview`, the editor's pan/zoom map, grid and tap picking |
| `scripts/retry_icon.gd` | new — the drawn restart icon (the font has no rotation arrow) |
| `scripts/menu_shell.gd` | new — the full-screen app shell: top bar, content sheet, bottom tab bar |
| `scripts/theme.gd` | new — `UiTheme`, the one `Theme` for the whole UI (palette, button variations, panels, scrollbars) |
| `scripts/ui_icon.gd` | new — `UiIcon`, the tab and action icons drawn as geometry (the theme font has no glyphs) |

The PRNG is reproduced exactly (masking products to 32 bits, the way JS
`Math.imul` does) so a seed is the same road in both builds — which is what a
shared leaderboard or replay needs.

## Screenshot

`-- --shot <path>` renders one frame and quits, for headless visual checks:

```sh
xvfb-run -a godot --path . -- --shot /tmp/shot.png
```

Add `--shot-tab <garage|editor|play|account|settings>` to capture a menu tab, or
`--shot-menu` for the menu as it opens. `--shot-overlay <tracks|board|history|account|tutorial|editor>`
captures an overlay card.
