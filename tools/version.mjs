#!/usr/bin/env node
// One source of version truth.
//
// The build version used to live in three places that drifted apart: the game
// reported 1.6 while the Android preset still said 1.3. `VERSION` is now the
// single source; this script writes the other two from it and fails if they
// disagree, so CI catches a partial bump.
//
//   node tools/version.mjs                 # print the version and where it is used
//   node tools/version.mjs --check         # exit 1 if any copy disagrees
//   node tools/version.mjs --set 1.8       # bump all three, increment version/code

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const versionPath = join(root, "VERSION");
const appPath = join(root, "godot", "scripts", "app.gd");
const presetsPath = join(root, "godot", "export_presets.cfg");

const SEMVER = /^\d+\.\d+(?:\.\d+)?$/;

function read(path) {
  return readFileSync(path, "utf8");
}

function readVersion() {
  const version = read(versionPath).trim();
  if (!SEMVER.test(version)) {
    fail(`VERSION is not a version number: ${JSON.stringify(version)}`);
  }
  return version;
}

function fail(message) {
  console.error(`version: ${message}`);
  process.exit(1);
}

// Each location is a regex with one capture group holding the current value.
const copies = [
  {
    path: appPath,
    label: "godot/scripts/app.gd App.VERSION",
    pattern: /^const VERSION := "([^"]+)"/m,
    replace: (src, v) => src.replace(/^const VERSION := "[^"]+"/m, `const VERSION := "${v}"`),
  },
  {
    path: presetsPath,
    label: "godot/export_presets.cfg version/name",
    pattern: /^version\/name="([^"]+)"/m,
    replace: (src, v) => src.replace(/^version\/name="[^"]+"/m, `version/name="${v}"`),
  },
];

function current() {
  const version = readVersion();
  const found = copies.map((copy) => {
    const match = read(copy.path).match(copy.pattern);
    if (!match) fail(`cannot find ${copy.label}`);
    return { ...copy, value: match[1] };
  });
  const codeMatch = read(presetsPath).match(/^version\/code=(\d+)/m);
  if (!codeMatch) fail("cannot find godot/export_presets.cfg version/code");
  return { version, found, code: Number(codeMatch[1]) };
}

function check() {
  const { version, found } = current();
  const bad = found.filter((copy) => copy.value !== version);
  for (const copy of found) {
    const state = copy.value === version ? "ok" : "MISMATCH";
    console.log(`${state.padEnd(8)} ${copy.label}: ${copy.value}`);
  }
  if (bad.length > 0) {
    fail(`VERSION is ${version} but ${bad.length} copy/copies disagree; run "node tools/version.mjs --set ${version}"`);
  }
  console.log(`version: ${version} is consistent everywhere`);
}

function set(next) {
  if (!SEMVER.test(next)) fail(`not a version number: ${JSON.stringify(next)}`);
  const { code } = current();
  writeFileSync(versionPath, `${next}\n`);
  for (const copy of copies) {
    writeFileSync(copy.path, copy.replace(read(copy.path), next));
  }
  writeFileSync(presetsPath, read(presetsPath).replace(/^version\/code=\d+/m, `version/code=${code + 1}`));
  console.log(`version: set ${next} (version/code ${code} -> ${code + 1})`);
}

const [flag, value] = process.argv.slice(2);
if (flag === "--check") {
  check();
} else if (flag === "--set") {
  if (!value) fail("--set needs a version, e.g. --set 1.8");
  set(value);
} else if (flag) {
  fail(`unknown argument: ${flag}`);
} else {
  const { version, found, code } = current();
  console.log(`version: ${version} (version/code ${code})`);
  for (const copy of found) console.log(`  ${copy.label}: ${copy.value}`);
}
