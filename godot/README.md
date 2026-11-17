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
skins, ghosts), the leaderboard with watchable ghosts, run history, accounts, and
the online layer (Supabase upload, the shared board, and replaying another
player's uploaded run) are all ported. The physics matches the JS the server
verifies runs with, and every track finishes near ten seconds in both.

Additions on top of the port:

- **Reattachable pillars.** A normal pillar is spent the moment you let go. A
  reattach pillar stays live if you release partway round its arc, so you can
  fly off, come back, and grab the same pole again. Riding the arc out still
  spends it, which keeps the ordinary clean line working exactly as before.
  Tracks 26–28 showcase it (amber = still catchable, bronze = spent).
- **Sprite cars.** Free CC0 top-down cars (see `assets/cars/CREDITS.md`) sit
  alongside the eight vector colours in the car picker.
- **A menu that fits a phone.** The track list moved behind its own **Tracks**
  button and every overlay card scrolls, so the account controls are reachable on
  the 420x820 viewport instead of running off the bottom of the screen.
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
runs upload, the shared board merges real runs with the baked ghost field, and
another player's uploaded run can be watched from its stored steps.

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
```

`tools/verify_board.gd` checks the leaderboard paging and ranking.

`tools/verify_guard.gd` proves the one rule that matters: holding or mashing
never beats the game. A clean line survives 120 corners, holding forever crashes
within two, every mash pattern dies within three, and a release up to 15 degrees
early still finishes.

```sh
godot --headless --path . --script res://tools/verify_guard.gd
```

`tools/verify_online.gd` checks the online layer's offline-testable parts: the
board merge (against reference values recorded from the JS `boardPage`), the run
queue, the client id, the account rules that must hold with no session, and the
net config. The network paths themselves need a server, so they are not covered
here.

```sh
godot --headless --path . --script res://tools/verify_online.gd
```

`tools/verify_ui.gd` checks the menu layout at phone and desktop sizes. It builds
the real scene in a `SubViewport` of each size (headless cannot resize the OS
window), presses the real tabs, and fails if any control lands outside the
viewport or if a tab's page does not come up. This is the guard for the bug the
old card menu had: a control taller than the screen, so its buttons could not be
pressed.

```sh
godot --headless --path . --script res://tools/verify_ui.gd
```

`tools/bake_ghosts.gd` regenerates `scripts/ghostdata.gd` from the Godot physics.
It is slow (a thousand ids per track), so it is a manual step, not a verifier:

```sh
godot --headless --path . --script res://tools/bake_ghosts.gd
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
| `scripts/ghostrun.gd` | the old `js/ghostrun.js` — a ghost from an integer id |
| `scripts/replay.gd` | the old `js/replay.js` — button-step replays |
| `scripts/storage.gd` | the old `js/storage.js` — records, best times, replays, history, prefs |
| `scripts/leaderboard.gd` | the old `js/leaderboard.js` — paging, ranking, the board |
| `scripts/net.gd` | new — the HTTP transport (one request at a time) |
| `scripts/netconfig.gd` | new — the Supabase URL and anon key, and the endpoints |
| `scripts/api.gd` | the old `js/api.js` — the run queue and the board client |
| `scripts/account.gd` | the old `js/account.js` — Supabase Auth and the `profiles` name |
| `scripts/render.gd` | the old `js/render.js` — themes, camera, road band, vector and sprite cars |
| `scripts/game.gd` | the old `js/game.js` — fixed 1/120s tick, modes, records, ghosts |
| `scripts/app.gd` | the old `js/app.js` — the tabbed menu (Play/Garage/Account), the board/history/settings overlays, leaderboard, history, accounts |
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

Add `--shot-tab <play|garage|account>` to capture a menu tab, or `--shot-menu`
for the menu as it opens.
