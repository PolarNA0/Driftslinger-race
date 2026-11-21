#!/usr/bin/env node
// Docs drift check.
//
// Documentation is only worth having if it is true. This catches the three
// kinds of drift that have actually happened here:
//
//   1. a sentence that describes a feature that has since shipped or changed
//      ("endless leaderboards should be added soon", the old Tracks button);
//   2. a verifier that exists but is not run in CI or not listed in
//      godot/README.md, so it quietly stops protecting anything;
//   3. a path in a layout table that no longer exists.
//
// It is deliberately narrow. It cannot tell whether prose is *correct*, only
// that the specific traps we have hit are not back.
//
//   node tools/docs-check.mjs

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (path) => readFileSync(join(root, path), 'utf8');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? 'ok  ' : 'FAIL'}  ${label}${detail ? `  (${detail})` : ''}`);
  if (!cond) failures++;
};

// ROADMAP.md is excluded: it quotes the old wording on purpose, as history.
const DOCS = ['README.md', 'AGENTS.md', 'PHYSICS.md', 'godot/README.md'];
const STALE = [
  ['should be added soon', 'the endless board shipped in 0005'],
  ['**Tracks** button', 'the track chooser is a grid on the Play tab'],
  ['players x 25', 'the playable set is derived from the track tables'],
  ['Play/Garage/Account', 'the shell has four tabs'],
  ['Build / Look / Help pages', 'the editor is a palette and a map, not pages'],
];

for (const doc of DOCS) {
  const text = read(doc);
  for (const [phrase, why] of STALE) {
    check(`${doc} does not say "${phrase}"`, !text.includes(phrase), why);
  }
}

// Every verifier is run by CI and named in the build's README. A verifier that
// exists but is not wired up protects nothing.
const verifiers = readdirSync(join(root, 'godot/tools'))
  .filter((name) => /^verify_.*\.gd$/.test(name))
  .sort();
const workflow = read('.github/workflows/verify.yml');
const godotReadme = read('godot/README.md');
for (const file of verifiers) {
  const script = file.replace(/\.gd$/, '');
  check(`CI runs ${script}`, workflow.includes(script));
  check(`godot/README.md lists ${script}`, godotReadme.includes(script));
}

// Paths in a layout table must exist. README.md paths are repo-relative;
// godot/README.md's Layout table is relative to godot/.
function layoutPaths(doc, base) {
  const paths = [];
  for (const line of read(doc).split('\n')) {
    const match = line.match(/^\|\s*`([^`]+)`\s*\|/);
    if (!match) continue;
    const path = match[1];
    // The first cell of a "File | Ports" row is a filename, which is the point.
    paths.push({ path, exists: existsSync(join(root, base, path)) });
  }
  return paths;
}

for (const [doc, base] of [
  ['README.md', ''],
  ['godot/README.md', 'godot'],
]) {
  const paths = layoutPaths(doc, base);
  check(`${doc} has a layout table`, paths.length > 0);
  for (const { path, exists } of paths) {
    check(`${doc} path exists: ${path}`, exists);
  }
}

// The daily challenge is a shipped mode, so its model, verifier and docs must
// stay together.
check('daily challenge model exists', existsSync(join(root, 'godot/scripts/daily.gd')));
check('daily challenge verifier exists', existsSync(join(root, 'godot/tools/verify_daily.gd')));
check('AGENTS documents the daily challenge', read('AGENTS.md').includes('## The daily challenge'));
check('Makefile runs verify_daily', read('Makefile').includes('verify_daily'));

// While a deploy is pending, the handoff note must be reachable from the two
// files an agent reads first. Once it is applied and the file is deleted, this
// check disappears with it.
if (existsSync(join(root, 'DEPLOY_PENDING.md'))) {
  check('AGENTS.md points at DEPLOY_PENDING.md', read('AGENTS.md').includes('DEPLOY_PENDING.md'));
  check('ROADMAP.md points at DEPLOY_PENDING.md', read('ROADMAP.md').includes('DEPLOY_PENDING.md'));
}

// The endless tracker is server-only: no Godot verifier can see it. Check the
// pieces that have to agree, so a refactor cannot silently drop the announcement.
const runFn = read('supabase/functions/run/index.ts');
const trackerFn = read('supabase/functions/_shared/tracker.ts');
check('run announces endless improvements', runFn.includes('announceEndless({'));
check('tracker has an endless position template', trackerFn.includes('DEFAULT_ENDLESS_MESSAGE'));
check('tracker has an endless lead template', trackerFn.includes('DEFAULT_ENDLESS_RECORD_MESSAGE'));
check('0007 adds the endless tracker columns', existsSync(join(root, 'supabase/migrations/0007_endless_tracker.sql')));

// The top-level README must point at the two documents that keep the project
// honest.
const readme = read('README.md');
check('README points at ROADMAP.md', readme.includes('ROADMAP.md'));
check('README points at UI_REDESIGN.md', readme.includes('UI_REDESIGN.md'));
check('README points at PHYSICS.md', readme.includes('PHYSICS.md'));

console.log(failures === 0 ? 'DOCS PASS' : `DOCS FAIL (${failures})`);
process.exit(failures === 0 ? 0 : 1);
