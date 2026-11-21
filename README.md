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

This repository began as a JavaScript/HTML5 game and was later ported to Godot.
**The Godot build supersedes it** and is where all new work goes. The JS client
has been removed.

One piece of JavaScript remains: `physics/`. It is kept for exactly one reason —
**it is the leaderboard's verification engine.** The Supabase Edge Function
replays every uploaded run through this physics (vendored by
`tools/sync-physics.mjs`) rather than trusting a time sent by a client, and
`godot/tools/parity.gd` checks the Godot port against the numbers it produces.
`node tools/test.mjs` covers it.

See [`AGENTS.md`](AGENTS.md) for the full picture.

## Layout

| Path | What it is |
|---|---|
| `godot/` | **The game.** GDScript, scenes, assets, export presets, verifiers. |
| `physics/` | The JS physics the server verifies runs with. Not a client. |
| `supabase/` | Leaderboard schema and Edge Functions. |
| `tools/` | `test.mjs` (physics + server verifier), `sync-physics.mjs`, `version.mjs`, `replay-row.mjs`, `smoke.mjs`. |
| `AGENTS.md` | Working notes for this repo: architecture, gotchas, rules. |
| `PHYSICS.md` | The checklist for any change to the physics the board verifies. |
| `ROADMAP.md` | The forward plan, with acceptance tests and shipped notes. |

## Licensing

The code is MIT — see [`LICENSE`](LICENSE). Bundled art and audio are CC0 1.0:
see [`godot/assets/cars/CREDITS.md`](godot/assets/cars/CREDITS.md) and
[`godot/assets/audio/CREDITS.md`](godot/assets/audio/CREDITS.md).

