// Adds round IO to the preview root's overview (#414's rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../order/io/',
    blurb: { en: 'Five list views that put items in walking order with little or no category noise, and how people and agents reorder.', de: 'Fünf Listenansichten, die Artikel in Laufweg-Reihenfolge zeigen, mit wenig oder ohne Kategorien, und wie Menschen und Agenten umsortieren.' },
    date: { en: 'Nov 21', de: '21. Nov.' },
    title: { en: 'Items in the right order (IO1–IO5)', de: 'Artikel in der richtigen Reihenfolge (IO1–IO5)' },
  },
`;
if (src.includes("href: '../order/io/'")) {
  console.log('overview already links round IO');
} else {
  const at = src.indexOf('export const linked = [\n');
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  const pos = at + 'export const linked = [\n'.length;
  writeFileSync(file, src.slice(0, pos) + entry + src.slice(pos));
  console.log('overview links round IO');
}
