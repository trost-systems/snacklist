#!/usr/bin/env node
// Tables from the review sets (build.mjs --step review): ffprobe of every file, the seam, the
// poster and the measured latencies. Writes them into each <video>/REVIEW.md between the
// "<!-- report -->" markers, and prints the whole set (for the PR body) to stdout.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const VIDEOS = ['add-tick', 'household-sync', 'mcp-chat'];
const CUTS = ['de-wide', 'de-compact', 'en-wide', 'en-compact'];
const kb = (b) => `${(b / 1024).toFixed(0)} KB`;

function table(video) {
  const rows = ['| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |', '| --- | --- | --- | --- | --- | --- | --- | --- |'];
  const seams = ['| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |', '| --- | --- | --- | --- |'];
  const lat = [];
  for (const cut of CUTS) {
    const s = JSON.parse(readFileSync(join(here, 'out', `${video}-${cut}`, 'review', 'summary.json'), 'utf8'));
    for (const f of s.files) {
      const name = f.file.includes('/out/') ? 'master (render)' : f.file.split('/').pop();
      rows.push(`| ${cut} | ${name} | ${f.codec} ${f.pix} | ${f.size} | ${f.fps} | ${f.duration} s | ${kb(f.bytes)} | ${f.audio ? 'yes' : 'none'} |`);
    }
    seams.push(`| ${cut} | ${s.seamSsim.toFixed(4)} | ${s.poster.file.split('/').pop()}, ${kb(s.poster.bytes)} | ${s.poster.at.toFixed(2)} s |`);
    if (s.latency && cut.endsWith('wide')) lat.push(`- ${cut.slice(0, 2).toUpperCase()}: ${Object.entries(s.latency).map(([k, v]) => `${k} ${v} ms`).join(', ')}`);
  }
  return [rows.join('\n'), '', seams.join('\n'), ...(lat.length ? ['', 'Measured in the takes (Marionette polls, so an upper bound for the app side):', '', ...lat] : [])].join('\n');
}

const all = [];
for (const video of VIDEOS) {
  const t = table(video);
  all.push(`### ${video}\n\n${t}\n`);
  const file = join(here, video, 'REVIEW.md');
  const text = readFileSync(file, 'utf8');
  const start = text.indexOf('<!-- report -->');
  const end = text.indexOf('<!-- /report -->');
  if (start < 0 || end < 0) throw new Error(`${file} has no <!-- report --> block`);
  writeFileSync(file, `${text.slice(0, start)}<!-- report -->\n${t}\n${text.slice(end)}`);
}
console.log(all.join('\n'));
