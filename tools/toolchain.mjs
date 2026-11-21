#!/usr/bin/env node
// One source for the build toolchain.
//
// Godot was pinned in four places (three workflows and the setup script), Node
// in three, and the Supabase CLI was `latest`. A bump was a scavenger hunt, and
// a missed copy meant CI and a developer's machine built different things.
//
//   node tools/toolchain.mjs          # print the versions
//   node tools/toolchain.mjs --check  # fail if anything hardcodes them instead
//
// A bump is one edit to toolchain.json (and .nvmrc for Node, which setup-node
// reads directly).

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (path) => readFileSync(join(root, path), 'utf8');

const toolchain = JSON.parse(read('toolchain.json'));
const REQUIRED = ['godot', 'godot_templates', 'node', 'supabase_cli'];

if (!process.argv.includes('--check')) {
  for (const key of REQUIRED) console.log(`${key.padEnd(16)} ${toolchain[key]}`);
  process.exit(0);
}

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? 'ok  ' : 'FAIL'}  ${label}${detail ? `  (${detail})` : ''}`);
  if (!cond) failures++;
};

for (const key of REQUIRED) check(`toolchain.json has ${key}`, Boolean(toolchain[key]));

const derivedTemplates = String(toolchain.godot).replace(/-stable$/, '.stable');
check(
  'godot_templates matches godot',
  toolchain.godot_templates === derivedTemplates,
  `expected ${derivedTemplates}`,
);
check('.nvmrc matches toolchain.node', read('.nvmrc').trim() === String(toolchain.node));

// A version that appears literally outside toolchain.json is a copy that will
// go stale. Allow it only in the file itself and in prose (the docs may name a
// version, but workflows and scripts must not).
const SOURCES = [
  ...readdirSync(join(root, '.github/workflows'))
    .filter((name) => /\.ya?ml$/.test(name))
    .map((name) => `.github/workflows/${name}`),
  'tools/dev-setup.sh',
  'Makefile',
];
for (const file of SOURCES) {
  if (!existsSync(join(root, file))) continue;
  const text = read(file);
  for (const key of ['godot', 'godot_templates', 'supabase_cli']) {
    check(`${file} does not hardcode ${toolchain[key]}`, !text.includes(toolchain[key]));
  }
  check(`${file} does not set node-version directly`, !/node-version:\s*["']?\d/.test(text));
}

console.log(failures === 0 ? 'TOOLCHAIN PASS' : `TOOLCHAIN FAIL (${failures})`);
process.exit(failures === 0 ? 0 : 1);
