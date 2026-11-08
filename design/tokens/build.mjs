#!/usr/bin/env node
// Writes the Hummlist design tokens for the app and the site from hummlist.tokens.json:
//   app/lib/design/tokens.g.dart  colours (light and dark) as a ThemeExtension, type, space,
//                                 radius, depth, shape, focus and motion constants
//   site/public/tokens.css        the same as --hl-* custom properties, dark under
//                                 prefers-color-scheme
//   app/web/join/tokens.css       the same file for the web app's join page (job 169b)
//   app/ios/HomeWidget/HummlistColors.swift, app/android/.../values{,-night}/hummlist_tokens.xml
//                                 the colours for the Home Screen widgets (job 63)
// Node only, no packages and no network. `--check` writes nothing and fails when an output
// differs from what the source makes.
import process from 'node:process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const tokens = JSON.parse(readFileSync(join(here, 'hummlist.tokens.json'), 'utf8'));

const groups = (node) => Object.entries(node).filter(([k]) => !k.startsWith('$'));
const resolve = (v) => {
  if (typeof v !== 'string' || !/^\{.+\}$/.test(v)) return v;
  const node = v.slice(1, -1).split('.').reduce((n, k) => n[k], tokens);
  return resolve(node.$value);
};
const value = (node) => resolve(node.$value);
const px = (d) => (d.unit === 'rem' ? d.value * 16 : d.value);
const num = (n) => `${Math.round(n * 10000) / 10000}`;
const camel = (s) => s.replace(/-(\w)/g, (_, c) => c.toUpperCase()).replace(/^(\d)/, 'v$1');
const colorHex = (c) => c.hex.toLowerCase();

const colorNames = groups(tokens.color.light).map(([k]) => k);
for (const k of colorNames) {
  if (!tokens.color.dark[k]) throw new Error(`color.dark.${k} is missing`);
}

// ---- CSS ----
const cssFamily = (f) => f.map((n) => (/\s/.test(n) && !n.includes('"') ? `"${n}"` : n)).join(', ');
const cssLength = (d) => `${d.value}${d.unit}`;
const cssShadow = (list) => list.map((s) => {
  const a = s.color.alpha;
  const color = a === undefined || a >= 1 ? colorHex(s.color) : `${colorHex(s.color)}${Math.round(a * 255).toString(16).padStart(2, '0')}`;
  return `${cssLength(s.offsetX)} ${cssLength(s.offsetY)} ${cssLength(s.blur)} ${cssLength(s.spread)} ${color}`;
}).join(', ');

function cssLines() {
  const out = [];
  for (const k of colorNames) out.push([`color-${k}`, colorHex(value(tokens.color.light[k]))]);
  for (const [k, n] of groups(tokens.font.family)) out.push([`font-family-${k}`, cssFamily(value(n))]);
  for (const [k, n] of groups(tokens.font.weight)) out.push([`font-weight-${k}`, `${value(n)}`]);
  for (const [k, n] of groups(tokens.type)) {
    const v = value(n);
    out.push([`type-${k}-family`, cssFamily(resolve(v.fontFamily))]);
    out.push([`type-${k}-size`, cssLength(v.fontSize)]);
    out.push([`type-${k}-weight`, `${v.fontWeight}`]);
    out.push([`type-${k}-line`, `${v.lineHeight}`]);
    out.push([`type-${k}-tracking`, cssLength(v.letterSpacing)]);
  }
  for (const [k, n] of groups(tokens.space)) out.push([`space-${k}`, cssLength(value(n))]);
  for (const [k, n] of groups(tokens.radius)) out.push([`radius-${k}`, cssLength(value(n))]);
  for (const [k, n] of groups(tokens.border)) out.push([`border-${k}`, cssLength(value(n))]);
  for (const [k, n] of groups(tokens.shadow)) out.push([`shadow-${k}`, cssShadow(value(n))]);
  for (const [k, n] of groups(tokens.motion.duration)) { const d = value(n); out.push([`motion-duration-${k}`, `${d.value}${d.unit}`]); }
  for (const [k, n] of groups(tokens.motion.easing)) out.push([`motion-easing-${k}`, `cubic-bezier(${value(n).join(', ')})`]);
  for (const [k, n] of groups(tokens.shape.hex)) { const v = value(n); out.push([`shape-hex-${k}`, typeof v === 'number' ? `${v}` : cssLength(v)]); }
  for (const [k, n] of groups(tokens.depth)) out.push([`depth-${k}`, cssLength(value(n))]);
  for (const [k, n] of groups(tokens.focus.ring)) out.push([`focus-ring-${k}`, cssLength(value(n))]);
  for (const [k, n] of groups(tokens.size)) out.push([`size-${k}`, cssLength(value(n))]);
  return out;
}

