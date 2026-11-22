// Adds round SC to the preview root's overview (rounds.js, the `linked` list, newest first). Idempotent.
// Usage: node link-overview.mjs <out dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const file = join(process.argv[2], 'rounds.js');
const src = readFileSync(file, 'utf8');
const entry = `  {
    href: '../store-card/sc/',
    blurb: { en: 'Five cards for the top of the list once a store’s last item is ticked and its “Open app” key is gone: what helps at the till, measured.', de: 'Fünf Karten oben in der Liste, wenn der letzte Artikel eines Ladens abgehakt ist und sein „App öffnen“-Knopf fehlt: was an der Kasse hilft, gemessen.' },
    date: { en: 'Nov 22', de: '22. Nov.' },
    title: { en: 'After a store’s last item: the card (SC1–SC5)', de: 'Nach dem letzten Artikel eines Ladens: die Karte (SC1–SC5)' },
  },
`;
if (src.includes("href: '../store-card/sc/'")) {
  console.log('overview already links round SC');
} else {
  const at = src.indexOf('export const linked = [\n');
  if (at < 0) throw new Error('rounds.js has no `linked` list');
  const pos = at + 'export const linked = [\n'.length;
  writeFileSync(file, src.slice(0, pos) + entry + src.slice(pos));
  console.log('overview links round SC');
}
