#!/usr/bin/env node
// Compares two runs by their manifests: which files are byte-identical, which differ, which only
// one run has. Exit 1 on any difference in the files both runs made, or when one run made files
// the other lacks for a locale both covered.
//
//   node compare.mjs <old manifest.json> [new manifest.json, default out/manifest.json]
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const [a, b = join(import.meta.dirname, 'out/manifest.json')] = process.argv.slice(2);
if (!a) {
  console.error('usage: compare.mjs <old manifest.json> [new manifest.json]');
  process.exit(64);
}
const load = (f) => new Map(JSON.parse(readFileSync(f, 'utf8')).files.map((x) => [x.file, x.sha256]));
const before = load(a);
const after = load(b);
const locale = (f) => f.split('/')[0];
const shared = new Set([...before.keys()].map(locale).filter((l) => [...after.keys()].some((f) => locale(f) === l)));
const same = [...after].filter(([f, h]) => before.get(f) === h).map(([f]) => f);
const changed = [...after].filter(([f, h]) => before.has(f) && before.get(f) !== h).map(([f]) => f);
const added = [...after.keys()].filter((f) => !before.has(f) && shared.has(locale(f)));
const gone = [...before.keys()].filter((f) => !after.has(f) && shared.has(locale(f)));
console.log(`${same.length} of ${same.length + changed.length} files both runs made are identical`);
for (const [label, list] of [['changed', changed], ['only in the new run', added], ['only in the old run', gone]]) {
  for (const f of list) console.log(`${label}: ${f}`);
}
process.exit(changed.length || added.length || gone.length ? 1 : 0);
