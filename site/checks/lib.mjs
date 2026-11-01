import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { startPreview } from '../scripts/preview.mjs';

export const VIEWPORTS = { 390: { width: 390, height: 844 }, 1440: { width: 1440, height: 900 } };
export const SCHEMES = ['light', 'dark'];
export const RUNS = Object.keys(VIEWPORTS).flatMap((width) => SCHEMES.map((scheme) => ({ width: Number(width), scheme })));
export const runName = ({ width, scheme }) => `${width} ${scheme}`;

export const AXE_PATH = createRequire(import.meta.url).resolve('axe-core/axe.min.js');

// argv: [distDir] [--port n] [--out dir] [--pages /de,/en]; the dist must exist.
export function parseArgs(defaults) {
  const args = process.argv.slice(2);
  const flag = (name) => {
    const at = args.indexOf(`--${name}`);
    return at < 0 ? undefined : args.splice(at, 2)[1];
  };
  const port = Number(flag('port') ?? defaults.port);
  const out = resolve(flag('out') ?? defaults.out ?? '.');
  const pages = flag('pages')?.split(',');
  const dist = resolve(args[0] ?? '../dist');
  if (!existsSync(resolve(dist, 'de.html'))) throw new Error(`${dist} has no de.html: build the site first (cd site && npm run build)`);
  return { dist, port, out, pages };
}

export async function serve(dist, port) {
  const server = await startPreview({ dir: dist, port, host: '127.0.0.1' });
  return { origin: `http://127.0.0.1:${port}`, close: () => new Promise((r) => server.close(r)) };
}

export const parseRgb = (css) => {
  const m = css.match(/rgba?\(([^)]+)\)/);
  if (!m) return null;
  const [r, g, b, a = 1] = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
  return [r, g, b, a];
};
const lum = ([r, g, b]) => {
  const [R, G, B] = [r, g, b].map((c) => c / 255).map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * R + 0.7152 * G + 0.0722 * B;
};
export const contrast = (a, b) => {
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};

// Installed in every page before its scripts run (CDP, so the CSP does not apply): a stable
// selector for any element, and the nearest opaque background colour behind it.
export function pageKit() {
  const sel = (e) => {
    const parts = [];
    for (let n = e; n && n.nodeType === 1 && n !== document.documentElement; n = n.parentElement) {
      if (n.id) { parts.unshift(`#${CSS.escape(n.id)}`); break; }
      let part = n.tagName.toLowerCase();
      const cls = [...n.classList].filter((c) => !/^is-/.test(c)).slice(0, 2);
      if (cls.length) part += `.${cls.map((c) => CSS.escape(c)).join('.')}`;
      const same = n.parentElement ? [...n.parentElement.children].filter((s) => s.tagName === n.tagName) : [];
      if (same.length > 1) part += `:nth-of-type(${same.indexOf(n) + 1})`;
      parts.unshift(part);
    }
    return parts.join(' > ');
  };
  const label = (e) => (e.getAttribute('aria-label') ?? e.textContent ?? '').trim().replace(/\s+/g, ' ').slice(0, 40);
  const bgBehind = (e) => {
    for (let n = e; n; n = n.parentElement) {
      const c = getComputedStyle(n).backgroundColor;
      const a = Number((c.match(/rgba?\(([^)]+)\)/)?.[1].split(/[\s,/]+/)[3]) ?? 1);
      if (a > 0.99) return { color: c, sel: n === document.body ? 'body' : sel(n) };
    }
    return { color: 'rgb(255, 255, 255)', sel: 'canvas' };
  };
  window.__kit = { sel, label, bgBehind };
}

// Group problems that repeat across runs: one line per page, check, selector and message.
export function groupProblems(problems) {
  const groups = new Map();
  for (const p of problems) {
    const key = [p.page, p.check, p.selector, p.message].join('\u0000');
    if (!groups.has(key)) groups.set(key, { ...p, runs: [] });
    groups.get(key).runs.push(p.run);
  }
  return [...groups.values()];
}

export function table(header, rows) {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)));
  const line = (cells) => `| ${cells.map((c, i) => String(c).padEnd(widths[i])).join(' | ')} |`;
  return [line(header), `| ${widths.map((w) => '-'.repeat(w)).join(' | ')} |`, ...rows.map(line)].join('\n');
}
