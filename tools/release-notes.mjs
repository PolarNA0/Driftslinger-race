#!/usr/bin/env node
// Build release notes from the commits since the previous version tag.
//
//   node tools/release-notes.mjs                    # markdown to stdout
//   node tools/release-notes.mjs --out notes.md
//   node tools/release-notes.mjs --from v1.6
//
// The release body names the build version and a fingerprint of the physics the
// board verifies with. Until the physics is versioned (ROADMAP C1), the
// fingerprint is what tells a reader whether stored runs are still expected to
// reproduce; a tuning change moves it.

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (path) => readFileSync(join(root, path), 'utf8');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();

function arg(name) {
  const at = process.argv.indexOf(name);
  return at === -1 ? null : process.argv[at + 1];
}

const version = read('VERSION').trim();
const physicsFiles = ['config.js', 'util.js', 'track.js', 'car.js', 'tracks.js'];
const fingerprint = createHash('sha256')
  .update(physicsFiles.map((name) => read(`physics/${name}`)).join('\n'))
  .digest('hex')
  .slice(0, 12);

const previous = arg('--from') || git('tag', '--list', 'v*', '--sort=-v:refname').split('\n')[0] || null;
const range = previous ? `${previous}..HEAD` : 'HEAD';
const commits = git('log', range, '--pretty=format:%h%x09%s')
  .split('\n')
  .filter(Boolean)
  .map((line) => {
    const [hash, subject] = line.split('\t');
    return { hash, subject };
  });

const SECTIONS = [
  ['feat', 'Features'],
  ['fix', 'Fixes'],
  ['perf', 'Performance'],
  ['refactor', 'Refactors'],
  ['test', 'Tests'],
  ['docs', 'Docs'],
  ['ci', 'CI'],
  ['chore', 'Chores'],
];
const groups = new Map(SECTIONS.map(([, title]) => [title, []]));
const other = [];

// New commits should use a conventional prefix. Older history does not, so a
// verb fallback keeps those releases readable instead of dumping everything into
// "Other".
const FALLBACK = [
  [/^(add|implement|introduce|ship|start)\b/i, 'Features'],
  [/^(fix|stop|correct|repair|revert|close|avoid|prevent)\b/i, 'Fixes'],
  [/^(make|improve|speed|reduce|simplify|split|extract)\b/i, 'Refactors'],
  [/^(document|docs|write down|explain)\b/i, 'Docs'],
  [/^(test|verify|prove|cover)\b/i, 'Tests'],
  [/^(ci|gate|pin|workflow)\b/i, 'CI'],
];

for (const commit of commits) {
  const match = commit.subject.match(/^(\w+)(?:\([^)]*\))?!?:\s*(.*)$/);
  const kind = match ? match[1] : null;
  const body = match ? match[2] : commit.subject;
  const title =
    SECTIONS.find(([prefix]) => prefix === kind)?.[1] ??
    FALLBACK.find(([pattern]) => pattern.test(commit.subject))?.[1];
  const bullet = `- ${body} (${commit.hash})`;
  if (title) groups.get(title).push(bullet);
  else other.push(bullet);
}
if (other.length) groups.set('Other', other);

const lines = [
  `# Sling Drift ${version}`,
  '',
  `Physics fingerprint: \`${fingerprint}\``,
  '',
  `The board re-simulates every stored run with this physics. A different`,
  `fingerprint means old rows may not reproduce.`,
  '',
];
for (const [, title] of SECTIONS) {
  const bullets = groups.get(title);
  if (!bullets?.length) continue;
  lines.push(`## ${title}`, '', ...bullets, '');
}
if (groups.get('Other')?.length) {
  lines.push('## Other', '', ...groups.get('Other'), '');
}

const notes = lines.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
const out = arg('--out');
if (out) {
  writeFileSync(isAbsolute(out) ? out : join(root, out), notes);
  console.error(`wrote ${out} (${commits.length} commits since ${previous ?? 'the start'})`);
} else {
  process.stdout.write(notes);
}
