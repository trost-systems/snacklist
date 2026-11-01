#!/usr/bin/env node
// Films every homepage scene: each scene x {de, en} x {wide, compact} x {light, dark} as a
// still at 2x, written as WebP under 120 KB to site/public/media/, PNGs and one contact sheet
// per scene to /tmp/s53/scenes/. See README.md.
//
//   node site/scenes/film-all.mjs [scene...]   film all scenes, or the named ones
//   node site/scenes/film-all.mjs --serve      only serve site/ on 127.0.0.1:57610
import { createServer } from 'node:http';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCENES = {
  hero: { wide: [500, 540], compact: [358, 400] },
  'add-tick': { wide: [576, 324], compact: [358, 448] },
  'household-sync': { wide: [576, 324], compact: [358, 448] },
  'mcp-chat': { wide: [576, 324], compact: [358, 448] },
  stores: { wide: [576, 324], compact: [358, 448] },
};
const LOCALES = ['de', 'en'];
const THEMES = ['light', 'dark'];
const MAX_BYTES = 120 * 1024;
const PORT = 57610;

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..');
const repo = resolve(site, '..');
const film = join(repo, '.claude/skills/hummlist-ui-craft/film.mjs');
const media = join(site, 'public/media');
const shots = '/tmp/s53/scenes';

const flutterBin = realpathSync(execFileSync('which', ['flutter'], { encoding: 'utf8' }).trim());
const iconFont = resolve(dirname(flutterBin), 'cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
if (!existsSync(iconFont)) throw new Error(`Material Icons font not found at ${iconFont}; run flutter precache`);

const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.otf': 'font/otf', '.png': 'image/png', '.webp': 'image/webp' };
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = path === '/scenes/material-icons.otf' ? iconFont : join(site, path);
  if (!file.startsWith(site) && file !== iconFont) return void res.writeHead(403).end();
  if (!existsSync(file) || !statSync(file).isFile()) return void res.writeHead(404).end();
  res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file));
});
await new Promise((r) => server.listen(PORT, '127.0.0.1', r));

if (process.argv.includes('--serve')) {
  console.log(`serving ${site} on http://127.0.0.1:${PORT}/scenes/`);
} else {
  const names = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  for (const name of names) if (!SCENES[name]) throw new Error(`unknown scene ${name}`);
  mkdirSync(media, { recursive: true });
  mkdirSync(shots, { recursive: true });
  for (const name of names.length ? names : Object.keys(SCENES)) await filmScene(name);
  server.close();
}

async function filmScene(name) {
  const pngs = [];
  for (const [size, [width, height]] of Object.entries(SCENES[name])) {
    for (const locale of LOCALES) {
      for (const theme of THEMES) {
        const id = `${name}-${locale}-${size}${theme === 'dark' ? '-dark' : ''}`;
        const out = join(shots, id);
        const args = [film, `http://127.0.0.1:${PORT}/scenes/${name}.html?lang=${locale}`, '--out', out,
          '--still', '--width', String(width), '--height', String(height), '--scale', '2'];
        if (theme === 'dark') args.push('--dark');
        const log = await run(args);
        if (log.includes('[page]')) throw new Error(`${id}: page errors\n${log}`);
        pngs.push(`${out}.png`);
        console.log(`${id}.webp ${webp(`${out}.png`, join(media, `${id}.webp`))} KB`);
      }
    }
  }
  await run([film, 'sheet', ...pngs, '--out', join(shots, name), '--cols', '4']);
  console.log(`sheet: ${join(shots, name)}-sheet.png`);
}

// Encodes at the highest quality that stays under the budget.
function webp(png, target) {
  for (const quality of [90, 85, 80, 75, 70, 65, 60]) {
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', png, '-quality', String(quality), target]);
    const size = statSync(target).size;
    if (size <= MAX_BYTES) return `${(size / 1024).toFixed(0)} (q${quality})`;
  }
  throw new Error(`${target} stays over ${MAX_BYTES} bytes at quality 60`);
}

// Async, so the server in this process keeps answering while film.mjs runs.
function run(args) {
  return new Promise((ok, fail) => {
    const child = spawn(process.execPath, args, { cwd: repo });
    let log = '';
    child.stdout.on('data', (d) => (log += d));
    child.stderr.on('data', (d) => (log += d));
    child.on('close', (code) => (code === 0 ? ok(log) : fail(new Error(`film.mjs exited ${code}\n${log}`))));
  });
}
