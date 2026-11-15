// Writes each round's comparison table into its RECOMMENDATION.md and .de.md, between <!-- table --> and <!-- /table -->,
// from the same flows and metrics the page uses. `--check` only compares and exits 1 on a difference.
// Usage: node tools/tables.mjs [--check]
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { measure, combos } from '../metrics.js';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const check = process.argv.includes('--check');

const range = (xs) => {
  const lo = Math.min(...xs), hi = Math.max(...xs);
  return lo === hi ? `${lo}` : `${lo}–${hi}`;
};

export const tableMarkdown = (round, lang) => {
  const P = round.page[lang];
  const first = Object.fromEntries(Object.entries(round.scenarios).map(([k, d]) => [k, d.values[0]]));
  const scenName = Object.entries(round.scenarios).map(([k, d]) => d.names[first[k]][lang]).join(', ');
  const head = `| ${P.cols.join(' | ')} |`;
  const sep = `| ${P.cols.map(() => '---').join(' | ')} |`;
  const rows = round.options.map((o) => {
    const label = o.id === 'today' ? (lang === 'de' ? 'Heute' : 'Today') : o.id;
    const goals = round.goals.map(({ key }) => {
      const now = measure(o, o.paths(first)[key]);
      const all = combos(round.scenarios).map((sc) => measure(o, o.paths(sc)[key]));
      return `**${now.taps} / ${now.screens}** (${range(all.map((m) => m.taps))} / ${range(all.map((m) => m.screens))})`;
    });
    return `| **${label}** ${o.name[lang]} | ${goals.join(' | ')} | ${round.facts.map((f) => o.facts[f][lang]).join(' | ')} |`;
  });
  const note = lang === 'de' ? `Fett: ${scenName}; in Klammern der Bereich über ${P.allScen}.` : `Bold: ${scenName}; in brackets the range over ${P.allScen}.`;
  return `<!-- table -->\n${head}\n${sep}\n${rows.join('\n')}\n\n${note}\n<!-- /table -->`;
};

let bad = 0;
for (const r of ['join', 'create']) {
  const { round } = await import(join(here, r, 'flows.js'));
  for (const [lang, file] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) {
    const path = join(here, r, file);
    const md = await readFile(path, 'utf8');
    const want = md.replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, tableMarkdown(round, lang));
    if (!md.includes('<!-- table -->')) {
      console.log(`FAIL ${r}/${file}: no <!-- table --> marker`);
      bad++;
    } else if (want !== md) {
      if (check) {
        console.log(`FAIL ${r}/${file}: table differs from the flows (run node tools/tables.mjs)`);
        bad++;
      } else {
        await writeFile(path, want);
        console.log(`wrote ${r}/${file}`);
      }
    } else console.log(`ok ${r}/${file}`);
  }
}
process.exit(bad ? 1 : 0);