const css = `/* Generated from design/tokens/hummlist.tokens.json by design/tokens/build.mjs. Do not edit. */

:root {
  color-scheme: light dark;
${cssLines().map(([k, v]) => `  --hl-${k}: ${v};`).join('\n')}
}

@media (prefers-color-scheme: dark) {
  :root {
${colorNames.map((k) => `    --hl-color-${k}: ${colorHex(value(tokens.color.dark[k]))};`).join('\n')}
  }
}
`;

// ---- Dart ----
const argb = (c) => `Color(0xFF${colorHex(c).slice(1).toUpperCase()})`;
const dartColors = (mode) => colorNames.map((k) => `    ${camel(k)}: ${argb(value(tokens.color[mode][k]))},`).join('\n');
const doc = (n) => (n.$description ? `\n  /// ${n.$description}\n` : '');
const fontFamily = (f) => resolve(f)[0];
const dartFonts = groups(tokens.font.family).map(([k, n]) => `${doc(n)}  static const ${camel(k)} = '${value(n)[0]}';`).join('\n');
const dartType = groups(tokens.type).map(([k, n]) => {
  const v = value(n);
  const size = px(v.fontSize);
  const tracking = v.letterSpacing.unit === 'em' ? v.letterSpacing.value * size : px(v.letterSpacing);
  return `  static const ${camel(k)} = TextStyle(
    fontFamily: HlFont.${camel(groups(tokens.font.family).find(([, f]) => value(f)[0] === fontFamily(v.fontFamily))[0])},
    fontSize: ${num(size)},
    fontWeight: FontWeight.w${Math.round(v.fontWeight / 100) * 100},
    height: ${num(v.lineHeight)},
    letterSpacing: ${num(tracking)},
  );`;
}).join('\n');
const dims = (_cls, node, prefix = '') => groups(node).map(([k, n]) => `${doc(n)}  static const double ${camel(prefix + k)} = ${num(px(value(n)))};`).join('\n');
const dartDurations = groups(tokens.motion.duration).map(([k, n]) => `${doc(n)}  static const ${camel(k)} = Duration(milliseconds: ${value(n).value});`).join('\n');
const dartCurves = groups(tokens.motion.easing).map(([k, n]) => `${doc(n)}  static const ${camel(k)} = Cubic(${value(n).map(num).join(', ')});`).join('\n');
// One shadow per line, as dart format lays them out.
const dartShadow = (shadows) => shadows.map((s) => {
  const a = Math.round((s.color.alpha ?? 1) * 255).toString(16).padStart(2, '0');
  const args = [
    `color: Color(0x${a}${s.color.hex.slice(1)})`,
    `offset: Offset(${num(s.offsetX.value)}, ${num(s.offsetY.value)})`,
    ...(s.blur.value ? [`blurRadius: ${num(s.blur.value)}`] : []),
    ...(s.spread.value ? [`spreadRadius: ${num(s.spread.value)}`] : []),
  ];
  return `    BoxShadow(${args.join(', ')}),`;
}).join('\n');
const dartShadows = groups(tokens.shadow).map(([k, n]) => `${doc(n)}  static const ${camel(k)} = [\n${dartShadow(value(n))}\n  ];`).join('\n');
const hex = tokens.shape.hex;

