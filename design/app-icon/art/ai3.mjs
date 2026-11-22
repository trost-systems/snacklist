// AI3 Bite: a honey snack with a scalloped bite out of one corner, RD10's motif. No check.
import { square, bite } from '../geom.mjs';

export default ({ color }) => {
  const snack = bite(bite(bite(square(512, 540, 320, 120), 880, 380, 120), 800, 230, 120), 660, 170, 110);
  return {
    id: 'AI3',
    groups: [{ name: 'Snack', els: [{ shape: snack, role: 'snack' }] }],
    colors: {
      light: { bg: color('light', 'cobalt'), snack: color('light', 'honey') },
      dark: { bg: color('dark', 'surface'), snack: color('dark', 'honey') },
    },
    mono: snack,
    monoEvenOdd: false,
    tinted: {},
    key: ['snack', 'bg'],
  };
};
