// Measures one rendered phone the way the round's table reports it. Runs in the page (live meter) and in verify.mjs.
// rows: item rows wholly visible between the bars over the list; minTap: the smallest side of anything tappable that is
// not covered; contrast: the lowest text contrast against what is painted under it (WCAG: 4.5, large text 3);
// ui: the lowest contrast of a control's drawn border against its ground (3); overflow: text cut, pushed off the
// screen or drawn over other text; palette: painted colours that are not today's tokens.
const parse = (c) => {
  const m = c.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/) ?? c.match(/color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)(?: \/ ([\d.]+))?\)/);
  if (!m) return null;
  const isSrgb = c.startsWith('color(');
  const k = isSrgb ? 255 : 1;
  return { r: +m[1] * k, g: +m[2] * k, b: +m[3] * k, a: m[4] === undefined ? 1 : +m[4] };
};
const lin = (v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
const lum = (c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
export const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
const over = (top, under) => ({ r: top.r * top.a + under.r * (1 - top.a), g: top.g * top.a + under.g * (1 - top.a), b: top.b * top.a + under.b * (1 - top.a), a: 1 });
const hex = (c) => `#${[c.r, c.g, c.b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('')}`;

// The opaque colour painted under an element: its own and its ancestors' backgrounds, composited, ending at the phone.
const groundOf = (el, phone) => {
  const layers = [];
  for (let n = el; n && n !== phone.parentElement; n = n.parentElement) {
    const bg = parse(getComputedStyle(n).backgroundColor);
    if (bg && bg.a > 0) {
      layers.push(bg);
      if (bg.a >= 1) break;
    }
  }
  let c = { r: 255, g: 255, b: 255, a: 1 };
  for (const l of layers.reverse()) c = over(l, c);
  return c;
};

const visible = (el) => {
  const r = el.getBoundingClientRect();
  if (r.width < 1 || r.height < 1) return false;
  const s = getComputedStyle(el);
  return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05;
};
// Not under a sheet, scrim or bar: the topmost element at a few points inside is this one or inside it.
const uncovered = (el, r = el.getBoundingClientRect()) => {
  const pts = [[0.5, 0.5], [0.2, 0.5], [0.8, 0.5]];
  return pts.some(([fx, fy]) => {
    const x = r.left + r.width * fx;
    const y = r.top + r.height * fy;
    if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) return false;
    const top = document.elementFromPoint(x, y);
    return top && (top === el || el.contains(top) || top.contains(el));
  });
};
const ownText = (el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
const range = (el) => {
  const r = document.createRange();
  r.selectNodeContents(el);
  return r;
};
const textRect = (el) => range(el).getBoundingClientRect();
// One rectangle per line the text takes: a wrapped name's bounding box would also cover the quantity before it.
const lineRects = (el) => [...range(el).getClientRects()].filter((r) => r.width > 0.5);
const label = (el) => `${el.tagName.toLowerCase()}.${[...el.classList].join('.')}${el.dataset.row ? `[${el.dataset.row}]` : ''} "${(el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 28)}"`;
// Text that may end in an ellipsis by design: the list name in the bars, the add field's hint.
const ELLIPSIS = '.two > *, .ttl b, .ptitle b, .large b, .addfield .hint';
const SCROLLERS = '.scroll, .stabs, .sheet, .panel, .drawer, .frames';

export const measure = (phone, palette) => {
  const pr = phone.getBoundingClientRect();
  const screen = phone.querySelector('.screen').getBoundingClientRect();
  const top = phone.querySelector('[data-chrome="top"]');
  const bot = phone.querySelector('[data-chrome="bottom"]');
  const vTop = top ? top.getBoundingClientRect().bottom : screen.top;
  const faces = bot ? [...bot.querySelectorAll('.face')].map((e) => e.getBoundingClientRect().top) : [];
  const vBot = bot ? (faces.length ? Math.min(...faces) : bot.getBoundingClientRect().top) : screen.bottom - 34;
  const rows = [...phone.querySelectorAll('[data-row]')].filter((r) => {
    const b = r.getBoundingClientRect();
    return b.top >= vTop - 0.5 && b.bottom <= vBot + 0.5;
  }).length;

  const taps = [];
  for (const el of phone.querySelectorAll('[data-tap]')) {
    if (!visible(el) || el.closest('[data-system]')) continue;
    const r = el.getBoundingClientRect();
    if (r.bottom <= pr.top || r.top >= pr.bottom || r.right <= pr.left || r.left >= pr.right) continue;
    if (!uncovered(el, r)) continue;
    taps.push({ el, w: r.width, h: r.height, min: Math.min(r.width, r.height) });
  }
  const minTap = taps.length ? Math.min(...taps.map((x) => x.min)) : null;
  const smallTaps = taps.filter((x) => x.min < 44 - 0.5).map((x) => `${label(x.el)} ${Math.round(x.w)}×${Math.round(x.h)}`);

  let contrast = Infinity;
  const lowText = [];
  const texts = [];
  for (const el of phone.querySelectorAll('*')) {
    if (el.closest('[data-system]') || !ownText(el) || !visible(el)) continue;
    const r = textRect(el);
    if (r.width < 1 || r.bottom <= pr.top || r.top >= pr.bottom) continue;
    if (!uncovered(el, r)) continue;
    texts.push({ el, r, lines: lineRects(el) });
    const s = getComputedStyle(el);
    const fg = parse(s.color);
    if (!fg) continue;
    const ground = groundOf(el, phone);
    const c = ratio(over(fg, ground), ground);
    const px = parseFloat(s.fontSize);
    const large = px >= 24 || (px >= 18.66 && Number(s.fontWeight) >= 700);
    const need = large ? 3 : 4.5;
    contrast = Math.min(contrast, c);
    if (c < need) lowText.push(`${label(el)} ${c.toFixed(2)} < ${need} (${hex(over(fg, ground))} on ${hex(ground)})`);
  }

  let ui = Infinity;
  const lowUi = [];
  // Controls only: a face inside something tappable, a tick box, the add field. Bars and separators are not controls.
  for (const el of phone.querySelectorAll('[data-tap] .face, .tk, .afield .face')) {
    if (el.closest('[data-system]') || !visible(el) || !uncovered(el)) continue;
    const s = getComputedStyle(el);
    const bw = parseFloat(s.borderTopWidth);
    const bc = parse(s.borderTopColor);
    if (!(bw >= 1) || !bc || bc.a === 0 || s.borderTopStyle === 'none') continue;
    const ground = groundOf(el.parentElement, phone);
    // The boundary is whichever differs more from the ground: the drawn border or the control's own fill.
    const fill = parse(s.backgroundColor);
    const c = Math.max(ratio(over(bc, ground), ground), fill && fill.a > 0 ? ratio(over(fill, ground), ground) : 1);
    ui = Math.min(ui, c);
    if (c < 3) lowUi.push(`${label(el)} border ${c.toFixed(2)} < 3`);
  }

  const overflow = [];
  for (const { el, r } of texts) {
    if ((r.left < pr.left - 0.5 || r.right > pr.right + 0.5) && !el.closest('.stabs')) overflow.push(`${label(el)} leaves the screen`);
    if (el.matches(ELLIPSIS)) continue;
    for (let n = el; n && n !== phone; n = n.parentElement) {
      if (n.matches(SCROLLERS)) break;
      const s = getComputedStyle(n);
      if (s.overflowX !== 'visible' && n.scrollWidth > n.clientWidth + 1) { overflow.push(`${label(el)} cut sideways by ${label(n)}`); break; }
      if (s.overflowY !== 'visible' && n.scrollHeight > n.clientHeight + 1) { overflow.push(`${label(el)} cut by ${label(n)}`); break; }
    }
  }
  const layerOf = (el) => el.closest('[data-sheet], [data-chrome], .scroll, .kbd') ?? phone;
  for (let i = 0; i < texts.length; i += 1) {
    for (let j = i + 1; j < texts.length; j += 1) {
      const a = texts[i];
      const b = texts[j];
      if (a.el.contains(b.el) || b.el.contains(a.el) || layerOf(a.el) !== layerOf(b.el)) continue;
      // Glyph boxes of a tall display face reach into the line above, so lines may touch by a quarter of their height.
      const hit = a.lines.some((p) => b.lines.some((r) => {
        const x = Math.min(p.right, r.right) - Math.max(p.left, r.left);
        const y = Math.min(p.bottom, r.bottom) - Math.max(p.top, r.top);
        return x > 2 && y > Math.max(2, 0.25 * Math.min(p.height, r.height));
      }));
      if (hit) overflow.push(`${label(a.el)} overlaps ${label(b.el)}`);
    }
  }

  // Words split across two lines: the cost of large text the table reports (not a failure: long German words must break).
  const broken = [];
  for (const { el } of texts) {
    for (const node of el.childNodes) {
      if (node.nodeType !== 3) continue;
      for (const m of node.textContent.matchAll(/\S+/g)) {
        const r = document.createRange();
        r.setStart(node, m.index);
        r.setEnd(node, m.index + m[0].length);
        const tops = new Set([...r.getClientRects()].filter((x) => x.width > 0.5).map((x) => Math.round(x.top)));
        if (tops.size > 1) broken.push(m[0]);
      }
    }
  }

  const offPalette = new Set();
  if (palette) {
    const ok = new Set(palette.map((p) => p.toLowerCase()));
    for (const el of [phone, ...phone.querySelectorAll('*')]) {
      if (el.closest('[data-system]') || !visible(el)) continue;
      const s = getComputedStyle(el);
      const cs = [['color', s.color], ['background', s.backgroundColor], ['fill', el.tagName === 'svg' || el.tagName === 'path' ? s.fill : '']];
      for (const side of ['Top', 'Right', 'Bottom', 'Left']) if (parseFloat(s[`border${side}Width`]) > 0 && s[`border${side}Style`] !== 'none') cs.push([`border-${side.toLowerCase()}`, s[`border${side}Color`]]);
      for (const [what, v] of cs) {
        const c = v && parse(v);
        if (!c || c.a === 0) continue;
        if (!ok.has(hex(c))) offPalette.add(`${what} ${hex(c)} on ${label(el)}`);
      }
    }
  }
  return {
    rows,
    minTap: minTap === null ? null : Math.round(minTap * 10) / 10,
    smallTaps,
    contrast: Number.isFinite(contrast) ? Math.round(contrast * 100) / 100 : null,
    lowText,
    ui: Number.isFinite(ui) ? Math.round(ui * 100) / 100 : null,
    lowUi,
    overflow: [...new Set(overflow)],
    broken,
    offPalette: [...offPalette],
  };
};

// Pads the list so its first row starts under the top bar and its end clears the bottom bar.
export const fit = (phone) => {
  const screen = phone.querySelector('.screen');
  const top = phone.querySelector('[data-chrome="top"]');
  const bot = phone.querySelector('[data-chrome="bottom"]');
  const content = phone.querySelector('.scroll > .content');
  if (!content) return;
  const sh = screen.getBoundingClientRect();
  const t = top ? top.getBoundingClientRect().bottom - sh.top : 0;
  const b = bot ? sh.bottom - bot.getBoundingClientRect().top : 34;
  content.style.setProperty('--top', `${Math.round(t + 4)}px`);
  content.style.setProperty('--bot', `${Math.round(b + 24)}px`);
};
