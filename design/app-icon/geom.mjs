// Shapes for the app icon and the splash mark. A shape is { d, rings }: SVG path data with
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

// Pointy-top hexagon with circumradius R.
export const hexPoints = (cx, cy, R) => Array.from({ length: 6 }, (_, i) => {
  const a = ((-90 + 60 * i) * Math.PI) / 180;
  return [cx + R * Math.cos(a), cy + R * Math.sin(a)];
});
// Corner radius 2R/6, the 3b Hex Soft rounding the icon was drawn with.
export const hex = (cx, cy, R, radius = (2 * R) / 6) => roundedPolygon(hexPoints(cx, cy, R), radius);

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

// The band a stroke of `width` paints along closed or open rings, for the rasterizer: one quad
// per segment and a disc at every vertex (round joins and caps), all wound the same way so a
// non-zero fill unions them.
export function strokeBand(rings, width, closed) {
  const h = width / 2;
  const disc = ([cx, cy]) => Array.from({ length: 32 }, (_, i) => [cx + h * Math.cos((i * Math.PI) / 16), cy + h * Math.sin((i * Math.PI) / 16)]);
  const out = [];
  for (const ring of rings) {
    const n = closed ? ring.length : ring.length - 1;
    for (let i = 0; i < n; i++) {
      const p = ring[i];
      const q = ring[(i + 1) % ring.length];
      if (len(sub(q, p)) < 1e-9) continue;
      const o = mul(normal(unit(sub(q, p))), h);
      const quad = [add(p, o), add(q, o), sub(q, o), sub(p, o)];
      const area = quad.reduce((s, a, k) => s + cross(a, quad[(k + 1) % 4]), 0);
      out.push(area > 0 ? quad : quad.reverse());
    }
    out.push(...ring.map(disc));
  }
  return out;
}

// A rectangle centred on (cx, cy), half sizes hw and hh, corners rounded by r.
export const roundedRect = (cx, cy, hw, hh, r) => roundedPolygon([[cx - hw, cy - hh], [cx + hw, cy - hh], [cx + hw, cy + hh], [cx - hw, cy + hh]], r);
export const square = (cx, cy, h, r) => roundedRect(cx, cy, h, h, r);

const circlePoints = (cx, cy, r, n = 192) => Array.from({ length: n }, (_, i) => [cx + r * Math.cos((2 * Math.PI * i) / n), cy + r * Math.sin((2 * Math.PI * i) / n)]);
const ringPath = (ring) => `M${ring.map(P).join(' L')} Z`;
export const circle = (cx, cy, r) => {
  const ring = circlePoints(cx, cy, r);
  return { d: `M${P([cx + r, cy])} A${f(r)} ${f(r)} 0 1 1 ${P([cx - r, cy])} A${f(r)} ${f(r)} 0 1 1 ${P([cx + r, cy])} Z`, rings: [ring] };
};

function densify(ring, step) {
  const out = [];
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % ring.length];
    const n = Math.max(1, Math.ceil(len(sub(b, a)) / step));
    for (let k = 0; k < n; k++) out.push(add(a, mul(sub(b, a), k / n)));
  }
  return out;
}

// `shape` with a round bite of radius r around (cx, cy) taken out of its edge. The circle must
// cross the outline exactly twice.
export function bite(shape, cx, cy, r) {
  const ring = densify(shape.rings[0], 2);
  const inside = ([x, y]) => Math.hypot(x - cx, y - cy) < r;
  const start = ring.findIndex((p, i) => !inside(p) && inside(ring[(i + 1) % ring.length]));
  if (start < 0) throw new Error('the bite misses the outline');
  const rolled = [...ring.slice(start + 1), ...ring.slice(0, start + 1)];
  const kept = rolled.filter((p) => !inside(p));
  const enter = rolled.at(-1);
  const exit = kept[0];
  const a1 = Math.atan2(enter[1] - cy, enter[0] - cx);
  let a2 = Math.atan2(exit[1] - cy, exit[0] - cx);
  // The bite's arc runs through the shape's inside, which lies toward the shape's centre.
  const mid = (a) => [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  const ccw = a2 < a1 ? a2 + 2 * Math.PI : a2;
  const cw = a2 > a1 ? a2 - 2 * Math.PI : a2;
  const cxS = ring.reduce((s, p) => s + p[0], 0) / ring.length;
  const cyS = ring.reduce((s, p) => s + p[1], 0) / ring.length;
  const near = (to) => { const m = mid((a1 + to) / 2); return Math.hypot(m[0] - cxS, m[1] - cyS); };
  a2 = near(ccw) < near(cw) ? ccw : cw;
  const steps = 96;
  const arc = Array.from({ length: steps - 1 }, (_, i) => mid(a1 + ((a2 - a1) * (i + 1)) / steps));
  const out = [...arc, ...kept];
  return { d: ringPath(out), rings: [out] };
}

// Several shapes as one (for a layer or the monochrome glyph).
export const union = (...shapes) => ({ d: shapes.map((s) => s.d).join(' '), rings: shapes.flatMap((s) => s.rings) });
