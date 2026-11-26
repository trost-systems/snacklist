import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { CHECKS, checkAgentSite, readStage, readVercel } from '../agent.mjs';
import { buildSite, serve, tempDir, flagsWithPublicApi, REAL_OPENAPI, SITE_DIR } from './helpers.mjs';

const SITE = 'https://snacklist.app';
const FLAGS_ON = flagsWithPublicApi('full');
const VERCEL = readVercel();
const VERCEL_INDEXABLE = {
  ...VERCEL,
  headers: VERCEL.headers.map((rule) => ({ ...rule, headers: rule.headers.filter((h) => h.key !== 'X-Robots-Tag') })),
};

const base = buildSite();

// A copy of the real build with `edits` (path in dist -> text, a function of the old text, or null).
function distWith(edits = {}, from = base.outDir) {
  const dist = join(tempDir(), 'dist');
  cpSync(from, dist, { recursive: true });
  for (const [rel, edit] of Object.entries(edits)) {
    const file = join(dist, rel);
    if (edit === null) rmSync(file);
    else writeFileSync(file, typeof edit === 'function' ? edit(readFileSync(file, 'utf8')) : edit);
  }
  return dist;
}

const check = (dist, opts = {}) => checkAgentSite({ dist, siteUrl: SITE, vercel: VERCEL, stage: 'waitlist', publicApi: false, ...opts });
const reported = (result, id) => result.problems.filter((p) => p.check === id);
const read = (dist, rel) => readFileSync(join(dist, rel), 'utf8');

function assertCatches(id, edits, pattern, opts) {
  const problems = reported(check(distWith(edits), opts), id);
  assert.ok(problems.some((p) => pattern.test(`${p.file}: ${p.message}`)), `${id} reports ${pattern}, got ${JSON.stringify(problems)}`);
}

test('the real build has no problems and says why the openapi check is skipped', () => {
  const result = check(base.outDir);
  assert.deepEqual(result.problems, []);
  assert.deepEqual(result.skipped, [{ check: 'openapi', reason: 'public-api rollout is off in releases/flags.json' }]);
  assert.equal(existsSync(join(base.outDir, 'openapi.yaml')), false);
  assert.deepEqual(CHECKS.map((c) => c.id), ['md-twin', 'llms-txt', 'llms-full', 'robots', 'launch', 'hreflang', 'sitemap', 'jsonld', 'structure', 'links', 'openapi']);
});

test('the stage is read from config/stage.ts and must be one of the three', () => {
  assert.equal(readStage(), 'waitlist');
  const at = (line) => {
    const siteDir = tempDir();
    cpSync(join(SITE_DIR, 'config'), join(siteDir, 'config'), { recursive: true });
    writeFileSync(join(siteDir, 'config/stage.ts'), line);
    return readStage(siteDir);
  };
  assert.equal(at("export const stage: Stage = 'launch';\n"), 'launch');
  assert.throws(() => at("export const stage: Stage = 'live';\n"), /config\/stage\.ts: needs the line/);
});

