// AI4 Bag: a honey tote bag, tapered, with a wide handle and today's check on it.
import { roundedPolygon, strokeOutline, check } from '../geom.mjs';

const HANDLE = 68;
const TOP = 390;

export default ({ color }) => {
  const body = roundedPolygon([[200, TOP], [824, TOP], [764, 800], [260, 800]], 70);
  // The handle's round caps end exactly on the bag's top edge, so the two never overlap.
  const cy = TOP - HANDLE / 2;
  const arc = Array.from({ length: 49 }, (_, i) => {
    const a = Math.PI + (Math.PI * i) / 48;
    return [512 + 170 * Math.cos(a), cy + 150 * Math.sin(a)];
  });
  const handle = strokeOutline(arc, HANDLE);
  const tick = check(407, 497, 210, 74);
  return {
    id: 'AI4',
    groups: [
      { name: 'Henkel', els: [{ shape: handle, role: 'handle' }] },
      { name: 'Tasche', els: [{ shape: body, role: 'bag' }, { shape: tick, role: 'mark' }] },
    ],
    colors: {
      light: { bg: color('light', 'cobalt'), handle: color('light', 'honey'), bag: color('light', 'honey'), mark: color('light', 'cobalt') },
      dark: { bg: color('dark', 'surface'), handle: color('dark', 'honey'), bag: color('dark', 'honey'), mark: color('dark', 'on-honey') },
    },
    mono: { d: `${handle.d} ${body.d} ${tick.d}`, rings: [...handle.rings, ...body.rings, ...tick.rings] },
    monoEvenOdd: true,
    tinted: { mark: 0 },
    key: ['mark', 'bag'],
  };
};
