## What changed

<!-- One paragraph. Name the roadmap ID if there is one (A5, C1, ...). -->

## Checks

- [ ] `node tools/test.mjs`
- [ ] `node tools/sync-physics.mjs --check`
- [ ] `node tools/version.mjs --check`
- [ ] Godot verifiers run (CI runs all of them; say if you ran any locally)
- [ ] UI changed: `verify_ui` and/or `verify_editor` cover the new layout
- [ ] New behaviour has a headless proof, not only a screenshot

## If this touches the physics

<!-- See PHYSICS.md. Delete this section otherwise. -->

- [ ] Changed `cfg.gd`/`car.gd`/`track.gd`/`tracks.gd` and the JS equivalents together
- [ ] `node tools/sync-physics.mjs` re-vendored the copies
- [ ] Both suites green: `node tools/test.mjs` and `parity.gd` + the area verifiers
- [ ] At least three real board rows per affected track re-simulated with
      `node tools/replay-row.mjs`; results pasted here
- [ ] Decided: same physics, or a new physics version (C1). Stored runs that no
      longer reproduce were called out, not silently re-ranked.

| Track | Row (player / id) | Stored ticks | Replayed ticks |
|---|---|---|---|
|  |  |  |  |
