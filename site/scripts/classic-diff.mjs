// Proves that a production build without HUMMLIST_WAITLIST still ships the site of <ref>
// (default origin/main): builds both with VERCEL_ENV=production and compares every file in dist/.
// The one allowed change is job 82's: /de and /en say noindex in the page, because vercel.json's
// X-Robots-Tag header now skips them. Usage: node scripts/classic-diff.mjs [ref]
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_DIR = join(SITE_DIR, '..');
const ref = process.argv[2] ?? 'origin/main';
const ALLOWED = { 'de.html': '<meta name="robots" content="noindex">', 'en.html': '<meta name="robots" content="noindex">' };

const root = mkdtempSync(join(tmpdir(), 'classic-diff-'));
try {
  execFileSync('sh', ['-c', `git -C "${REPO_DIR}" archive "${ref}" site releases app/pubspec.yaml | tar -x -C "${root}"`]);
  symlinkSync(join(SITE_DIR, 'node_modules'), join(root, 'site/node_modules'));
  const build = (siteDir, outDir) =>
    execFileSync(process.execPath, ['--input-type=module', '-e', `const { build } = await import(${JSON.stringify(join(siteDir, 'build.mjs'))}); build({ outDir: ${JSON.stringify(outDir)}, env: { VERCEL_ENV: 'production' } });`]);
  build(join(root, 'site'), join(root, 'before'));
  build(SITE_DIR, join(root, 'after'));
  const files = (dir) => readdirSync(dir, { recursive: true, withFileTypes: true }).filter((f) => f.isFile()).map((f) => join(f.parentPath, f.name).slice(dir.length + 1)).sort();
  const before = files(join(root, 'before'));
  const after = files(join(root, 'after'));
  const problems = [
    ...before.filter((f) => !after.includes(f)).map((f) => `${f}: missing now`),
    ...after.filter((f) => !before.includes(f)).map((f) => `${f}: new`),
  ];
  let allowed = 0;
  for (const file of before.filter((f) => after.includes(f))) {
    const a = readFileSync(join(root, 'before', file));
    const b = readFileSync(join(root, 'after', file));
    if (a.equals(b)) continue;
    const added = ALLOWED[file];
    const lines = (buf) => buf.toString('utf8').split('\n');
    const rest = lines(b).filter((line) => line !== added);
    if (added && lines(b).length === lines(a).length + 1 && rest.join('\n') === lines(a).join('\n')) allowed++;
    else problems.push(`${file}: differs`);
  }
  console.log(`classic production build vs ${ref}: ${before.length} files before, ${after.length} now, ${allowed} with the allowed noindex line`);
  if (problems.length > 0) {
    console.error(problems.join('\n'));
    process.exitCode = 1;
  } else console.log('same output');
} finally {
  rmSync(root, { recursive: true, force: true });
}
