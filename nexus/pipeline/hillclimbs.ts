// Hill-climb progress from the docs on main (docs/hillclimb/hc-*.md). Each doc writes its baseline
// in its own words, so a small registry says where to read it; the attempts table is shared
// (`| # | time | change | score | kept | why |`). A doc that drifts from its entry throws, and the
// test over the real docs fails, instead of the page showing a wrong number.
import type { HillClimb } from '../src/snapshot.ts';

export interface HillClimbDoc {
  id: string;
  metric: string;
  direction: 'lower' | 'higher';
  /** Captures the baseline score in group 1. */
  baseline: RegExp;
  target: number | null;
  /** Captures a kept row's score in group 1 where the cell has it; else the cell's first number counts. */
  score?: RegExp;
}

export const hillClimbDocs: readonly HillClimbDoc[] = [
  {
    id: 'hc-backend-perf',
    metric: 'p95 latency, geometric mean (ms)',
    direction: 'lower',
    baseline: /^Median \*\*([\d.]+)\*\*/m,
    target: null,
  },
  {
    id: 'hc-design-v2-app',
    metric: 'weakest design aspect, blind council (harness v2, of 10)',
    direction: 'higher',
    baseline: /Score \(median\) \*\*([\d.]+)\*\*/,
    target: null,
  },
  {
    id: 'hc-design-v3-app',
    metric: 'weakest design aspect, blind council (harness v3, of 10)',
    direction: 'higher',
    baseline: /Score \(median\) \*\*([\d.]+)\*\*/,
    target: null,
  },
  {
    id: 'hc-size-start',
    metric: 'download size and start time (1.0 = baseline)',
    direction: 'lower',
    baseline: /score ([\d.]+) by construction/,
    target: null,
  },
  {
    id: 'hc-strictness',
    metric: 'TypeScript rule violations',
    direction: 'lower',
    baseline: /the honest baseline is (\d+)/,
    target: 0,
  },
  {
    id: 'hc-sync',
    metric: 'failed sync seeds per 1000',
    direction: 'lower',
    baseline: /^Median score \*\*([\d.]+)\*\*/m,
    target: 0,
  },
  {
    id: 'hc-tests',
    metric: 'coverage x mutation score per wall second',
    direction: 'higher',
    baseline: /\*\*Corrected baseline ([\d.]+)/,
    target: null,
    score: /([\d.]+) corrected/,
  },
  {
    id: 'hc-ui-app',
    metric: 'weakest design category (judges, of 10)',
    direction: 'higher',
    baseline: /^Baseline median \*\*([\d.]+)\*\*/m,
    target: 9,
  },
  {
    id: 'hc-ui-perf',
    metric: 'frame time score',
    direction: 'lower',
    baseline: /\*\*Baseline ([\d.]+), band/,
    target: null,
  },
];

/** Cells of one Markdown table row; a `|` inside backticks or escaped stays in its cell. */
export function tableCells(line: string): string[] {
  const cells: string[] = [];
  let cell = '';
  let code = false;
  const body = line.trim().replace(/^\|/, '').replace(/\|$/, '');
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === '`') code = !code;
    if (c === '\\' && body[i + 1] === '|') {
      cell += '|';
      i++;
      continue;
    }
    if (c === '|' && !code) {
      cells.push(cell.trim());
      cell = '';
      continue;
    }
    cell += c;
  }
  cells.push(cell.trim());
  return cells;
}

const plain = (cell: string): string => cell.replaceAll('**', '').trim();

/** The scores of the kept rows of the attempts table, in table order. */
export function keptScores(markdown: string, doc: HillClimbDoc): number[] {
  const lines = markdown.split('\n');
  const header = lines.findIndex((l) => /^\|\s*#\s*\|/.test(l) && /\|\s*kept/i.test(l));
  if (header < 0) throw new Error(`${doc.id}: no attempts table (| # | ... | score | kept ... |)`);
  const names = tableCells(lines[header] ?? '').map((c) => c.toLowerCase());
  const scoreCol = names.indexOf('score');
  const keptCol = names.findIndex((n) => n.startsWith('kept'));
  if (scoreCol < 0 || keptCol < 0) throw new Error(`${doc.id}: attempts table has no score or kept column`);
  const scores: number[] = [];
  for (const line of lines.slice(header + 2)) {
    if (!line.startsWith('|')) break;
    const cells = tableCells(line);
    if (cells.length < names.length) throw new Error(`${doc.id}: short attempts row: ${line.slice(0, 40)}`);
    if (!plain(cells[keptCol] ?? '').toLowerCase().startsWith('kept')) continue;
    const scoreCell = plain(cells[scoreCol] ?? '');
    const value = doc.score?.exec(scoreCell)?.[1] ?? /^([\d.]+)/.exec(scoreCell)?.[1];
    if (value === undefined) continue; // a kept harness-only row ("n/a") moves no score
    scores.push(Number(value));
  }
  return scores;
}

export function parseHillClimb(markdown: string, doc: HillClimbDoc): HillClimb {
  const b = doc.baseline.exec(markdown)?.[1];
  if (b === undefined) throw new Error(`${doc.id}: baseline not found (${doc.baseline})`);
  const baseline = Number(b);
  const steps = keptScores(markdown, doc);
  const better = doc.direction === 'lower' ? Math.min : Math.max;
  return {
    id: doc.id,
    metric: doc.metric,
    direction: doc.direction,
    baseline,
    best: better(baseline, ...steps),
    target: doc.target,
    steps,
  };
}

/** Every registered doc in dir; a doc that is missing or fails to parse is reported and left out. */
export async function readHillClimbs(dir: string, warn: (msg: string) => void): Promise<HillClimb[]> {
  const out: HillClimb[] = [];
  for (const doc of hillClimbDocs) {
    try {
      out.push(parseHillClimb(await Deno.readTextFile(`${dir}/${doc.id}.md`), doc));
    } catch (e) {
      warn(`hill-climb ${doc.id} left out: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  return out;
}
