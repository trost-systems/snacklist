#!/usr/bin/env node
// Builds the demo videos from the takes in <video>/footage/<lang>/ (capture/take.ts):
//
//   node build.mjs [video ...] [--lang de,en] [--format wide,compact] [--step project,check,render,encode]
//
// project: writes one HyperFrames project per video, language and format to out/<name>/
// check:   `hyperframes check --json` (fails on errors) and `snapshot --review`
// render:  `hyperframes render` to out/<name>/master.mp4
// encode:  the web files, poster and captions into site/public/media/ (media/README.md names)
//
// Nothing here touches the network: GSAP, tokens and fonts are copied into each project.

import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { vtt } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '../..');
const media = join(repo, 'site/public/media');
const VIDEOS = ['add-tick', 'household-sync', 'mcp-chat'];

const args = process.argv.slice(2);
const opt = (name, all) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1].split(',') : all;
};
const videos = args.filter((a, i) => !a.startsWith('--') && !args[i - 1]?.startsWith('--'));
const langs = opt('lang', ['de', 'en']);
const fmts = opt('format', ['wide', 'compact']);
const steps = opt('step', ['project', 'check', 'render', 'encode', 'review']);

const run = (cmd, argv, opts = {}) => {
  console.error(`$ ${cmd} ${argv.join(' ')}`);
  return execFileSync(cmd, argv, { stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: 1 << 28, ...opts }).toString();
};
const hf = (cwd, argv) => run(join(here, 'node_modules/.bin/hyperframes'), argv, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });

const flutterFonts = join(process.env.HOME, 'flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');

function assets(dir) {
  const a = join(dir, 'assets');
  mkdirSync(join(a, 'fonts'), { recursive: true });
  copyFileSync(join(repo, 'site/public/tokens.css'), join(a, 'tokens.css'));
  copyFileSync(join(here, 'video.css'), join(a, 'video.css'));
  copyFileSync(join(repo, 'site/public/hex/hex-pointy.svg'), join(a, 'hex-pointy.svg'));
  copyFileSync(join(repo, 'site/public/favicon.svg'), join(a, 'hummlist-icon.svg'));
  copyFileSync(join(here, 'node_modules/gsap/dist/gsap.min.js'), join(a, 'gsap.min.js'));
  for (const f of ['bricolage-grotesque-latin-standard-normal.woff2', 'inter-latin-wght-normal.woff2']) {
    copyFileSync(join(repo, 'site/public/fonts', f), join(a, 'fonts', f));
  }
  copyFileSync(flutterFonts, join(a, 'fonts/MaterialIcons-Regular.otf'));
  return a;
}

