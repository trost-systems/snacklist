// AI1 "Soft tile" (job 372, Peter's pick): icon 5 "Wabenstapel" with RD1's rounded squares in
// place of the hexagons. A honey ring tile on cobalt, a white tile inside it with a cobalt check.
import { square, check, union } from '../geom.mjs';

export default ({ color }) => {
  const outer = square(512, 512, 330, 120);
  const hole = square(512, 512, 226, 76);
  const inner = square(512, 512, 212, 68);
  const tick = check(407, 415, 210, 70);
  return {
    groups: [
      { name: 'Kachel außen', els: [{ shape: outer, role: 'outer' }] },
      { name: 'Kachel innen', els: [{ shape: inner, role: 'inner' }, { shape: tick, role: 'mark' }] },
    ],
    colors: {
      light: { bg: color('light', 'cobalt'), outer: color('light', 'honey'), inner: color('light', 'on-cobalt'), mark: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), outer: color('dark', 'honey'), inner: color('dark', 'brand'), mark: color('dark', 'on-brand') },
    },
    // One colour (Android monochrome, iOS tinted): the ring and the check; the inner tile stays
    // out, so the check stands free in the ring's opening. Even-odd: the hole cuts the ring.
    mono: union(outer, hole, tick),
    monoEvenOdd: true,
    tinted: { inner: 'hide' },
  };
};
