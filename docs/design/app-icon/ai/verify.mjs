#!/usr/bin/env node
// Checks round AI: today's icon files are unchanged, each option's committed asset set is what
// the generator writes, measured.json is a fresh run, every option fits Android's safe circle,
// and every number the recommendation quotes matches measured.json.
//   node docs/design/app-icon/ai/verify.mjs
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, statSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { copy } from './copy.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../../../..');
const fails = [];
let checks = 0;
const ok = (cond, msg) => { checks++; if (!cond) fails.push(msg); };
const files = (dir) => readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? files(join(dir, n)) : [join(dir, n)]));
const tmp = mkdtempSync(join(tmpdir(), 'ai-verify-'));

try {
  execFileSync('node', ['design/app-icon/build.mjs', '--check'], { cwd: root, stdio: 'pipe' });
  ok(true, '');
} catch (e) {
  ok(false, `today's icon files changed: ${e.stderr}`);
}

const REQUIRED = [
  'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
  'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png',
  'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png',
  'app/ios/Runner/AppIcon.icon/icon.json',
  'app/android/app/src/main/res/drawable/ic_launcher_foreground.xml',
  'app/android/app/src/main/res/drawable/ic_launcher_background.xml',
  'app/android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
  'app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  'store/app-store-1024.png',
  'store/play-512.png',
];
for (const id of ['AI1', 'AI2', 'AI3', 'AI4', 'AI5']) {
  const want = join(tmp, id);
  execFileSync('node', ['design/app-icon/build.mjs', '--art', `design/app-icon/art/${id.toLowerCase()}.mjs`, '--out', want], { cwd: root, stdio: 'pipe' });
  const have = join(here, 'assets', id);
  const a = files(want).map((f) => relative(want, f)).sort();
  const b = files(have).map((f) => relative(have, f)).sort();
  ok(JSON.stringify(a) === JSON.stringify(b), `${id}: committed asset files differ from the generator's list`);
  for (const f of a) ok(b.includes(f) && readFileSync(join(want, f)).equals(readFileSync(join(have, f))), `${id}: ${f} is stale`);
  for (const f of REQUIRED) ok(a.includes(f), `${id}: ${f} missing`);
  const png = readFileSync(join(have, 'store/app-store-1024.png'));
  ok(png[25] === 2, `${id}: the App Store icon has an alpha channel`);
}

execFileSync('node', [join(here, 'tools/render.mjs'), join(tmp, 'page')], { stdio: 'pipe' });
const fresh = readFileSync(join(tmp, 'page/measured.json'), 'utf8');
ok(fresh === readFileSync(join(here, 'measured.json'), 'utf8'), 'measured.json is not a fresh run');
const m = JSON.parse(fresh);
for (const [id, v] of Object.entries(m)) ok(v.inside, `${id} leaves the 66 dp safe circle (${v.reachDp.toFixed(1)} dp)`);

// The recommendation's numbers, each against the value it claims.
const n1 = (v) => v.toFixed(1);
const n2 = (v) => v.toFixed(2);
const claims = [
  ['AI1 thinnest at 29 pt', n1(m.AI1.thinnest29), '2.0'],
  ['Today thinnest at 29 pt', n1(m.Today.thinnest29), '1.2'],
  ['AI1 tinted thinnest', n1(m.AI1.monoThinnest29), '2.0'],
  ['AI1 reach', n1(m.AI1.reachDp), '29.3'],
  ['AI3 thinnest above 9 px', String(m.AI3.thinnest29 > 9), 'true'],
  ['AI3 contrast', n2(m.AI3.keyLight), '6.85'],
  ['AI5 tile on light wallpaper', n2(m.AI5.tileOnWall.light), '1.10'],
  ['AI2 thinnest at 29 pt', n1(m.AI2.thinnest29), '0.6'],
  ['AI4 thinnest at 29 pt', n1(m.AI4.thinnest29), '1.9'],
];
for (const [what, got, quoted] of claims) ok(got === quoted, `recommendation quotes ${what} ${quoted}, measured ${got}`);
for (const lang of ['en', 'de']) {
  const text = copy.rec[lang].replace(/,(\d)/g, '.$1');
  for (const [, , quoted] of claims) if (quoted !== 'true') ok(text.includes(quoted), `${lang} recommendation no longer quotes ${quoted}`);
}

for (const lang of ['en', 'de']) {
  const md = execFileSync('node', [join(here, 'tools/approaches.mjs'), lang], { encoding: 'utf8' });
  ok(md === readFileSync(join(here, lang === 'en' ? 'RECOMMENDATION.md' : 'RECOMMENDATION.de.md'), 'utf8'), `RECOMMENDATION${lang === 'en' ? '' : '.de'}.md is stale: node tools/approaches.mjs ${lang}`);
}

rmSync(tmp, { recursive: true, force: true });
if (fails.length) {
  console.error(fails.join('\n'));
  console.error(`${fails.length} of ${checks} checks failed`);
  process.exit(1);
}
console.log(`all checks passed (${checks})`);
