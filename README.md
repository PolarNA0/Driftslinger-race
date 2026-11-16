# Sling Drift

A one-button car-drifting game. Hold to sling the car round a pillar, let go to
fly straight to the next one. Leave the road and the run ends.

Two modes:

- **Speedrun** — a finite ~10s track, scored by time.
- **Endless** — an infinite road, scored by distance in metres.

## The Godot build is the game

The game is built in **Godot 4.5**. Everything ships from `godot/`:

- the **web build** served at
  <https://driftslinger-race.exopolar1.workers.dev/>, and
- the **Android app**.

See [`godot/README.md`](godot/README.md) for how to run, export and verify it.

### A note on the JavaScript build

This repository began as a JavaScript/HTML5 game (`index.html`, `css/`, `js/`)
and was later ported to Godot. **The Godot build supersedes it** and is where all
new work goes.

The JS build has not been deleted yet, for two reasons:

1. **It is the leaderboard's verification engine.** The Supabase Edge Function
   replays every uploaded run through the JS physics (vendored by
   `tools/sync-physics.mjs`) rather than trusting a time sent by a client. That
   property depends on this code.
2. **It is the reference the port is checked against.** `godot/tools/parity.gd`
   compares the two builds number for number.

Until those are moved into the Godot build, `js/` stays. Do not add features to
it. See [`AGENTS.md`](AGENTS.md) for the full picture.

## Layout

| Path | What it is |
|---|---|
| `godot/` | **The game.** GDScript, scenes, assets, export presets, verifiers. |
| `js/`, `css/`, `index.html`, `sw.js` | Legacy JS build (verification engine + parity reference). |
| `supabase/` | Leaderboard schema and Edge Functions. |
| `tools/` | Dev harnesses for the JS build (tests, ghost baking, physics sync). |
| `android/` | Legacy WebView shell for the old JS APK. |
| `AGENTS.md` | Working notes for this repo: architecture, gotchas, rules. |

## Licensing

Car sprites are CC0 — see [`godot/assets/cars/CREDITS.md`](godot/assets/cars/CREDITS.md).
