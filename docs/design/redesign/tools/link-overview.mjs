// Adds round RD to the preview root's overview (#414's rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../redesign/rd/',
    blurb: { en: 'Ten designs away from the hexagons: corner radii, the menu, rows, ticks and type, on today’s colours.', de: 'Zehn Designs weg von den Sechsecken: Eckenrundung, Menü, Zeilen, Haken und Schrift, in den heutigen Farben.' },
    date: { en: 'Nov 21', de: '21. Nov.' },
    title: { en: 'Snacklist without hexagons (RD1–RD10)', de: 'Snacklist ohne Sechsecke (RD1–RD10)' },
  },
`;
if (src.includes("href: '../redesign/rd/'")) {
  console.log('overview already links round RD');
} else {
  const at = src.indexOf('export const linked = [\n');
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  const pos = at + 'export const linked = [\n'.length;
  writeFileSync(file, src.slice(0, pos) + entry + src.slice(pos));
  console.log('overview links round RD');
}
