# Sling Drift

A one-button car-drifting game. Hold to sling the car round a pillar, let go to
fly straight to the next one. Leave the road and the run ends.

Two modes, plus a daily challenge:

- **Speedrun** — a finite ~10s track, scored by time.
- **Endless** — an infinite road, scored by distance in metres.
- **Daily challenge** — one track and one modifier (mirror, or no reattach on a
  reattach track), the same for everyone on the same UTC date. It is local-only:
  the run is saved on the device and never uploaded.

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

## Verifying

```sh
make setup     # once: the pinned Godot + export templates (Linux x86_64)
make check     # every JS and Godot check
```

`make test` is the JavaScript half (physics, vendored copies, version, docs);
`make verify` is every Godot verifier; `make web` and `make apk` export. CI runs
the same checks in `.github/workflows/verify.yml`, plus the tracker SQL test on a
postgres service.

The forward plan and the shipped notes live in [`ROADMAP.md`](ROADMAP.md). Any
change to the physics follows [`PHYSICS.md`](PHYSICS.md), because the leaderboard
re-simulates every stored run.

## Layout

| Path | What it is |
|---|---|
| `godot/` | **The game.** GDScript, scenes, assets, export presets, verifiers. |
| `physics/` | The JS physics the server verifies runs with. Not a client. |
| `supabase/` | Leaderboard schema and Edge Functions. |
| `tools/` | `test.mjs` (physics + server verifier), `sync-physics.mjs`, `version.mjs`, `docs-check.mjs`, `replay-row.mjs`, `smoke.mjs`, `release-notes.mjs`. |
| `AGENTS.md` | Working notes for this repo: architecture, gotchas, rules. |
| `PHYSICS.md` | The checklist for any change to the physics the board verifies. |
| `ROADMAP.md` | The forward plan, with acceptance tests and shipped notes. |
| `UI_REDESIGN.md` | The proposed UI redesign: research, tokens, screen specs and phases. |
| `Makefile` | `make check`, `verify`, `web`, `apk`, `setup`. |
| `toolchain.json` | The pinned Godot, Node and Supabase CLI versions. `node tools/toolchain.mjs --check` enforces it. |

## Licensing

The code is MIT — see [`LICENSE`](LICENSE). Bundled art and audio are CC0 1.0:
see [`godot/assets/cars/CREDITS.md`](godot/assets/cars/CREDITS.md) and
[`godot/assets/audio/CREDITS.md`](godot/assets/audio/CREDITS.md).

