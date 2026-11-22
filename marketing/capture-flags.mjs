#!/usr/bin/env node
// The flags every marketing capture builds with (store screenshots, demo videos, the hero):
// the flags releases/flags.json rolls out in full, minus marketing/CAPTURE_FLAGS_OFF, plus
// marketing/CAPTURE_FLAGS. A flag stays off even once flags.json turns it off itself.
//
//   node marketing/capture-flags.mjs                      prints the FLAGS_ON list
//   node marketing/capture-flags.mjs --check <FLAGS_ON>    exits 1 when the list holds a
//                                                         CAPTURE_FLAGS_OFF flag or misses a CAPTURE_FLAGS one
//   node marketing/capture-flags.mjs --check-build <file>  the same for the FLAGS_ON compiled into a
//                                                         build (main.dart.wasm, main.dart.js, libapp.so)
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const here = import.meta.dirname;
// One flag per line or comma-separated; # starts a comment.
const names = (file) => readFileSync(join(here, file), 'utf8').split('\n').flatMap((l) => l.replace(/#.*/, '').split(',')).map((s) => s.trim()).filter(Boolean);

const { flags } = JSON.parse(readFileSync(join(here, '../releases/flags.json'), 'utf8'));
const on = names('CAPTURE_FLAGS');
const off = names('CAPTURE_FLAGS_OFF');
for (const k of [...on, ...off]) if (!flags[k]) throw new Error(`capture flags: ${k} is not a flag in releases/flags.json`);
const both = on.filter((k) => off.includes(k));
if (both.length) throw new Error(`capture flags: ${both.join(', ')} in both CAPTURE_FLAGS and CAPTURE_FLAGS_OFF`);

/** What is wrong with a FLAGS_ON list, if anything. */
function problems(list) {
  const built = list.split(',').map((s) => s.trim());
  return [
    ...off.filter((k) => built.includes(k)).map((k) => `${k} is on (marketing/CAPTURE_FLAGS_OFF)`),
    ...on.filter((k) => !built.includes(k)).map((k) => `${k} is off (marketing/CAPTURE_FLAGS)`),
  ];
}

/** The FLAGS_ON literal compiled into a build: the one comma list of flag names holding a CAPTURE_FLAGS flag. */
function compiledFlags(file) {
  const lists = new Set(readFileSync(file, 'latin1').match(/[a-z0-9-]+(,[a-z0-9-]+)+/g) ?? []);
  const found = [...lists].filter((l) => l.split(',').some((k) => on.includes(k)));
  if (found.length !== 1) throw new Error(`capture flags: ${file} holds ${found.length} FLAGS_ON lists, expected 1${found.length ? `: ${found.join(' | ')}` : ''}`);
  return found[0];
}

const [mode, ...args] = process.argv.slice(2);
if (mode === '--check' || mode === '--check-build') {
  const lists = mode === '--check' ? [[args[0] ?? '', 'FLAGS_ON']] : args.map((f) => [compiledFlags(f), f]);
  const wrong = lists.flatMap(([list, where]) => problems(list).map((p) => `${where}: ${p}`));
  if (wrong.length) {
    console.error(`capture flags: not the launch build: ${wrong.join('; ')}`);
    process.exit(1);
  }
} else {
  const full = Object.keys(flags).filter((k) => flags[k].rollout === 'full' && !off.includes(k));
  console.log([...new Set([...full, ...on])].join(','));
}
