import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { request } from 'node:http';
import { after } from 'node:test';
import { parse } from 'node-html-parser';
import { build, readConfig } from '../build.mjs';
import { dayNumber } from '../releases.mjs';
import { startPreview } from '../scripts/preview.mjs';

export const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CONTENT_DIR = join(SITE_DIR, 'content');
export const REPO_DIR = join(SITE_DIR, '..');
export const REAL_RECORD = readFileSync(join(REPO_DIR, 'releases/releases.json'), 'utf8');
export const REAL_PUBSPEC = readFileSync(join(REPO_DIR, 'app/pubspec.yaml'), 'utf8');

const temps = [];
after(() => temps.forEach((d) => rmSync(d, { recursive: true, force: true })));

export function tempDir() {
  const dir = mkdtempSync(join(tmpdir(), 'hummlist-site-'));
  temps.push(dir);
  return dir;
}

// The files the build reads from outside site/: the real ones unless given, null for missing.
// `drafts` maps a file name in releases/changelog/ to its text (today's repo has none).
export function repoDir({ record = REAL_RECORD, pubspec = REAL_PUBSPEC, drafts = {} } = {}) {
  const dir = tempDir();
  const draftFiles = Object.entries(drafts).map(([name, text]) => [`releases/changelog/${name}`, text]);
  for (const [rel, text] of [['releases/releases.json', record], ['app/pubspec.yaml', pubspec], ...draftFiles]) {
    if (text === null) continue;
    mkdirSync(dirname(join(dir, rel)), { recursive: true });
    writeFileSync(join(dir, rel), text);
  }
  return dir;
}

// The real record with one valid public release per version, oldest first.
export function record(versions, patch = (data) => data) {
  const data = JSON.parse(REAL_RECORD);
  let previous = null;
  data.releases = versions.map((version, i) => {
    const date = `2026-11-${String(i + 1).padStart(2, '0')}`;
    const sha = (i + 1).toString(16).padStart(40, 'a');
    const release = {
      version,
      channel: 'public',
      date,
      day: dayNumber(data.project.day_zero, date),
      build: i + 1,
      sha,
      previous_sha: previous,
      stores: { app_store: true, play: true, web: true },
      stats: { commits: 1, additions: 1, deletions: 0, files_changed: 1, contributors: [] },
      notes: { de: `Version ${version}`, en: `Version ${version}` },
    };
    previous = sha;
    return release;
  });
  return `${JSON.stringify(patch(data), null, 2)}\n`;
}

// Builds the real content plus `files` (path relative to content/ -> text, or null to delete),
// against `repo` (see repoDir).
export function buildSite({ files = {}, env = {}, config = {}, repo = {}, publicDir } = {}) {
  const root = tempDir();
  const contentDir = join(root, 'content');
  const outDir = join(root, 'dist');
  cpSync(CONTENT_DIR, contentDir, { recursive: true });
  for (const [rel, text] of Object.entries(files)) {
    const file = join(contentDir, rel);
    if (text === null) rmSync(file);
    else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, text);
    }
  }
  const result = build({ contentDir, outDir, publicDir, repoDir: repoDir(repo), env, config: { ...readConfig(), ...config } });
  return { ...result, outDir, page: (route) => readPage(outDir, route) };
}

export function readPage(outDir, route) {
  const file = route === '/' ? 'index.html' : `${route.slice(1)}.html`;
  return parse(readFileSync(join(outDir, file), 'utf8'));
}

export function htmlRoutes(outDir) {
  return readdirSync(outDir, { recursive: true })
    .filter((f) => f.endsWith('.html'))
    .map((f) => (f === 'index.html' ? '/' : `/${f.slice(0, -5)}`));
}

// A copy of public/ plus `files` (path relative to public/ -> Buffer or text, or null to delete).
export function publicWith(files) {
  const dir = join(tempDir(), 'public');
  cpSync(join(SITE_DIR, 'public'), dir, { recursive: true });
  for (const [rel, data] of Object.entries(files)) {
    const file = join(dir, rel);
    if (data === null) rmSync(file);
    else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, data);
    }
  }
  return dir;
}

// `since` goes in unquoted, so `since: 1.4` is the number YAML makes of it.
export function guide({ locale, slug, title = `Title ${slug}`, description = `Description ${slug}`, key = slug, body = `# ${title}\n\nText.\n`, omit = [], since }) {
  const fields = { title, description, slug, locale, translation_key: key, updated: '2026-10-01' };
  const lines = Object.entries(fields).filter(([k]) => !omit.includes(k)).map(([k, v]) => `${k}: "${v}"`);
  if (since !== undefined) lines.push(`since: ${since}`);
  return `---\n${lines.join('\n')}\n---\n\n${body}`;
}

export function legal({ locale, path, key, title = `Legal ${key}`, body = `# ${title}\n\nText.\n` }) {
  return `---\ntitle: "${title}"\ndescription: "About ${key}"\nlocale: ${locale}\npath: ${path}\ntranslation_key: ${key}\nupdated: 2026-10-01\n---\n\n${body}`;
}

export const hrefs = (doc, selector = 'a') => doc.querySelectorAll(selector).map((a) => a.getAttribute('href'));
export const meta = (doc, key) => doc.querySelector(`meta[property="${key}"], meta[name="${key}"]`)?.getAttribute('content');
export const alternates = (doc) =>
  Object.fromEntries(doc.querySelectorAll('link[rel="alternate"]').map((l) => [l.getAttribute('hreflang'), l.getAttribute('href')]));

const get = (base, path) =>
  new Promise((resolve, reject) => {
    request(base + path, (res) => {
      let body = '';
      res.setEncoding('utf8').on('data', (c) => (body += c)).on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    }).on('error', reject).end();
  });

// Serves `outDir` the way Vercel does (scripts/preview.mjs) and fetches `paths`.
export async function serve(outDir, paths) {
  const server = await startPreview({ dir: outDir, port: 0 });
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    return Object.fromEntries(await Promise.all(paths.map(async (p) => [p, await get(base, p)])));
  } finally {
    server.close();
  }
}
