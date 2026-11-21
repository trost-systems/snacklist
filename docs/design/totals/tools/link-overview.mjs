// Adds round TE to the preview root's overview (#414's rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../totals/te/',
    blurb: { en: 'Five ways to show the shopping total when no item or only some items have a price.', de: 'Fünf Wege, die Einkaufssumme zu zeigen, wenn kein Artikel oder nur einige einen Preis haben.' },
    date: { en: 'Nov 21', de: '21. Nov.' },
    title: { en: 'Totals with missing prices (TE1–TE5)', de: 'Summen mit fehlenden Preisen (TE1–TE5)' },
  },
`;
if (src.includes("href: '../totals/te/'")) {
  console.log('overview already links round TE');
} else {
  const at = src.indexOf('export const linked = [\n');
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  const pos = at + 'export const linked = [\n'.length;
  writeFileSync(file, src.slice(0, pos) + entry + src.slice(pos));
  console.log('overview links round TE');
}
