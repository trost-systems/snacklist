// The measured table in RECOMMENDATION.md and .de.md: after `<!-- measured: <lang> <device> <ts> -->`, one row per
// option, each column a scenario and a field of measured.json. measure.mjs --write fills it; verify.mjs reads it back.
export const columns = [['short-3', 'active'], ['short-3', 'recent'], ['short-15', 'recent'], ['long-15', 'active'], ['long-15', 'recent'], ['long-15', 'toFirstRecent']];
export const optionIds = ['today', 'RU1', 'RU2', 'RU3', 'RU4'];
const marker = /^<!-- measured: (\w+) (\w+) (\d+) -->$/;
const show = (v) => (v === null ? '—' : String(v));

export const fill = (src, m) => {
  const lines = src.split('\n');
  const out = [];
  for (let i = 0; i < lines.length; i += 1) {
    out.push(lines[i]);
    const hit = marker.exec(lines[i]);
    if (!hit) continue;
    const [, lang, dev, ts] = hit;
    out.push(lines[i + 1], lines[i + 2]);
    i += 2;
    while (lines[i + 1]?.startsWith('|')) i += 1;
    for (const id of optionIds) out.push(`| ${id} | ${columns.map(([sc, f]) => show(m[lang][dev][ts][sc][id][f])).join(' | ')} |`);
  }
  return out.join('\n');
};

// Every cell that differs from measured.json, as text; empty when the tables match (or there is none).
export const check = (src, m) => {
  const bad = [];
  const lines = src.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const hit = marker.exec(lines[i]);
    if (!hit) continue;
    const [, lang, dev, ts] = hit;
    const rows = [];
    for (let j = i + 3; lines[j]?.startsWith('|'); j += 1) rows.push(lines[j].split('|').slice(1, -1).map((c) => c.trim()));
    if (rows.length !== optionIds.length) bad.push(`${lang} ${dev} ${ts}: ${rows.length} rows, want ${optionIds.length}`);
    for (const r of rows) {
      const id = r[0];
      columns.forEach(([sc, f], k) => {
        const want = show(m[lang]?.[dev]?.[ts]?.[sc]?.[id]?.[f]);
        if (r[k + 1] !== want) bad.push(`${lang} ${dev} ${ts} ${id} ${sc} ${f}: table ${r[k + 1]}, measured ${want}`);
      });
    }
  }
  return bad;
};
