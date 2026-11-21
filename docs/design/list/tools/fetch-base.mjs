// Copies every file of an earlier preview deployment into <out>, byte for byte, so the new preview keeps the old rounds.
// Usage: VERCEL_TOKEN=… node fetch-base.mjs <deployment id> <out>
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import process from 'node:process';

const team = 'team_IudIeLeFCx8U5zncDHnUOczr';
const [id, out] = process.argv.slice(2);
const token = process.env.VERCEL_TOKEN;
if (!id || !out || !token) {
  console.error('usage: VERCEL_TOKEN=… node fetch-base.mjs <deployment id> <out>');
  process.exit(64);
}
const api = async (path) => {
  const res = await fetch(`https://api.vercel.com${path}${path.includes('?') ? '&' : '?'}teamId=${team}`, { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return res.json();
};

const files = [];
const walk = (nodes, prefix) => {
  for (const n of nodes) {
    const p = prefix ? `${prefix}/${n.name}` : n.name;
    if (n.type === 'directory') walk(n.children ?? [], p);
    else files.push({ path: p.replace(/^src\//, ''), uid: n.uid });
  }
};
walk(await api(`/v6/deployments/${id}/files`), '');

let next = 0;
const worker = async () => {
  while (next < files.length) {
    const f = files[next++];
    const { data } = await api(`/v7/deployments/${id}/files/${f.uid}`);
    const bytes = Buffer.from(data, 'base64');
    const sha = createHash('sha1').update(bytes).digest('hex');
    if (sha !== f.uid) throw new Error(`${f.path}: sha1 ${sha} is not ${f.uid}`);
    await mkdir(dirname(join(out, f.path)), { recursive: true });
    await writeFile(join(out, f.path), bytes);
  }
};
await Promise.all([worker(), worker(), worker(), worker()]);
console.log(`fetched ${files.length} files of ${id}, every SHA-1 matches`);