/** The take's footage as seekable H.264 (Chrome cannot decode the capture's 4:4:4). */
function footage(video, lang, a) {
  const src = join(here, video, 'footage', lang);
  for (const f of Object.keys(JSON.parse(readFileSync(join(src, 'take.json'), 'utf8')).offsets)) {
    const mkv = join(src, `${f}.mkv`);
    const mp4 = join(src, `${f}.mp4`);
    if (!existsSync(mp4) || statSync(mp4).mtimeMs < statSync(mkv).mtimeMs) {
      run('ffmpeg', ['-loglevel', 'error', '-y', '-i', mkv, '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '12', '-pix_fmt', 'yuv420p', '-g', '15', '-movflags', '+faststart', mp4]);
    }
    copyFileSync(mp4, join(a, `${f}.mp4`));
  }
}

function encode(video, lang, fmt, dir, p) {
  const name = `${video}-${lang}-${fmt}`;
  const master = join(dir, 'master.mp4');
  const base = join(media, name);
  // Sizes per media/README.md: about 1.5 to 3 MB per file.
  run('ffmpeg', ['-loglevel', 'error', '-y', '-i', master, '-an', '-c:v', 'libx264', '-preset', 'slow', '-crf', '24', '-pix_fmt', 'yuv420p',
    '-profile:v', 'high', '-movflags', '+faststart', '-r', '30', `${base}.mp4`]);
  run('ffmpeg', ['-loglevel', 'error', '-y', '-i', master, '-an', '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '38', '-row-mt', '1',
    '-deadline', 'good', '-cpu-used', '2', '-pix_fmt', 'yuv420p', '-r', '30', `${base}.webm`]);
  // Poster: the beat that tells the story alone, at twice the shown size, WebP under 120 KB.
  const size = fmt === 'wide' ? '1152:648' : '716:896';
  const png = join(dir, 'poster.png');
  run('ffmpeg', ['-loglevel', 'error', '-y', '-ss', String(p.poster), '-i', master, '-frames:v', '1', '-vf', `scale=${size}:flags=lanczos`, png]);
  for (const q of [90, 85, 80, 75, 70, 65, 60]) {
    run('ffmpeg', ['-loglevel', 'error', '-y', '-i', png, '-c:v', 'libwebp', '-quality', String(q), '-compression_level', '6', `${base}.webp`]);
    if (statSync(`${base}.webp`).size < 120_000) break;
  }
  rmSync(`${base}-dark.webp`, { force: true });
}

/**
 * The review set (research §2.5, hummlist-ui-craft review.md): HyperFrames' review sheets, eight
 * frames across ±0.5 s of every beat, a contact sheet and the seam from the RENDERED file, and
 * ffprobe of every web file. Writes out/<name>/review/.
 */
function review(video, lang, fmt, dir, p) {
  const r = join(dir, 'review');
  rmSync(r, { recursive: true, force: true });
  mkdirSync(r, { recursive: true });
  hf(dir, ['snapshot', '--review', '-o', join(r, 'hyperframes')]);
  for (const [beat, at] of Object.entries(p.beats)) {
    const from = Math.max(0, at - 0.5);
    const to = Math.min(p.duration - 1 / 30, at + 0.5);
    hf(dir, ['snapshot', '--range', `${from.toFixed(3)},${to.toFixed(3)}`, '--frames', '8', '--no-end', '-o', join(r, `beat-${beat}`)]);
  }
  const master = join(dir, 'master.mp4');
  const tile = fmt === 'wide' ? 'scale=480:-2,tile=6x4' : 'scale=270:-2,tile=8x3';
  run('ffmpeg', ['-loglevel', 'error', '-y', '-i', master, '-vf', `fps=2,${tile}`, '-frames:v', '1', join(r, 'contact.png')]);
  run('ffmpeg', ['-loglevel', 'error', '-y', '-i', master, '-vf', 'select=eq(n\\,0)', '-frames:v', '1', join(r, 'first.png')]);
  run('ffmpeg', ['-loglevel', 'error', '-y', '-sseof', '-0.04', '-i', master, '-frames:v', '1', join(r, 'last.png')]);
  const seam = spawnSync('ffmpeg', ['-hide_banner', '-i', join(r, 'first.png'), '-i', join(r, 'last.png'), '-lavfi', 'ssim', '-f', 'null', '-']).stderr;
  const probe = (file) => {
    const j = JSON.parse(run('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_name,width,height,pix_fmt,r_frame_rate,codec_type', '-show_entries', 'format=duration,size', '-of', 'json', file]));
    const v = j.streams.find((s) => s.codec_type === 'video');
    return { file: file.replace(`${repo}/`, ''), codec: v.codec_name, size: `${v.width}x${v.height}`, pix: v.pix_fmt, fps: v.r_frame_rate, duration: Number(j.format.duration).toFixed(2), bytes: Number(j.format.size), audio: j.streams.some((s) => s.codec_type === 'audio') };
  };
  const base = join(media, `${video}-${lang}-${fmt}`);
  const summary = {
    seamSsim: Number(/All:([0-9.]+)/.exec(seam.toString() + '')?.[1] ?? NaN),
    files: [probe(master), probe(`${base}.mp4`), probe(`${base}.webm`)],
    poster: { file: `${base}.webp`.replace(`${repo}/`, ''), bytes: statSync(`${base}.webp`).size, at: p.poster },
    beats: p.beats,
    latency: p.latency ?? null,
  };
  writeFileSync(join(r, 'summary.json'), JSON.stringify(summary, null, 1));
}

/** The name is always "Hummlist" in full (research pitfall 19), in every source and page. This file holds the pattern and is not scanned. */
function brandGate(files) {
  const bad = [];
  for (const f of files) {
    readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
      if (/humm(?!list)/i.test(line) || /HummList|Hum list/.test(line)) bad.push(`${f.replace(`${repo}/`, '')}:${i + 1}: ${line.trim()}`);
    });
  }
  if (bad.length) throw new Error(`brand gate: write "Hummlist" in full\n${bad.join('\n')}`);
}

const sources = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  ['footage', 'out', 'node_modules', 'build.mjs'].includes(e.name) ? []
    : e.isDirectory() ? sources(join(dir, e.name))
    : /\.(mjs|ts|json|css|md)$/.test(e.name) && e.name !== 'package-lock.json' ? [join(dir, e.name)] : []);
brandGate([...sources(here), join(repo, 'test/fixtures/scenarios/demo-familie.yaml'), join(repo, 'test/fixtures/scenarios/demo-family-en.yaml')]);

for (const video of videos.length ? videos : VIDEOS) {
  const scene = await import(join(here, video, 'scene.mjs'));
  for (const lang of langs) {
    const fdir = join(here, video, 'footage', lang);
    const take = JSON.parse(readFileSync(join(fdir, 'take.json'), 'utf8'));
    const events = JSON.parse(readFileSync(join(fdir, 'events.json'), 'utf8'));
    const p = scene.plan(take, events, lang);
    for (const fmt of fmts) {
      const name = `${video}-${lang}-${fmt}`;
      const dir = join(here, 'out', name);
      if (steps.includes('project')) {
        mkdirSync(dir, { recursive: true });
        const a = assets(dir);
        footage(video, lang, a);
        writeFileSync(join(dir, 'index.html'), scene.compose({ fmt, lang, take, events, p }));
        brandGate([join(dir, 'index.html')]);
        writeFileSync(join(dir, 'plan.json'), JSON.stringify(p, null, 1));
      }
      if (steps.includes('check')) {
        let out;
        try {
          out = hf(dir, ['check', '--json']);
        } catch (e) {
          out = e.stdout?.toString() ?? '{}';
        }
        const report = JSON.parse(out || '{}');
        writeFileSync(join(dir, 'check.json'), JSON.stringify(report, null, 1));
        const errors = [];
        JSON.stringify(report, (k, v) => (v && v.severity === 'error' && errors.push(v), v));
        if (report.ok === false || errors.length) {
          console.error(JSON.stringify(errors.length ? errors : report, null, 1));
          throw new Error(`${name}: hyperframes check failed`);
        }
      }
      if (steps.includes('render')) {
        hf(dir, ['render', '--no-low-memory-mode', '--workers', '6', '--quality', 'delivery', '-o', 'master.mp4']);
      }
      if (steps.includes('encode')) encode(video, lang, fmt, dir, p);
      if (steps.includes('review')) review(video, lang, fmt, dir, p);
    }
    if (steps.includes('encode')) writeFileSync(join(media, `${video}-${lang}.vtt`), vtt(p.cues));
  }
}
