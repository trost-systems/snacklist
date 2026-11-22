// AI1 Soft swap: today's icon with RD1's rounded rectangles in place of the hexagons.
import { square, check, union } from '../geom.mjs';

export default ({ color }) => {
  const outer = square(512, 512, 330, 120);
  const hole = square(512, 512, 226, 76);
  const inner = square(512, 512, 212, 68);
  const tick = check(407, 415, 210, 70);
  return {
    id: 'AI1',
    groups: [
      { name: 'Kachel außen', els: [{ shape: outer, role: 'outer' }] },
      { name: 'Kachel innen', els: [{ shape: inner, role: 'inner' }, { shape: tick, role: 'mark' }] },
    ],
    colors: {
      light: { bg: color('light', 'cobalt'), outer: color('light', 'honey'), inner: color('light', 'on-cobalt'), mark: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), outer: color('dark', 'honey'), inner: color('dark', 'brand'), mark: color('dark', 'on-brand') },
    },
    mono: union(outer, hole, tick),
    monoEvenOdd: true,
    tinted: { inner: 'hide' },
    key: ['mark', 'inner'],
  };
};
