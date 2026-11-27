export type Look = 'soft' | 'hex';
export type ShapeKind = 'hex' | 'rect';

const TIP = 0.2887;
const REF_HEIGHT = 48;
const CORNER = 8;

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export function softRadius(side: number): number {
  if (side < 28) return 6;
  if (side < 40) return 8;
  if (side < 60) return 12;
  return 20;
}

export function alongFor(look: Look, outset: number): number {
  return look === 'soft' ? outset : outset / Math.sin(Math.atan(1 / (2 * TIP)));
}

const f = (n: number) => (Math.round(n * 100) / 100).toString();

function roundRect(b: Box, r: number): string {
  const rr = Math.max(0, Math.min(r, b.w / 2, b.h / 2));
  const { x, y, w, h } = b;
  return [
    `M${f(x + rr)} ${f(y)}`,
    `H${f(x + w - rr)}`,
    `A${f(rr)} ${f(rr)} 0 0 1 ${f(x + w)} ${f(y + rr)}`,
    `V${f(y + h - rr)}`,
    `A${f(rr)} ${f(rr)} 0 0 1 ${f(x + w - rr)} ${f(y + h)}`,
    `H${f(x + rr)}`,
    `A${f(rr)} ${f(rr)} 0 0 1 ${f(x)} ${f(y + h - rr)}`,
    `V${f(y + rr)}`,
    `A${f(rr)} ${f(rr)} 0 0 1 ${f(x + rr)} ${f(y)}`,
    'Z',
  ].join('');
}

function roundedPolygon(vs: [number, number][], radius: number): string {
  const v = vs.filter((p, i) => {
    const q = vs[(i - 1 + vs.length) % vs.length];
    return !(q && q[0] === p[0] && q[1] === p[1]);
  });
  const n = v.length;
  if (radius <= 0 || n < 3) return `M${v.map((p) => `${f(p[0])} ${f(p[1])}`).join('L')}Z`;
  let d = '';
  for (let i = 0; i < n; i++) {
    const prev = v[(i - 1 + n) % n];
    const cur = v[i];
    const next = v[(i + 1) % n];
    if (!prev || !cur || !next) continue;
    const ax = prev[0] - cur[0];
    const ay = prev[1] - cur[1];
    const bx = next[0] - cur[0];
    const by = next[1] - cur[1];
    const la = Math.hypot(ax, ay);
    const lb = Math.hypot(bx, by);
    const angle = Math.acos(Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb))));
    const halfTan = Math.tan(angle / 2);
    const t = Math.min(radius / halfTan, Math.min(la, lb) / 2);
    const r = t * halfTan;
    const sx = cur[0] + (ax / la) * t;
    const sy = cur[1] + (ay / la) * t;
    const ex = cur[0] + (bx / lb) * t;
    const ey = cur[1] + (by / lb) * t;
    d += `${i === 0 ? 'M' : 'L'}${f(sx)} ${f(sy)}A${f(r)} ${f(r)} 0 0 1 ${f(ex)} ${f(ey)}`;
  }
  return `${d}Z`;
}

export function shapePath(kind: ShapeKind, look: Look, b: Box, outset = 0): string {
  const grownSoft = { x: b.x - outset, y: b.y - outset, w: b.w + 2 * outset, h: b.h + 2 * outset };
  if (kind === 'rect') return roundRect(grownSoft, 0);
  if (look === 'soft') return roundRect(grownSoft, Math.max(0, softRadius(Math.min(b.w, b.h)) + outset));
  const along = alongFor(look, outset);
  const g = { x: b.x - along, y: b.y - outset, w: b.w + 2 * along, h: b.h + 2 * outset };
  const t = Math.min(TIP * g.h, g.w / 2);
  const cy = g.y + g.h / 2;
  const vertices: [number, number][] = [
    [g.x, cy],
    [g.x + t, g.y],
    [g.x + g.w - t, g.y],
    [g.x + g.w, cy],
    [g.x + g.w - t, g.y + g.h],
    [g.x + t, g.y + g.h],
  ];
  return roundedPolygon(vertices, Math.max(0, (CORNER * b.h) / REF_HEIGHT + outset));
}

export function hexTextInset(height: number): number {
  return TIP * height + 4;
}
