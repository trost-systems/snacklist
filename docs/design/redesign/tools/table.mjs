// Writes the measurement table into rd/RECOMMENDATION.md and .de.md (between <!-- table --> and <!-- /table -->)
// from rd/measured.json, so the docs quote what verify.mjs measured. Usage: node tools/table.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { options } from '../options.js';
import { pick, runnerUp } from '../recommend.js';

const here = dirname(fileURLToPath(import.meta.url));
const { summary } = JSON.parse(readFileSync(join(here, '../rd/measured.json'), 'utf8'));
const cost = {
  en: { none: 'today', tokens: 'cheap (tokens only)', widgets: 'medium (widgets)', structure: 'structural' },
  de: { none: 'heute', tokens: 'günstig (nur Tokens)', widgets: 'mittel (Widgets)', structure: 'strukturell' },
};
const head = {
  en: '| Option | Cost | Whole rows, 100 % | Whole rows, 310 % | Smallest tap target | Lowest text contrast, light / dark | Lowest border contrast, light / dark | Overflows at 310 % | Words broken at 310 % |',
  de: '| Option | Aufwand | Ganze Zeilen, 100 % | Ganze Zeilen, 310 % | Kleinstes Tippziel | Niedrigster Textkontrast, hell / dunkel | Niedrigster Randkontrast, hell / dunkel | Überläufe bei 310 % | Getrennte Wörter bei 310 % |',
};
const n = (lang, x) => (x === null ? '–' : lang === 'de' ? String(x).replace('.', ',') : String(x));
const table = (lang) => [head[lang], `|${' --- |'.repeat(9)}`, ...options.map((o) => {
  const m = summary[o.id];
  const name = o.id === 'today' ? o.name[lang] : `${o.id} ${o.name[lang]}`;
  const label = o.id === pick ? `**${name}**` : name;
  const tag = o.id === runnerUp ? (lang === 'de' ? ' (zweite Wahl)' : ' (runner-up)') : '';
  return `| ${label}${tag} | ${cost[lang][o.cost]} | ${m.rows100} | ${m.rows310} | ${n(lang, m.minTap)} px | ${n(lang, m.contrastLight)} / ${n(lang, m.contrastDark)} | ${n(lang, m.uiLight)} / ${n(lang, m.uiDark)} | ${m.overflow310} | ${m.broken310} |`;
})].join('\n');
for (const [file, lang] of [['RECOMMENDATION.md', 'en'], ['RECOMMENDATION.de.md', 'de']]) {
  const p = join(here, '../rd', file);
  const src = readFileSync(p, 'utf8');
  const out = src.replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, `<!-- table -->\n${table(lang)}\n<!-- /table -->`);
  writeFileSync(p, out);
  console.log(`${file}: table ${out === src ? 'unchanged' : 'written'}`);
}
