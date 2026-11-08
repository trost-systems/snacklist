import { assertEquals, assertThrows } from '@std/assert';
import { hillClimbDocs, parseHillClimb, tableCells } from '../pipeline/hillclimbs.ts';

const docsDir = new URL('../../docs/hillclimb/', import.meta.url).pathname;

Deno.test('every registered doc on main parses to its known numbers', async () => {
  const got = Object.fromEntries(
    await Promise.all(hillClimbDocs.map(async (doc) => {
      const h = parseHillClimb(await Deno.readTextFile(`${docsDir}${doc.id}.md`), doc);
      return [doc.id, [h.baseline, h.best, h.steps.length]] as const;
    })),
  );
  assertEquals(got, {
    'hc-backend-perf': [122.82, 91.98, 1],
    'hc-design-v2-app': [4, 5, 11],
    'hc-design-v3-app': [5, 6, 10],
    'hc-size-start': [1, 1, 0],
    'hc-strictness': [1030, 2, 6],
    'hc-sync': [175.000509, 0.000491, 8],
    'hc-tests': [10.36, 19.2368, 2],
    'hc-ui-app': [6.5, 6.5, 0],
    'hc-ui-perf': [7.479, 6.598, 1],
  });
});

Deno.test('every hc doc on main is registered', async () => {
  const onDisk: string[] = [];
  for await (const e of Deno.readDir(docsDir)) {
    if (e.isFile && /^hc-.*\.md$/.test(e.name)) onDisk.push(e.name.replace(/\.md$/, ''));
  }
  assertEquals(onDisk.sort(), hillClimbDocs.map((d) => d.id).sort());
});

Deno.test('table cells keep pipes inside code and escapes', () => {
  assertEquals(tableCells('| 5 | 11:20 | index on `a | b` and a\\|b | 91.0 | kept | x |'), [
    '5',
    '11:20',
    'index on `a | b` and a|b',
    '91.0',
    'kept',
    'x',
  ]);
});

const doc = {
  id: 'hc-x',
  metric: 'm',
  direction: 'lower' as const,
  baseline: /Baseline \*\*([\d.]+)\*\*/,
  target: null,
};
const table = [
  'Baseline **10.5**',
  '',
  '| # | time | change | score | kept/reverted | why |',
  '| --- | --- | --- | --- | --- | --- |',
  '| 1 | 01:00 | a | 9.5 (9.4, 9.6) | kept | . |',
  '| 2 | 02:00 | b | 8.0 | reverted | . |',
  '| 2b | 02:10 | harness | n/a | kept | . |',
  '| 3 | 03:00 | c | **7.25** | **kept** | . |',
  '',
  '| # | time | change | score | kept | why |',
  '| 9 | 09:00 | later table | 1.0 | kept | . |',
].join('\n');

Deno.test('kept rows only, bold and harness rows handled, best by direction', () => {
  assertEquals(parseHillClimb(table, doc), {
    id: 'hc-x',
    metric: 'm',
    direction: 'lower',
    baseline: 10.5,
    best: 7.25,
    target: null,
    steps: [9.5, 7.25],
  });
  assertEquals(parseHillClimb(table, { ...doc, direction: 'higher' }).best, 10.5);
});

Deno.test('format drift fails loudly', () => {
  assertThrows(() => parseHillClimb(table.replace('Baseline', 'Base'), doc), Error, 'baseline not found');
  assertThrows(
    () => parseHillClimb('Baseline **1**\n\n| # | time | change | result | kept | why |\n| --- |\n', doc),
    Error,
    'no score or kept column',
  );
  assertThrows(() => parseHillClimb('Baseline **1**', doc), Error, 'no attempts table');
  assertThrows(
    () => parseHillClimb(table.replace('| 9.5 (9.4, 9.6) | kept | . |', '| kept |'), doc),
    Error,
    'short attempts row',
  );
});
