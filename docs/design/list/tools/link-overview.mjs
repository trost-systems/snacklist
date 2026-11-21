// Adds round RU to the preview root's overview (#414's rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../list/ru/',
    blurb: { en: 'Four ways to keep Recently used open under the list and set it apart, so a tick visibly lands there and one tap brings an item back.', de: 'Vier Wege, „Zuletzt verwendet“ unter der Liste offen zu halten und abzusetzen, damit ein Haken sichtbar dort landet und ein Tipp den Artikel zurückholt.' },
    date: { en: 'Nov 21', de: '21. Nov.' },
    title: { en: 'Recently used, expanded (RU1–RU4)', de: 'Zuletzt verwendet, aufgeklappt (RU1–RU4)' },
  },
`;
if (src.includes("href: '../list/ru/'")) {
  console.log('overview already links round RU');
} else {
  const at = src.indexOf('export const linked = [\n');
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  const pos = at + 'export const linked = [\n'.length;
  writeFileSync(file, src.slice(0, pos) + entry + src.slice(pos));
  console.log('overview links round RU');
}