const dart = `// GENERATED from design/tokens/hummlist.tokens.json by design/tokens/build.mjs. Do not edit.
import 'package:flutter/material.dart';

/// Every colour token, in light or dark. Read it with
/// \`Theme.of(context).extension<HummlistColors>()!\` or [HummlistColors.of].
@immutable
class HummlistColors extends ThemeExtension<HummlistColors> {
  const HummlistColors({
${colorNames.map((k) => `    required this.${camel(k)},`).join('\n')}
  });

${colorNames.map((k) => `${doc(tokens.color.light[k])}  final Color ${camel(k)};`).join('\n')}

  static const light = HummlistColors(
${dartColors('light')}
  );

  static const dark = HummlistColors(
${dartColors('dark')}
  );

  static HummlistColors of(Brightness brightness) => switch (brightness) {
    Brightness.light => light,
    Brightness.dark => dark,
  };

  @override
  HummlistColors copyWith() => this;

  @override
  HummlistColors lerp(HummlistColors? other, double t) {
    if (other == null) {
      return this;
    }
    return HummlistColors(
${colorNames.map((k) => `      ${camel(k)}: Color.lerp(${camel(k)}, other.${camel(k)}, t)!,`).join('\n')}
    );
  }
}

abstract final class HlFont {
${dartFonts}
}

abstract final class HlType {
${dartType}
}

abstract final class HlSpace {
${dims('HlSpace', tokens.space, 's')}
}

abstract final class HlRadius {
${dims('HlRadius', tokens.radius)}
}

abstract final class HlBorder {
${dims('HlBorder', tokens.border)}
}

abstract final class HlShadow {
${dartShadows}
}

abstract final class HlDepth {
${dims('HlDepth', tokens.depth)}
}

abstract final class HlFocus {
${dims('HlFocus', tokens.focus.ring, 'ring-')}
}

abstract final class HlSize {
${dims('HlSize', tokens.size)}
}

abstract final class HlHex {
${doc(hex.tip)}  static const double tip = ${num(value(hex.tip))};
${doc(hex['reference-height'])}  static const double referenceHeight = ${num(px(value(hex['reference-height'])))};
${doc(hex['corner-radius'])}  static const double cornerRadius = ${num(px(value(hex['corner-radius'])))};
}

abstract final class HlDuration {
${dartDurations}
}

abstract final class HlEasing {
${dartCurves}
}
`;


// ---- Home Screen widgets (job 63): the colours only, light and dark ----
const generated = 'Generated from design/tokens/hummlist.tokens.json by design/tokens/build.mjs. Do not edit.';
const rgb = (mode, k) => `0x${colorHex(value(tokens.color[mode][k])).slice(1)}`;
const swift = `// ${generated}
import SwiftUI
import UIKit

/// Every colour token, switching with the widget's light or dark appearance.
enum HummlistColors {
${colorNames.map((k) => `  static let ${camel(k)} = dynamic(light: ${rgb('light', k)}, dark: ${rgb('dark', k)})`).join('\n')}

  private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
  }

  private static func rgb(_ value: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((value >> 16) & 0xff) / 255,
      green: CGFloat((value >> 8) & 0xff) / 255,
      blue: CGFloat(value & 0xff) / 255,
      alpha: 1)
  }
}
`;
const androidColors = (mode) => `<?xml version="1.0" encoding="utf-8"?>
<!-- ${generated} -->
<resources>
${colorNames.map((k) => `    <color name="hl_${k.replace(/-/g, '_')}">${colorHex(value(tokens.color[mode][k]))}</color>`).join('\n')}
</resources>
`;
const androidRes = 'app/android/app/src/main/res';

const outputs = [
  // dart format puts a blank line before a doc comment that follows a member, not after a brace.
  ['app/lib/design/tokens.g.dart', dart.replace(/\{\n\n/g, '{\n').replace(/\n\n\n/g, '\n\n')],
  ['site/public/tokens.css', css],
  ['app/web/join/tokens.css', css],
  ['app/ios/HomeWidget/HummlistColors.swift', swift],
  [`${androidRes}/values/hummlist_tokens.xml`, androidColors('light')],
  [`${androidRes}/values-night/hummlist_tokens.xml`, androidColors('dark')],
];

const check = process.argv.includes('--check');
let stale = 0;
for (const [path, content] of outputs) {
  const file = join(root, path);
  const current = existsSync(file) ? readFileSync(file, 'utf8') : null;
  if (current === content) continue;
  if (check) {
    console.error(`${path} is stale: run node design/tokens/build.mjs`);
    stale++;
  } else {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
    console.log(`wrote ${relative(root, file)}`);
  }
}
process.exit(stale ? 1 : 0);
