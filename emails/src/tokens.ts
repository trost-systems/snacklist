// The RD1 design tokens (colour, space, soft shapes), read from design/tokens/snacklist.tokens.json at render time so no
// colour, space or radius is copied by hand. Mail clients get the resolved values inline.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

type Node = { $value?: unknown; [key: string]: unknown };
const source: Node = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../design/tokens/snacklist.tokens.json', import.meta.url)), 'utf8'),
);

function resolve(value: unknown): unknown {
  if (typeof value !== 'string' || !/^\{.+\}$/.test(value)) return value;
  const node = value.slice(1, -1).split('.').reduce<Node>((n, k) => n[k] as Node, source);
  return resolve(node.$value);
}
function token(path: string): unknown {
  const node = path.split('.').reduce<Node>((n, k) => {
    const next = n[k] as Node | undefined;
    if (!next) throw new Error(`design token ${path} is missing`);
    return next;
  }, source);
  return resolve(node.$value);
}

const COLORS = [
  'brand', 'honey', 'on-honey', 'honey-soft', 'accent', 'surface', 'surface-raised',
  'surface-sunken', 'text', 'text-muted', 'border', 'divider', 'ink',
] as const;
export type ColorName = (typeof COLORS)[number];
export type Mode = 'light' | 'dark';

function palette(mode: Mode): Record<ColorName, string> {
  return Object.fromEntries(
    COLORS.map((name) => [name, (token(`color.${mode}.${name}`) as { hex: string }).hex.toLowerCase()]),
  ) as Record<ColorName, string>;
}
export const color = { light: palette('light'), dark: palette('dark') };

const px = (path: string): number => {
  const d = token(path) as { value: number; unit: string };
  return d.unit === 'rem' ? d.value * 16 : d.value;
};
export const space = { 1: px('space.1'), 2: px('space.2'), 3: px('space.3'), 4: px('space.4'), 5: px('space.5'), 6: px('space.6'), 7: px('space.7') };
// RD1 soft shapes: cards lg, buttons and fields md, the logo tile follows the icon (md).
export const radius = { sm: px('shape.soft.sm'), md: px('shape.soft.md'), lg: px('shape.soft.lg'), xl: px('shape.soft.xl'), full: px('radius.full') };
export const border = { width: px('border.width'), thin: px('border.width-thin') };
export const depth = { edge: px('depth.edge') };
export const target = px('size.target');

type TypeToken = { fontSize: { value: number; unit: string }; fontWeight: number; lineHeight: number };
function type(name: string) {
  const t = token(`type.${name}`) as TypeToken;
  return { size: t.fontSize.unit === 'rem' ? t.fontSize.value * 16 : t.fontSize.value, weight: t.fontWeight, line: t.lineHeight };
}
export const typography = { headline: type('headline'), title: type('title'), body: type('body'), label: type('label') };
export const weight = { bold: token('font.weight.bold') as number, heavy: token('font.weight.heavy') as number };

// Mail clients cannot load the self-hosted fonts without a remote request (docs/EMAIL.md,
// "Fonts"), so the token's first family leads a stack of fonts mail clients have installed.
const family = (path: string): string => {
  const [first] = token(path) as string[];
  if (first === undefined) throw new Error(`design token ${path} has no family`);
  return first;
};
const stack = (names: string[]) => names.map((n) => (/\s/.test(n) ? `"${n}"` : n)).join(', ');
export const font = {
  display: stack([family('font.family.display'), 'Trebuchet MS', 'Helvetica Neue', 'Arial', 'sans-serif']),
  body: stack([family('font.family.sans'), '-apple-system', 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', 'sans-serif']),
};
