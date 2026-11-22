// AI2 The list: three RD1 rows on the paper colour, the first ticked off in honey.
import { square, roundedRect, check, union } from '../geom.mjs';

const BOX = 78;
const EDGE = 40;
const ROWS = [302, 512, 722];
const boxX = 290;
const box = (y) => square(boxX, y, BOX, 30);
const boxHole = (y) => square(boxX, y, BOX - EDGE, 10);
const bar = (y, right) => roundedRect((420 + right) / 2, y, (right - 420) / 2, 46, 46);

export default ({ color }) => {
  const done = box(ROWS[0]);
  const tick = check(boxX - 42, ROWS[0] - 36, 84, 40);
  const empty = ROWS.slice(1).map((y) => union(box(y), boxHole(y)));
  const doneBar = bar(ROWS[0], 640);
  const bars = union(bar(ROWS[1], 790), bar(ROWS[2], 720));
  return {
    id: 'AI2',
    groups: [
      { name: 'Erledigt', els: [{ shape: done, role: 'box' }, { shape: tick, role: 'mark' }, { shape: doneBar, role: 'done' }] },
      { name: 'Offen', els: [{ shape: union(...empty), role: 'edge', evenOdd: true }, { shape: bars, role: 'bar' }] },
    ],
    colors: {
      light: { bg: color('light', 'surface'), box: color('light', 'honey'), mark: color('light', 'ink'), done: color('light', 'text-muted'), edge: color('light', 'ink'), bar: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), box: color('dark', 'honey'), mark: color('dark', 'on-honey'), done: color('dark', 'text-muted'), edge: color('dark', 'text'), bar: color('dark', 'brand') },
    },
    // The ticked box is cut by its check; the two open boxes are rings.
    mono: union(done, tick, ...empty, doneBar, bars),
    monoEvenOdd: true,
    tinted: { mark: 0 },
    key: ['bar', 'bg'],
  };
};
