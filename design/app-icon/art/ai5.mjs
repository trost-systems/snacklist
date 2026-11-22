// AI5 Big check: one heavy cobalt check on honey, nothing else.
import { check } from '../geom.mjs';

const STROKE = 140;

export default ({ color }) => {
  const tick = check(272, 318, 480, STROKE);
  return {
    id: 'AI5',
    groups: [{ name: 'Haken', els: [{ shape: tick, role: 'mark' }] }],
    colors: {
      light: { bg: color('light', 'honey'), mark: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), mark: color('dark', 'honey') },
    },
    mono: tick,
    monoEvenOdd: false,
    tinted: {},
    key: ['mark', 'bg'],
  };
};
