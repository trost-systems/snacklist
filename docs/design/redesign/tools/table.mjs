// Writes the measurement table into rd/RECOMMENDATION.md and .de.md (between <!-- table --> and <!-- /table -->)
// from rd/measured.json, so the docs quote what verify.mjs measured. Usage: node tools/table.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { options } from '../options.js';
import { pick, runnerUp } from '../recommend.js';
import { pathOf, taps } from '../places.js';
import process from 'node:process';

const here = dirname(fileURLToPath(import.meta.url));
const cost = {
  en: { none: 'today', tokens: 'cheap (tokens only)', widgets: 'medium (widgets)', structure: 'structural' },
  de: { none: 'heute', tokens: 'günstig (nur Tokens)', widgets: 'mittel (Widgets)', structure: 'strukturell' },
};
const head = {
  en: '| Option | Cost | Whole rows, 100 % | Whole rows, 310 % | Smallest tap target | Lowest text contrast, light / dark | Lowest border contrast, light / dark | Overflows at 310 % | Words broken at 310 % |',
  de: '| Option | Aufwand | Ganze Zeilen, 100 % | Ganze Zeilen, 310 % | Kleinstes Tippziel | Niedrigster Textkontrast, hell / dunkel | Niedrigster Randkontrast, hell / dunkel | Überläufe bei 310 % | Getrennte Wörter bei 310 % |',
};
const n = (lang, x) => (x === null ? '–' : lang === 'de' ? String(x).replace('.', ',') : String(x));
// Taps from the list to each place, from places.js.
export const tapCols = [
  { dest: 'history', en: 'History', de: 'Verlauf' },
  { dest: 'edit', en: 'Edit (stores)', de: 'Anpassen (Läden)' },
  { dest: 'trip', en: 'Start a trip', de: 'Einkauf starten' },
  { dest: 'account', en: 'Account', de: 'Konto' },
  { dest: 'settings', en: 'Settings', de: 'Einstellungen' },
  { dest: 'imprint', en: 'Imprint', de: 'Impressum' },
  { dest: 'signout', en: 'Sign out', de: 'Abmelden' },
  { dest: 'list', en: 'Another list', de: 'Andere Liste' },
];
const firstStep = {
  en: { 'History tab': 'tab bar', 'More tab': 'tab bar', 'Stores tab': 'tab bar', Edit: 'top bar', menu: 'menu button, bottom', drawer: 'menu button, top', title: 'title, top', avatars: 'avatars, top', '•••': '••• button, top', 'History segment': 'segments, top', switcher: 'switcher, top' },
  de: { 'History tab': 'Tab-Leiste', 'More tab': 'Tab-Leiste', 'Stores tab': 'Tab-Leiste', Edit: 'obere Leiste', menu: 'Menü-Knopf, unten', drawer: 'Menü-Knopf, oben', title: 'Titel, oben', avatars: 'Avatare, oben', '•••': '•••-Knopf, oben', 'History segment': 'Segmente, oben', switcher: 'Umschalter, oben' },
};
export const tapsTable = (lang) => {
  const headRow = `| Option | ${tapCols.map((c) => c[lang]).join(' | ')} | ${lang === 'de' ? 'Konto & Co. öffnen von' : 'Account and the rest open from'} |`;
  const rows = options.map((o) => `| ${o.id === 'today' ? o.name[lang] : o.id} | ${tapCols.map((c) => taps(o, c.dest)).join(' | ')} | ${firstStep[lang][pathOf(o, 'account')[0]]} |`);
  return [headRow, `|${' --- |'.repeat(tapCols.length + 2)}`, ...rows].join('\n');
};
const table = (summary, lang) => [head[lang], `|${' --- |'.repeat(9)}`, ...options.map((o) => {
  const m = summary[o.id];
  const name = o.id === 'today' ? o.name[lang] : `${o.id} ${o.name[lang]}`;
  const label = o.id === pick ? `**${name}**` : name;
  const tag = o.id === runnerUp ? (lang === 'de' ? ' (zweite Wahl)' : ' (runner-up)') : '';
  return `| ${label}${tag} | ${cost[lang][o.cost]} | ${m.rows100} | ${m.rows310} | ${n(lang, m.minTap)} px | ${n(lang, m.contrastLight)} / ${n(lang, m.contrastDark)} | ${n(lang, m.uiLight)} / ${n(lang, m.uiDark)} | ${m.overflow310} | ${m.broken310} |`;
})].join('\n');
if (process.argv[1] === fileURLToPath(import.meta.url)) for (const [file, lang] of [['RECOMMENDATION.md', 'en'], ['RECOMMENDATION.de.md', 'de']]) {
  const { summary } = JSON.parse(readFileSync(join(here, '../rd/measured.json'), 'utf8'));
  const p = join(here, '../rd', file);
  const src = readFileSync(p, 'utf8');
  const out = src.replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, `<!-- table -->\n${table(summary, lang)}\n<!-- /table -->`)
    .replace(/<!-- taps -->[\s\S]*?<!-- \/taps -->/, `<!-- taps -->\n${tapsTable(lang)}\n<!-- /taps -->`);
  writeFileSync(p, out);
  console.log(`${file}: table ${out === src ? 'unchanged' : 'written'}`);
}
