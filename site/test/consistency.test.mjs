import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import matter from 'gray-matter';
import { CONTENT_DIR, SITE_DIR } from './helpers.mjs';
import { readConfig } from '../build.mjs';

const REPO = join(SITE_DIR, '..');
const APP_WEB = join(REPO, 'app', 'web');
const contentFiles = () => readdirSync(CONTENT_DIR, { recursive: true }).filter((f) => f.endsWith('.md'));

// app.hummlist.com serves files from app/web as they are (vercel.json: cleanUrls false) and answers
// every other path with the Flutter app. A link to a static page there must name the real file,
// e.g. /konto-loeschen.html, or the reader lands in the app instead (review of job 24).
test('links to app.hummlist.com name a file the app host really serves', () => {
  const links = contentFiles().flatMap((file) =>
    [...readFileSync(join(CONTENT_DIR, file), 'utf8').matchAll(/https:\/\/app\.hummlist\.com(\/[^\s)\]"']*[^\s)\]"'.,])?/g)]
      .map((m) => ({ file, path: (m[1] ?? '/').split(/[?#]/)[0] })),
  );
  assert.ok(links.some((l) => l.path === '/konto-loeschen.html'), 'the help page links the deletion page');
  for (const { file, path } of links) {
    if (path === '/') continue;
    assert.ok(existsSync(join(APP_WEB, path)), `${file}: https://app.hummlist.com${path} is not a file in app/web (the app would open instead)`);
  }
});

// Publishing the help page flips three things together (docs/NEEDS_PETER.md, Job 24): the
// `draft: true` lines, `supportPublished` in config.json and `supportPagePublished` in the app.
// A half-publish would show the app's link to a 404 or hide a live page.
test('the help page, the footer flag and the app constant agree on published', () => {
  const drafts = ['legal/support.md', 'legal/support-en.md'].map(
    (f) => matter(readFileSync(join(CONTENT_DIR, f), 'utf8')).data.draft === true,
  );
  assert.equal(drafts[0], drafts[1], 'support.md and support-en.md publish together');
  const published = !drafts[0];
  assert.equal(readConfig().supportPublished, published, 'site/config.json supportPublished');
  const guides = readFileSync(join(REPO, 'app', 'lib', 'app', 'guides.dart'), 'utf8');
  const constant = /^const supportPagePublished = (true|false);$/m.exec(guides);
  assert.ok(constant, 'app/lib/app/guides.dart declares supportPagePublished');
  assert.equal(constant[1] === 'true', published, 'app/lib/app/guides.dart supportPagePublished');
});
