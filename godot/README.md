# Sling Drift — Godot build

**This is the game.** The Godot build is the primary implementation: the web build
served to players and the Android app both come from here. New work goes here.

It began as a port of the original JavaScript build (`../index.html`, `../js/`,
`../css/`), which is now legacy. That JS build is kept only because the Supabase
leaderboard replays uploaded runs through its physics
(`../tools/sync-physics.mjs`), and because `tools/parity.gd` compares the two
builds number for number. Do not add features to the JS build.

Same physics, same ten ported tracks, same top-down look, plus three
reattach showcase tracks and sprite cars.

## Status

Feature-complete with the JS build. Physics, track generation, all ten ported
time-attack tracks, rendering, the one-button loop, the full menu shell
(mode and track pickers, car skins, ghosts), the leaderboard with watchable
ghosts, run history, and local accounts are all ported. The physics is
bit-for-bit identical to the JS build and every track finishes near ten seconds
in both.

Additions on top of the port:

- **Reattachable pillars.** A normal pillar is spent the moment you let go. A
  reattach pillar stays live if you release partway round its arc, so you can
  fly off, come back, and grab the same pole again. Riding the arc out still
  spends it, which keeps the ordinary clean line working exactly as before.
  Tracks 26–28 showcase it (amber = still catchable, bronze = spent).
- **Sprite cars.** Free CC0 top-down cars (see `assets/cars/CREDITS.md`) sit
  alongside the eight vector colours in the car picker.

### Not yet ported from the JS build

The JS client has online features the Godot build does not have yet. Porting them
is the work that has to happen before the JS client can be deleted:

- **Online leaderboard upload.** `js/api.js` uploads runs to Supabase and reads
  the shared board. The Godot board is local + baked (`ghostdata.gd`), so ranks
  and ghosts are real but not shared between players.
- **Accounts.** `js/account.js` signs in against Supabase. `account.gd` is
  device-local only (username + salted SHA-256 on this device).
- **Discord record webhook.** `js/discord.js` posts records from the browser.
- **Replay of another player's uploaded run.** `js/replay.js` + the `steps`
  field on the server; the Godot ghost path is id-based only.

## Export

Both presets ship in `export_presets.cfg`: **Web** and **Android**.

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

`tools/verify_online.gd` checks the online layer's offline-testable parts: the
board merge (against reference values produced by the JS `boardPage`), the run
queue, the client id, the account rules that must hold with no session, and the
net config. The network paths themselves need a server, so they are not covered
here.

```sh
godot --headless --path . --script res://tools/verify_online.gd
```

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
| `scripts/car.gd` | `js/car.js` — the one-button car, plus the reattach pillar |
| `scripts/tracks.gd` | `js/tracks.js` — the ten ported tracks, plus the reattach showcase tracks 26–28 |
| `scripts/ghostrun.gd` | `js/ghostrun.js` — a ghost from an integer id |
| `scripts/replay.gd` | `js/replay.js` — button-step replays |
| `scripts/storage.gd` | `js/storage.js` — records, best times, replays, history, prefs |
| `scripts/leaderboard.gd` | `js/leaderboard.js` — paging, ranking, the board |
| `scripts/net.gd` | new — the HTTP transport (one request at a time) |
| `scripts/netconfig.gd` | new — the Supabase URL and anon key, and the endpoints |
| `scripts/api.gd` | `js/api.js` — the run queue and the board client |
| `scripts/account.gd` | `js/account.js` — Supabase Auth and the `profiles` name |
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
