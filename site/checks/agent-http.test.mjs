// node --test agent-http.test.mjs (after `npm run build` in site/): the built site served like
// Vercel serves it, then copies broken one way each, so each check is proven to fail.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { readPublicApi } from '../agent.mjs';
import { checkServed } from './agent-http.mjs';
import { serve } from './lib.mjs';

const SITE = resolve(import.meta.dirname, '..');
const DIST = join(SITE, 'dist');
const { siteUrl } = JSON.parse(readFileSync(join(SITE, 'config.json'), 'utf8'));

async function served(dist, publicApi = false) {
  const site = await serve(dist);
  try {
    return await checkServed({ origin: site.origin, siteUrl, publicApi });
  } finally {
    await site.close();
  }
}

function distWith(edits) {
  const dist = join(mkdtempSync(join(tmpdir(), 'agent-http-')), 'dist');
  cpSync(DIST, dist, { recursive: true });
  for (const [rel, edit] of Object.entries(edits)) {
    if (edit === null) rmSync(join(dist, rel), { force: true });
    else writeFileSync(join(dist, rel), edit(readFileSync(join(dist, rel), 'utf8')));
  }
  return dist;
}

const catches = async (edits, check, pattern, publicApi) => {
  const { problems } = await served(distWith(edits), publicApi);
  assert.ok(problems.some((p) => p.check === check && pattern.test(`${p.url} ${p.message}`)), JSON.stringify(problems, null, 1));
};

test('the built site serves every agent file, llms.txt link and sitemap URL', async () => {
  assert.ok(existsSync(join(DIST, 'llms.txt')), 'build the site first: cd site && npm run build');
  const publicApi = readPublicApi(join(SITE, '..'));
  const { problems, skipped } = await served(DIST, publicApi);
  assert.deepEqual(problems, []);
  assert.deepEqual(skipped, publicApi ? [] : [{ check: 'openapi', reason: 'public-api rollout is off in releases/flags.json' }]);
});

test('a twin listed in llms.txt that is gone fails', () => catches({ 'en/guides/claude.md': null }, 'llms-txt', /\/en\/guides\/claude\.md answers 404/));
test('a missing agent file fails', () => catches({ 'robots.txt': null }, 'agent-files', /\/robots\.txt answers 404/));
test('a sitemap URL that is not served fails', () =>
  catches({ 'sitemap.xml': (xml) => xml.replace('/en/guides/claude<', '/en/guides/nope<') }, 'sitemap', /\/en\/guides\/nope answers 404/));
test('a sitemap URL serving another canonical URL fails', () =>
  catches({ 'en/privacy.html': (html) => html.replace('<link rel="canonical" href="https://snacklist.app/en/privacy">', '<link rel="canonical" href="https://snacklist.app/en/privacy-old">') }, 'sitemap', /canonical URL is https:\/\/snacklist\.app\/en\/privacy-old/));
test('with the public API on, a missing openapi.yaml fails', () => catches({ 'openapi.yaml': null }, 'openapi', /\/openapi\.yaml answers 404/, true));
