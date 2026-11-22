// Adds round AI to the preview root's overview (rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../app-icon/ai/',
    blurb: { en: 'Five app icons without the hexagon, in RD1’s colours and shapes, on home screens, in small sizes and store listings, measured.', de: 'Fünf App-Icons ohne Sechseck, in RD1s Farben und Formen, auf Home-Bildschirmen, in kleinen Größen und Store-Einträgen, gemessen.' },
    date: { en: 'Nov 22', de: '22. Nov.' },
    title: { en: 'App icon without the hexagon (AI1–AI5)', de: 'App-Icon ohne Sechseck (AI1–AI5)' },
  },
`;
if (src.includes("href: '../app-icon/ai/'")) {
  console.log('overview already links round AI');
} else {
  const head = 'export const linked = [\n';
  const at = src.indexOf(head);
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  writeFileSync(file, src.slice(0, at + head.length) + entry + src.slice(at + head.length));
  console.log('overview links round AI');
}
