// Builds the site against the fixture release record test/fixtures/history-record.json (three
// public releases, job 105), so /history can be looked at and run through checks/ before there is
// a public release. The real content, the real flags; only the record is the fixture's.
//
//   node scripts/history-fixture.mjs [outDir] [--long-name]   # default dist-history/ (git-ignored), then e.g.
//   cd checks && node crawl.mjs ../dist-history && node contrast.mjs ../dist-history --pages /history,/en/history
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { build } from '../build.mjs';

const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_DIR = join(SITE_DIR, '..');
export const HISTORY_FIXTURE = join(SITE_DIR, 'test/fixtures/history-record.json');

const args = process.argv.slice(2);
// --long-name: a contributor with the longest name and a 37-character login, to prove nothing scrolls sideways.
const longName = args.includes('--long-name');
const outDir = resolve(args.find((a) => !a.startsWith('--')) ?? join(SITE_DIR, 'dist-history'));
const repo = mkdtempSync(join(tmpdir(), 'snacklist-history-'));
try {
  for (const rel of ['releases/flags.json', 'app/pubspec.yaml', 'docs/api/openapi.yaml']) {
    mkdirSync(dirname(join(repo, rel)), { recursive: true });
    cpSync(join(REPO_DIR, rel), join(repo, rel));
  }
  const record = readFileSync(HISTORY_FIXTURE, 'utf8');
  writeFileSync(
    join(repo, 'releases/releases.json'),
    longName ? record.replaceAll('"Mia Brandt"', '"Maximiliane Schwarzenberger-Lüdenscheid"').replaceAll('"mia-brandt"', '"maximiliane-schwarzenberger-luedensch"') : record,
  );
  const { routes, live } = build({ outDir, repoDir: repo, env: { VERCEL_ENV: process.env.VERCEL_ENV } });
  console.log(`live version: ${live.live} (from the fixture record)`);
  console.log(`built ${routes.length} pages into ${outDir}`);
} finally {
  rmSync(repo, { recursive: true, force: true });
}
