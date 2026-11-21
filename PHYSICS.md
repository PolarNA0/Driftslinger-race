# Changing the physics

The physics is the game's contract with the leaderboard. A submitted run is a
string of button steps; the server replays those steps through the same physics
the client runs and stores the resulting tick count. That only works if a given
step sequence keeps producing the same run forever.

So a physics change is not an ordinary change. It is either a change that leaves
every stored run intact, or it is a new game, and the old runs have to be kept
separately. There is no third option.

## What counts as a physics change

Any edit to:

- `godot/scripts/cfg.gd`, `godot/scripts/car.gd`, `godot/scripts/track.gd`,
  `godot/scripts/tracks.gd`
- `physics/config.js`, `physics/car.js`, `physics/track.js`, `physics/tracks.js`
- `supabase/functions/_shared/physics/verify.js` (the replay loop itself)

`tools/sync-physics.mjs` vendors the five shared modules, so the Godot and JS
numbers must be changed together and re-synced.

## The checklist

Every physics pull request does all of this, and the PR body records it:

1. **Change both sides together.** Edit the GDScript and the JavaScript. Run
   `node tools/sync-physics.mjs` so the vendored copy matches.
2. **Run both suites.** The game and the server must agree:

   ```sh
   node tools/test.mjs
   godot --headless --path godot --script res://tools/parity.gd
   ```

   Then the verifiers for the areas touched: `verify_tracks`, `verify_reattach`,
   `verify_endless`, `verify_guard` and `verify_board` at minimum. `verify_guard`
   is not optional - it is the proof that holding and mashing still lose.
3. **Re-simulate real board rows.** Pick at least three stored runs on each
   affected track and replay them on the new physics:

   ```sh
   node tools/replay-row.mjs --track 28 --steps <steps> --ticks <stored ticks>
   ```

   Record the result in the PR: run id or player, stored ticks, replayed ticks.
   A row that no longer reproduces is the signal that this is a different game.
4. **Decide: same physics or a new version.** If every recorded row still
   reproduces, the change is compatible and can ship. If any row changes, the
   change is a new physics version (C1 in `ROADMAP.md`): stored runs are kept
   verifiable against the old numbers and the board shows which version a row was
   run on. Do not silently re-rank a board that was set on different physics.
5. **Do not tune to a row.** If a change makes one real run pass but shifts
   others, the numbers are wrong. Revert and start again.

## Why the golden numbers do not catch everything

`tools/parity.gd` and `tools/test.mjs` pin the *shared* numbers: the road, the
car and the guard. They do not pin every tunable. A change to
`REATTACH_BOOST_MAX` or `REATTACH_EFFECT_TIME` passes both suites and still moves
a real line; the recorded 9.925 on track 28 re-simulates to 1191 ticks on the
shipped numbers and leaves the road under a front-loaded boost curve. That is why
step 3 exists.

## Server side

The `run` Edge Function replays through the vendored copy. After any physics
change, deploy the function before the client build that depends on it, or a run
the new client considers valid is refused. `tools/sync-physics.mjs --check` in CI
fails if the vendored copy was forgotten.
