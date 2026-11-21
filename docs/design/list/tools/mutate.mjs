// Breaks the round on purpose, one mutation at a time, in a built copy, and records which verify.mjs checks fail
// (ru/MUTATIONS.md). A mutation no check catches fails this script.
// Usage: node tools/mutate.mjs
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

const here = dirname(fileURLToPath(import.meta.url));
const edit = (file, from, to) => (dir) => {
  const p = join(dir, 'list', file);
  const src = readFileSync(p, 'utf8');
  if (!src.includes(from)) throw new Error(`${file}: no ${from}`);
  writeFileSync(p, src.replace(from, to));
};
const mutations = [
  ['RU3 starts collapsed (its chips hidden)', edit('options.js', '<div class="rchips">', '<div class="rchips" style="display:none">')],
  ['A tap-back puts the item at the end of the list', edit('model.js', '.sort((a, b) => byId[a].rank - byId[b].rank)', '')],
  ['One measured number changed (en ios 100 short-3 RU1 active 5 → 6)', (dir) => {
    const p = join(dir, 'list/ru/measured.json');
    const m = JSON.parse(readFileSync(p, 'utf8'));
    m.en.ios[100]['short-3'].RU1.active += 1;
    writeFileSync(p, JSON.stringify(m, null, 1));
  }],
  ['RU2’s peek pill holds the second-newest item', edit('options.js', 'const item = byId[s.recent[0]];', 'const item = byId[s.recent[1] ?? s.recent[0]];')],
  ['RU3’s chips get a hexagon cell', edit('options.js', '${cell(item)}<span>${q}', '<i class="hexcell"></i>${cell(item)}<span>${q}')],
  ['A tick appends to the end of Recently used', edit('model.js', 's.recent = [arg, ...s.recent.filter((x) => x !== arg)].slice(0, recentLimit);', 's.recent = [...s.recent.filter((x) => x !== arg), arg].slice(0, recentLimit);')],
];

const rows = [];
let missed = 0;
for (const [name, apply] of mutations) {
  const tmp = mkdtempSync(join(tmpdir(), 'ru-mut-'));
  execFileSync('bash', [join(here, '../build.sh'), tmp], { stdio: 'ignore' });
  apply(tmp);
  const r = spawnSync('node', [join(here, '../verify.mjs'), '--dir', tmp, '--path', '/list/'], { encoding: 'utf8' });
  const fails = r.stdout.split('\n').filter((l) => l.startsWith('FAIL ')).map((l) => l.slice(5).split(' -- ')[0]);
  rmSync(tmp, { recursive: true, force: true });
  if (!fails.length) missed += 1;
  rows.push(`| ${name} | ${fails.length ? fails.map((f) => f.replace(/\|/g, '/')).join('; ') : '**none: not caught**'} |`);
  console.log(`${name}: ${fails.length} checks fail`);
}
writeFileSync(join(here, '../ru/MUTATIONS.md'), `# Mutations (round RU)

\`node docs/design/list/tools/mutate.mjs\` builds the round into a temporary folder, applies one mutation, runs
\`verify.mjs\` on it, and lists the checks that failed. Every mutation must fail at least one check.

| Mutation | Checks that fail |
| --- | --- |
${rows.join('\n')}
`);
process.exit(missed ? 1 : 0);
