// Shapes for the app icon and the splash tile. A shape is { d, rings }: SVG path data with
// M, L, A and Z only (Android vector drawables read the same) and the outline flattened to
// polygons for the rasterizer. Ported from the job 45 prototype's geom.mjs.

const f = (n) => Number(n.toFixed(2));
const P = ([x, y]) => `${f(x)} ${f(y)}`;
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const mul = (a, k) => [a[0] * k, a[1] * k];
const len = (a) => Math.hypot(a[0], a[1]);
const unit = (a) => mul(a, 1 / len(a));
const normal = (a) => [a[1], -a[0]];
const cross = (a, b) => a[0] * b[1] - a[1] * b[0];

// Points along the arc around `c` from p1 to p2, the short way round (or clockwise when `cw`).
function arcPoints(c, p1, p2, cw) {
  const a1 = Math.atan2(p1[1] - c[1], p1[0] - c[0]);
  let a2 = Math.atan2(p2[1] - c[1], p2[0] - c[0]);
  if (cw === undefined) {
    while (a2 - a1 > Math.PI) a2 -= 2 * Math.PI;
    while (a1 - a2 > Math.PI) a2 += 2 * Math.PI;
  } else if (cw) {
    while (a2 < a1) a2 += 2 * Math.PI;
  } else {
    while (a2 > a1) a2 -= 2 * Math.PI;
  }
  const r = len(sub(p1, c));
  const steps = Math.max(2, Math.ceil(Math.abs(a2 - a1) / (Math.PI / 96)));
  return Array.from({ length: steps + 1 }, (_, i) => {
    const a = a1 + ((a2 - a1) * i) / steps;
    return [c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)];
  });
}

// A polygon with every corner rounded by `radius` (tangent arcs).
export function roundedPolygon(points, radius) {
  const n = points.length;
  let d = '';
  const ring = [];
  for (let i = 0; i < n; i++) {
    const prev = points[(i + n - 1) % n];
    const cur = points[i];
    const next = points[(i + 1) % n];
    const a = unit(sub(prev, cur));
    const b = unit(sub(next, cur));
    const angle = Math.acos(Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1])));
    const t = Math.min(radius / Math.tan(angle / 2), len(sub(prev, cur)) / 2, len(sub(next, cur)) / 2);
    const r = t * Math.tan(angle / 2);
    const p1 = add(cur, mul(a, t));
    const p2 = add(cur, mul(b, t));
    if (r < 0.01) {
      d += `${i === 0 ? 'M' : 'L'}${P(cur)} `;
      ring.push(cur);
      continue;
    }
    const sweep = cross(a, b) < 0 ? 1 : 0;
    d += `${i === 0 ? 'M' : 'L'}${P(p1)} A${f(r)} ${f(r)} 0 0 ${sweep} ${P(p2)} `;
    const c = add(cur, mul(unit(add(a, b)), r / Math.sin(angle / 2)));
    ring.push(...arcPoints(c, p1, p2));
  }
  return { d: `${d}Z`, rings: [ring] };
}

// The outline of a stroked polyline (round caps, mitred joins).
export function strokeOutline(pts, width) {
  const h = width / 2;
  const segs = pts.slice(1).map((p, i) => unit(sub(p, pts[i])));
  const side = (sign) => pts.map((p, i) => {
    if (i === 0) return add(p, mul(normal(segs[0]), sign * h));
    if (i === pts.length - 1) return add(p, mul(normal(segs[i - 1]), sign * h));
    const n1 = normal(segs[i - 1]);
    const m = unit(add(n1, normal(segs[i])));
    return add(p, mul(m, (sign * h) / (m[0] * n1[0] + m[1] * n1[1])));
  });
  const left = side(1);
  const right = side(-1).reverse();
  return {
    d: `M${left.map(P).join(' L')} A${f(h)} ${f(h)} 0 0 1 ${P(right[0])} L${right.slice(1).map(P).join(' L')} A${f(h)} ${f(h)} 0 0 1 ${P(left[0])} Z`,
    rings: [[...left, ...arcPoints(pts.at(-1), left.at(-1), right[0], true).slice(1, -1), ...right, ...arcPoints(pts[0], right.at(-1), left[0], true).slice(1, -1)]],
  };
}

export const checkPoints = (x, y, s) => [[x, y + 0.5 * s], [x + 0.36 * s, y + 0.86 * s], [x + s, y]];
export const check = (x, y, s, width) => strokeOutline(checkPoints(x, y, s), width);

// A rectangle centred on (cx, cy), half sizes hw and hh, corners rounded by r.
export const roundedRect = (cx, cy, hw, hh, r) => roundedPolygon([[cx - hw, cy - hh], [cx + hw, cy - hh], [cx + hw, cy + hh], [cx - hw, cy + hh]], r);
export const square = (cx, cy, h, r) => roundedRect(cx, cy, h, h, r);

// Several shapes as one (for a layer or the monochrome glyph).
export const union = (...shapes) => ({ d: shapes.map((s) => s.d).join(' '), rings: shapes.flatMap((s) => s.rings) });
