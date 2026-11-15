# Sling Drift — Godot port

A port of the web remake in `../slingdrift` to Godot 4.3. Same physics, same
twenty-five tracks, same top-down look.

## Status

Feature-complete with the web build. Physics, track generation, all twenty-five
time-attack tracks, rendering, the one-button loop, the full menu shell (mode and
track pickers, car skins, ghosts), the leaderboard with watchable ghosts, run
history, and local accounts are all ported. The physics is bit-for-bit identical
to the JS build and every track finishes near ten seconds in both.

## Android

Exports a signed debug APK (~23 MB, arm64-v8a, min SDK 21). Needs the Godot
4.3 export templates, a JDK, and the Android SDK (build-tools + platform 34).
Point the editor settings at the JDK and SDK, enable
`rendering/textures/vram_compression/import_etc2_astc`, then:

```sh
godot --headless --path . --export-debug "Android" build/sling-drift.apk
```

`JAVA_HOME`/`PATH` must include the JDK so Godot's `apksigner` step can sign the
APK.

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
| `scripts/tracks.gd` | `js/tracks.js` — the twenty-five tracks |
| `scripts/ghostrun.gd` | `js/ghostrun.js` — a ghost from an integer id |
| `scripts/replay.gd` | `js/replay.js` — button-step replays |
| `scripts/storage.gd` | `js/storage.js` — records, best times, replays, history, prefs |
| `scripts/leaderboard.gd` | `js/leaderboard.js` — paging, ranking, the board |
| `scripts/account.gd` | `js/account.js` — local accounts |
| `scripts/render.gd` | `js/render.js` — themes, camera, road band, car |
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