test('a twin is the page as Markdown: h1 first, links absolute, alt texts kept, no video or icons, other language at the end', () => {
  const twin = read(base.outDir, 'en/guides/claude.md');
  assert.match(twin, /^# Connect Snacklist to Claude\n\n/);
  assert.match(twin, /\n---\n\nCanonical URL: https:\/\/snacklist\.app\/en\/guides\/claude\nMarkdown \(de\): https:\/\/snacklist\.app\/de\/anleitungen\/claude\.md\n$/);
  const landing = read(base.outDir, 'de.md');
  assert.doesNotMatch(landing, /<svg|<video|<button|\]\(\/(?!\/)/);
  assert.match(landing, /!\[[^\]]+\]\(https:\/\/snacklist\.app\/media\/hero-de-wide\.webp\)/);
  assert.match(landing, /\]\(https:\/\/snacklist\.app\/de#/, 'same-page anchors made absolute');
  assert.match(base.page('/de').querySelector('link[type="text/markdown"]').getAttribute('href'), /^\/de\.md$/);
});

test('llms.txt lists the guides, help and legal pages, and the rest under Optional', () => {
  const llms = read(base.outDir, 'llms.txt');
  assert.match(llms, /^# Snacklist\n\n> /);
  const sections = [...llms.matchAll(/^## (.+)$/gm)].map((m) => m[1]);
  assert.deepEqual(sections, ['Guides in English', 'Guides in German', 'Help', 'Comparisons', 'Legal', 'Optional']);
  assert.match(llms, /\n- \[Help and contact\]\(https:\/\/snacklist\.app\/en\/support\.md\): /);
  assert.match(llms, /## Optional\n[\s\S]*\(https:\/\/snacklist\.app\/llms-full\.txt\)/);
  assert.doesNotMatch(llms, /openapi|app\.(?:snacklist\.app|hummlist\.com)/);
  assert.match(read(base.outDir, 'robots.txt'), /^User-agent: \*\nAllow: \/\n\nSitemap: https:\/\/snacklist\.app\/sitemap\.xml\n$/);
});

test('md-twin: a public page without its twin, or a twin with another h1', () => {
  assertCatches('md-twin', { 'en/guides/claude.md': null }, /en\/guides\/claude\.md: missing/);
  assertCatches('md-twin', { 'de/anleitungen.md': (t) => t.replace(/^# .*/, '# Something else') }, /first line must be "# Anleitungen"/);
  assertCatches('md-twin', { 'impressum.html': (t) => t.replace(/<link rel="alternate" type="text\/markdown"[^>]*>/, '') }, /impressum\.html: head needs <link rel="alternate" type="text\/markdown" href="\/impressum\.md">/);
});

test('llms-txt: a heading level, a stray line, a foreign URL and an unlisted page', () => {
  assertCatches('llms-txt', { 'llms.txt': (t) => `${t}\n### Deeper\n` }, /only one H1 and then H2 sections/);
  assertCatches('llms-txt', { 'llms.txt': (t) => `${t}\nJust text in a section.\n` }, /a section holds only "- \[name\]\(url\)"/);
  assertCatches('llms-txt', { 'llms.txt': (t) => `${t}- [Elsewhere](https://example.com/x.md)\n` }, /the only external URL allowed is https:\/\/mcp\.snacklist\.app/);
  assertCatches('llms-txt', { 'llms.txt': (t) => t.replace(/^- \[Impressum\].*\n/m, '') }, /does not list https:\/\/snacklist\.app\/impressum\.md/);
  assertCatches('llms-txt', { 'llms.txt': (t) => t.replace('/en/guides/claude.md', '/en/guides/gone.md') }, /broken link https:\/\/snacklist\.app\/en\/guides\/gone\.md/);
  assertCatches('llms-txt', { 'llms.txt': (t) => `Intro\n${t}` }, /line 1: must start with one H1/);
});

test('llms-full: missing a listed twin, or another H1', () => {
  assertCatches('llms-full', { 'llms-full.txt': (t) => t.replace(read(base.outDir, 'en/imprint.md').trim(), '') }, /does not contain the twin https:\/\/snacklist\.app\/en\/imprint\.md/);
  assertCatches('llms-full', { 'llms-full.txt': (t) => t.replace(/^# Snacklist/, '# Other') }, /must start with llms\.txt's H1/);
});

test('robots: a Disallow over a noindex page fails for any group; the longer Allow or a tie keeps it crawlable', () => {
  assertCatches('robots', { 'robots.txt': (t) => t.replace('Allow: /', 'Disallow: /en/guides') }, /user-agent \* disallows \/en\/guides/);
  assertCatches('robots', { 'robots.txt': (t) => `User-agent: Googlebot\nUser-agent: Bingbot\nDisallow: /impressum\n\n${t}` }, /user-agent Googlebot, Bingbot disallows \/impressum/);
  assertCatches('robots', { 'robots.txt': 'User-agent: *\nAllow: /\n' }, /needs the line "Sitemap: https:\/\/snacklist\.app\/sitemap\.xml"/);
  const allowed = distWith({ 'robots.txt': (t) => t.replace('Allow: /', 'Disallow: /en\nAllow: /en/\nAllow: /en$\nDisallow: /de/*\nAllow: /de/*') });
  assert.deepEqual(reported(check(allowed), 'robots'), []);
});

test('launch: any noindex header fails at stage launch, the indexable vercel.json passes, other stages never check', () => {
  assertCatches('launch', {}, /site\/vercel\.json: stage is launch .*X-Robots-Tag noindex header of the rule "\/\(\.\*\)"/, { stage: 'launch' });
  assert.deepEqual(reported(check(base.outDir, { stage: 'launch', vercel: VERCEL_INDEXABLE }), 'launch'), []);
  assert.deepEqual(reported(check(base.outDir, { stage: 'waitlist' }), 'launch'), []);
  assertCatches('launch', { 'en/imprint.html': (t) => t.replace('<title>', '<meta name="robots" content="noindex">\n<title>') }, /en\/imprint\.html: stage is launch/, { stage: 'launch', vercel: VERCEL_INDEXABLE });
  assert.throws(() => buildSite({ stage: 'launch' }), /agent checks failed:\n {2}launch: site\/vercel\.json: /);
});

test('hreflang: a target in another language, and a target that does not link back', () => {
  assertCatches('hreflang', { 'impressum.html': (t) => t.replace('hreflang="en" href="https://snacklist.app/en/imprint"', 'hreflang="en" href="https://snacklist.app/datenschutz"') }, /hreflang="en" target https:\/\/snacklist\.app\/datenschutz has <html lang="de">/);
  assertCatches('hreflang', { 'en/privacy.html': (t) => t.replace('hreflang="de" href="https://snacklist.app/datenschutz"', 'hreflang="de" href="https://snacklist.app/impressum"') }, /datenschutz\.html: https:\/\/snacklist\.app\/en\/privacy does not link back/);
  assertCatches('hreflang', { 'en.html': (t) => t.replace(/<link rel="alternate" hreflang="x-default"[^>]*>/, '') }, /en\.html: alternates must include x-default/);
});

test('sitemap: a missing and an extra URL', () => {
  assertCatches('sitemap', { 'sitemap.xml': (t) => t.replace(/<url><loc>https:\/\/snacklist\.app\/en\/imprint<\/loc>.*\n/, '') }, /missing public page https:\/\/snacklist\.app\/en\/imprint$/);
  assertCatches('sitemap', { 'sitemap.xml': (t) => t.replace('</urlset>', '<url><loc>https://snacklist.app/en/guides/widget</loc></url>\n</urlset>') }, /lists https:\/\/snacklist\.app\/en\/guides\/widget, which is no public page/);
});

test('jsonld: support pages carry their FAQ, guides a TechArticle, landing pages a WebSite', () => {
  const ld = (route) => base.page(route).querySelectorAll('script[type="application/ld+json"]').map((s) => JSON.parse(s.innerHTML));
  const [faq] = ld('/en/support');
  assert.equal(faq['@type'], 'FAQPage');
  assert.deepEqual(faq.mainEntity.find((q) => q.name === 'How do I invite someone?'), {
    '@type': 'Question',
    name: 'How do I invite someone?',
    acceptedAnswer: { '@type': 'Answer', text: "Tap your household's name at the top left of the list, then Invite. Share the link or the code. An invite is valid for one person. Revoke open invites on the members page under Open invites." },
  });
  assert.deepEqual(faq.mainEntity.map((q) => q.name), base.page('/en/support').querySelectorAll('main h3').map((h) => h.text));
  assert.deepEqual(ld('/de/anleitungen/alexa').map((d) => [d['@type'], d.dateModified, d.inLanguage]), [['TechArticle', '2026-11-22', 'de']]);
  assert.deepEqual(ld('/en'), [{ '@context': 'https://schema.org', '@type': 'WebSite', name: 'Snacklist', url: `${SITE}/en`, inLanguage: 'en' }]);
});

test('jsonld: broken JSON, a missing property, an unknown type and FAQ questions out of step with the page', () => {
  const ldOf = (t) => /<script type="application\/ld\+json">([^<]*)<\/script>/.exec(t)[1];
  const swap = (rel, change) => ({ [rel]: (t) => t.replace(ldOf(t), change(ldOf(t))) });
  assertCatches('jsonld', swap('en/guides/claude.html', (j) => j.slice(1)), /en\/guides\/claude\.html: JSON-LD does not parse/);
  assertCatches('jsonld', swap('en/guides/claude.html', (j) => j.replace(/"dateModified":"[\d-]+",/, '')), /JSON-LD TechArticle needs "dateModified"/);
  assertCatches('jsonld', swap('en.html', (j) => j.replace('"WebSite"', '"Organization"')), /@type "Organization" is not one of WebSite, TechArticle, Article, BreadcrumbList, MobileApplication, FAQPage/);
  assertCatches('jsonld', swap('support.html', (j) => j.replace('Wie lade ich', 'Wie bitte lade ich')), /support\.html: FAQPage questions .* differ from the FAQ section's h3s/);
  assertCatches('jsonld', { 'en/support.html': (t) => t.replace(/<script type="application\/ld\+json">[^<]*<\/script>/, '') }, /has a FAQ section but no FAQPage JSON-LD/);
});

test('structure: an index missing a guide, a guide without intro or date, a FAQ question without "?"', () => {
  assertCatches('structure', { 'en/guides.html': (t) => t.replace(/<li><a href="\/en\/guides\/claude">.*?<\/li>/s, '') }, /en\/guides\.html: guide index does not list \/en\/guides\/claude/);
  assertCatches('structure', { 'en/guides/alexa.html': (t) => t.replace(/(<\/h1>\n(?:<p class="open-in-app" hidden>.*<\/p>\n)?)(?:<p>.*?<\/p>\n|<blockquote>[\s\S]*?<\/blockquote>\n)+/, '$1') }, /en\/guides\/alexa\.html: needs an intro paragraph/);
  assertCatches('structure', { 'en/guides/alexa.html': (t) => t.replace(/<time datetime="[^"]*">/, '<time>') }, /needs the updated date as <time datetime/);
  assertCatches('structure', { 'en/support.html': (t) => t.replace('<h3>How do I export my data?</h3>', '<h3>How to export your data</h3>') }, /FAQ question "How to export your data" must end with "\?"/);
});

test('links: a missing page or fragment in HTML, twins and llms-full.txt, and an odd scheme', () => {
  assertCatches('links', { 'en/imprint.html': (t) => t.replace('</main>', '<p><a href="/en/guides/claude#nowhere">x</a></p></main>') }, /en\/imprint\.html: link \/en\/guides\/claude#nowhere: en\/guides\/claude\.html has no id "nowhere"/);
  assertCatches('links', { 'en/imprint.md': (t) => `${t}\n[gone](https://snacklist.app/en/gone)\n` }, /en\/imprint\.md: broken link https:\/\/snacklist\.app\/en\/gone/);
  assertCatches('links', { 'llms-full.txt': (t) => `${t}\n[gone](https://snacklist.app/datenschutz#nichts)\n` }, /llms-full\.txt: link https:\/\/snacklist\.app\/datenschutz#nichts: datenschutz\.html has no id "nichts"/);
  assertCatches('links', { 'en/imprint.html': (t) => t.replace('</main>', '<p><a href="javascript:alert(1)">x</a></p></main>') }, /link javascript:alert\(1\) must be http\(s\) or mailto/);
});

test('openapi: with the flag on the build ships openapi.yaml and lists it; a broken $ref fails', () => {
  const on = buildSite({ repo: { flags: FLAGS_ON } });
  assert.equal(read(on.outDir, 'openapi.yaml'), REAL_OPENAPI);
  assert.match(read(on.outDir, 'llms.txt'), /\n## API\n\n- \[OpenAPI description\]\(https:\/\/snacklist\.app\/openapi\.yaml\): .*\n\n## Optional\n/);
  const result = check(on.outDir, { publicApi: true });
  assert.deepEqual(result, { problems: [], skipped: [] });
  const ref = /\$ref: ['"]?(#\/[^'"\s]+)/.exec(REAL_OPENAPI)[1];
  const broken = reported(check(distWith({ 'openapi.yaml': (t) => t.replace(ref, `${ref}Gone`) }, on.outDir), { publicApi: true }), 'openapi');
  assert.deepEqual(broken.map((p) => p.message), [`$ref ${ref}Gone does not resolve`]);
  const missing = reported(check(distWith({ 'openapi.yaml': null }, on.outDir), { publicApi: true }), 'openapi');
  assert.deepEqual(missing.map((p) => p.message), ['missing, but the public-api flag is on']);
});

test('the preview serves twins as Markdown and llms.txt as plain text, like vercel.json', async () => {
  const res = await serve(base.outDir, ['/de.md', '/en/guides/claude.md', '/llms.txt', '/llms-full.txt']);
  assert.equal(res['/de.md'].headers['content-type'], 'text/markdown; charset=utf-8');
  assert.equal(res['/en/guides/claude.md'].headers['content-type'], 'text/markdown; charset=utf-8');
  assert.equal(res['/llms.txt'].headers['content-type'], 'text/plain; charset=utf-8');
  assert.equal(res['/llms-full.txt'].status, 200);
  assert.equal(res['/llms.txt'].headers['x-robots-tag'], 'noindex', 'the noindex header stays until launch');
});
