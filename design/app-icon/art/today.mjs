// Today's icon, 5 "Wabenstapel": a honey hexagon ring on cobalt, a white hexagon with a check.
import { hex, check, union } from '../geom.mjs';

export default ({ color }) => {
  const outer = hex(512, 512, 380);
  const hole = hex(512, 512, 250);
  const inner = hex(512, 512, 230);
  const tick = check(406, 452, 212, 66);
  return {
    id: 'Today',
    groups: [
      { name: 'Wabe außen', els: [{ shape: outer, role: 'outer' }] },
      { name: 'Wabe innen', els: [{ shape: inner, role: 'inner' }, { shape: tick, role: 'mark' }] },
    ],
    colors: {
      light: { bg: color('light', 'cobalt'), outer: color('light', 'honey'), inner: color('light', 'on-cobalt'), mark: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), outer: color('dark', 'honey'), inner: color('dark', 'brand'), mark: color('dark', 'on-brand') },
    },
    // One colour (Android monochrome, iOS tinted): the ring and the check; the inner hexagon stays
    // out, so the check stands free in the ring's opening. Even-odd: the hole cuts the ring.
    mono: union(outer, hole, tick),
    monoEvenOdd: true,
    tinted: { inner: 'hide' },
    splash: 'hex-mark',
    key: ['mark', 'inner'],
  };
};
