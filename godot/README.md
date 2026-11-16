# Sling Drift — Godot port

A port of the web remake in `../slingdrift` to Godot 4.5. Same physics, same
twenty-five tracks, same top-down look, plus three reattach showcase tracks and a
sprite car.

## Status

Feature-complete with the web build. Physics, track generation, all twenty-five
time-attack tracks, rendering, the one-button loop, the full menu shell (mode and
track pickers, car skins, ghosts), the leaderboard with watchable ghosts, run
history, and local accounts are all ported. The physics is bit-for-bit identical
to the JS build and every track finishes near ten seconds in both.

Two additions on top of the port:

- **Reattachable pillars.** A normal pillar is spent the moment you let go. A
  reattach pillar stays live if you release partway round its arc, so you can
  fly off, come back, and grab the same pole again. Riding the arc out still
  spends it, which keeps the ordinary clean line working exactly as before.
  Tracks 26–28 showcase it (amber = still catchable, bronze = spent).
- **A sprite car.** `assets/cars/topdown_car.png` (CC0, see its `CREDITS.md`) is
  the "Roadster" model in the car picker, drawn alongside the vector cars.

## Export

Both presets ship in `export_presets.cfg`: **Web** and **Android**. The web build
deploys to Cloudflare Pages.

```sh
# Web (static site in build/web)
godot --headless --path . --export-release "Web" build/web/index.html

# Android (signed debug APK)
godot --headless --path . --export-debug "Android" build/android/drift-slinger.apk
```

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

`tools/parity.gd` runs the same scripted input as `../slingdrift/tools/_parity.mjs`
and prints the end state, so the two builds can be compared number for number:

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

The physics is bit-for-bit identical to the JS build: both crash after 334 steps
at `x=657.803120 y=-278.859877 angle=5.652743`, `dead=wall`, `grabbed=2` (the
Godot numbers differ in the last digit or two, which is float32 vs float64).
The track geometry matches too (track 1: length 3074.0, finishS 3074.0, clean 10.3s).

## Layout

| File | Ports |
|---|---|
| `scripts/cfg.gd` | `js/config.js` — every tuning number |
| `scripts/util.gd` | `js/util.js` — `angDiff`, and `mulberry32` bit-exact via 32-bit `imul` |
| `scripts/track.gd` | `js/track.js` — the road |
| `scripts/car.gd` | `js/car.js` — the one-button car |
| `scripts/tracks.gd` | `js/tracks.js` — the twenty-five ported tracks, plus the reattach showcase tracks 26–28 |
| `scripts/ghostrun.gd` | `js/ghostrun.js` — a ghost from an integer id |
| `scripts/replay.gd` | `js/replay.js` — button-step replays |
| `scripts/storage.gd` | `js/storage.js` — records, best times, replays, history, prefs |
| `scripts/leaderboard.gd` | `js/leaderboard.js` — paging, ranking, the board |
| `scripts/account.gd` | `js/account.js` — local accounts |
| `scripts/render.gd` | `js/render.js` — themes, camera, road band, vector and sprite cars |
| `scripts/game.gd` | `js/game.js` — fixed 1/120s tick, modes, records, ghosts |
| `scripts/app.gd` | `js/app.js` — menu, overlays, leaderboard, history, accounts |

The PRNG is reproduced exactly (masking products to 32 bits, the way JS
`Math.imul` does) so a seed is the same road in both builds — which is what a
shared leaderboard or replay would need.

## Screenshot

`-- --shot <path>` renders one frame and quits, for headless visual checks:

```sh
xvfb-run -a godot --path . -- --shot /tmp/shot.png
```
