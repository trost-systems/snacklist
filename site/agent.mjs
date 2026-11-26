// The site as AI agents read it (job 93): a Markdown twin of every page, llms.txt, llms-full.txt,
// sitemap.xml, robots.txt, JSON-LD and, with the public API on, openapi.yaml. The checks below read
// only the built dist/, the way an agent sees the site, so they catch what the generators miss.
import process from 'node:process';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';
import { parse } from 'node-html-parser';
import TurndownService from 'turndown';
import { gfm } from 'turndown-plugin-gfm';
import { matchesSource } from './scripts/preview.mjs';

const SITE_DIR = dirname(fileURLToPath(import.meta.url));
const SITE_NAME = 'Snacklist';
const MCP_URL = 'https://mcp.snacklist.app';
const STAGES = ['waitlist', 'beta', 'launch'];
const API_OFF = 'public-api rollout is off in releases/flags.json';

export class AgentError extends Error {}

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// The trademark lines a page carries when its text names the mark (Legal N-366): the build adds
// them to the footer, so no page can miss one, and to llms.txt and llms-full.txt.
export const MARKS = [
  {
    mark: /\balexa/i,
    de: 'Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.',
    en: 'Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates.',
  },
];

// The lines, in both languages, of the marks an agent file (llms.txt, llms-full.txt) names.
const marksIn = (text) => MARKS.filter(({ mark }) => mark.test(text)).flatMap((m) => [m.en, m.de]);

export const twinPath = (route) => `${route}.md`;

// Node 22 runs CI and can't import TypeScript, so the stage line is read as text.
// SITE_STAGE overrides it in preview and local builds only (job 370), so a preview can show the
// launch stage while the one-line change in stage.ts stays the production switch.
export function stageOverride(env = process.env) {
  const override = env.VERCEL_ENV === 'production' ? undefined : env.SITE_STAGE || undefined;
  if (override && !STAGES.includes(override)) throw new AgentError(`SITE_STAGE=${override}: allowed are ${STAGES.join(', ')}`);
  return override;
}

export function readStage(siteDir = SITE_DIR, env = process.env) {
  const override = stageOverride(env);
  if (override) return override;
  const file = join(siteDir, 'config/stage.ts');
  const stage = /^export const stage: Stage = '([a-z]+)';$/m.exec(readFileSync(file, 'utf8'))?.[1];
  if (!STAGES.includes(stage)) throw new AgentError(`${file}: needs the line "export const stage: Stage = '<${STAGES.join('|')}>';"`);
  return stage;
}

export function readPublicApi(repoDir) {
  const file = join(repoDir, 'releases/flags.json');
  let rollout;
  try {
    rollout = JSON.parse(readFileSync(file, 'utf8')).flags?.['public-api']?.rollout;
  } catch (error) {
    throw new AgentError(`cannot read ${file}: ${error.message}`);
  }
  if (typeof rollout !== 'string') throw new AgentError(`${file}: needs flags["public-api"].rollout`);
  return rollout !== 'off';
}

export const readVercel = (siteDir = SITE_DIR) => JSON.parse(readFileSync(join(siteDir, 'vercel.json'), 'utf8'));

// The FAQ is the h2 section with one of these titles (the help pages' own headings, so Legal's
// files stay untouched): each h3 a question, the elements up to the next h3 its answer.
export const FAQ_HEADINGS = ['Häufige Fragen', 'Common questions'];
export function faqOf(root) {
  const items = [];
  const heading = root.querySelectorAll('h2').find((h) => FAQ_HEADINGS.includes(h.text.trim()));
  for (let el = heading?.nextElementSibling; el && el.tagName !== 'H2'; el = el.nextElementSibling) {
    if (el.tagName === 'H3') items.push({ question: el.text.trim(), answer: '' });
    else if (items.length > 0) items.at(-1).answer = `${items.at(-1).answer} ${el.text}`.replace(/\s+/g, ' ').trim();
  }
  return items;
}

// schema.org types the site uses: which pages get one, and what each must carry.
const SCHEMAS = {
  WebSite: {
    required: ['name', 'url', 'inLanguage'],
    data: (page, url) => page.kind === 'landing' && { name: SITE_NAME, url, inLanguage: page.locale },
  },
  TechArticle: {
    required: ['headline', 'description', 'inLanguage', 'dateModified', 'url'],
    data: (page, url) =>
      page.kind === 'guide' && { headline: page.title, description: page.description, inLanguage: page.locale, dateModified: page.updated, url },
  },
  // Comparison pages: the article, its breadcrumb, and Snacklist itself, without any rating. The
  // compared product gets no markup of its own (no Product, Review or AggregateRating).
  Article: {
    required: ['headline', 'description', 'inLanguage', 'dateModified', 'url'],
    data: (page, url) =>
      page.kind === 'comparison' && {
        headline: page.title,
        description: page.description,
        inLanguage: page.locale,
        dateModified: page.updated,
        url,
        publisher: { '@type': 'Organization', name: SITE_NAME },
      },
  },
  BreadcrumbList: {
    required: ['itemListElement'],
    data: (page, url) =>
      page.kind === 'comparison' && {
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: SITE_NAME, item: url.slice(0, url.length - page.route.length) + `/${page.locale}` },
          { '@type': 'ListItem', position: 2, name: page.title, item: url },
        ],
      },
  },
  MobileApplication: {
    required: ['name', 'operatingSystem', 'applicationCategory'],
    data: (page, url) =>
      page.kind === 'comparison' && {
        name: SITE_NAME,
        operatingSystem: 'iOS, Android',
        applicationCategory: 'LifestyleApplication',
        inLanguage: ['de', 'en'],
        url: url.slice(0, url.length - page.route.length) + `/${page.locale}`,
      },
  },
  FAQPage: {
    required: ['mainEntity'],
    data: (page) => {
      const faq = faqOf(parse(page.body));
      return (
        faq.length > 0 && {
          mainEntity: faq.map(({ question, answer }) => ({ '@type': 'Question', name: question, acceptedAnswer: { '@type': 'Answer', text: answer } })),
        }
      );
    },
  },
};

// The head lines renderPage adds: the twin link and the page's JSON-LD.
export function agentHead(page, url) {
  const blocks = Object.entries(SCHEMAS).flatMap(([type, schema]) => {
    const data = schema.data(page, url);
    return data ? [{ '@context': 'https://schema.org', '@type': type, ...data }] : [];
  });
  return [
    `<link rel="alternate" type="text/markdown" href="${twinPath(page.route)}">\n`,
    // `<` escaped so no text can close the script element.
    ...blocks.map((data) => `<script type="application/ld+json">${JSON.stringify(data).replace(/</g, '\\u003c')}</script>\n`),
  ].join('');
}

const turndown = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced', bulletListMarker: '-', emDelimiter: '*' }).use(gfm);

const absolute = (href, siteUrl, route) => (href.startsWith('#') ? `${siteUrl}${route}${href}` : href.startsWith('/') ? `${siteUrl}${href}` : href);

// The page's <main> as Markdown: decoration out, links absolute, a demo video as its label; then
// the footer's trademark lines.
export function markdownTwin(route, html, siteUrl) {
  const doc = parse(html);
  const main = doc.querySelector('main');
  const h1 = main.querySelector('h1');
  const title = h1.text.trim();
  h1.remove();
  // The report form (job 275) is controls and messages, the app hand-off (job 462) a control for
  // phones; the page's text around them stays.
  for (const el of main.querySelectorAll('svg, button, track, source, script, [aria-hidden="true"], [data-report], .open-in-app')) el.remove();
  for (const video of main.querySelectorAll('video')) {
    const label = video.getAttribute('aria-label');
    video.replaceWith(label ? `<p>${escapeHtml(label)}</p>` : '');
  }
  for (const a of main.querySelectorAll('a[href]')) a.setAttribute('href', absolute(a.getAttribute('href'), siteUrl, route));
  for (const img of main.querySelectorAll('img[src]')) img.setAttribute('src', absolute(img.getAttribute('src'), siteUrl, route));
  const canonical = doc.querySelector('link[rel="canonical"]').getAttribute('href');
  const others = doc
    .querySelectorAll('link[rel="alternate"][hreflang]')
    .filter((l) => !['x-default', doc.querySelector('html').getAttribute('lang')].includes(l.getAttribute('hreflang')))
    .map((l) => `Markdown (${l.getAttribute('hreflang')}): ${l.getAttribute('href')}.md`);
  // Turndown indents the blank lines of loose list items.
  const body = turndown.turndown(main.innerHTML).replace(/^[ \t]+$/gm, '');
  // The footer's trademark lines (MARKS) belong to the page's text.
  const marks = doc.querySelectorAll('footer .marks').map((p) => `\n\n${p.text.trim()}`).join('');
  return `# ${title}\n\n${body}${marks}\n\n---\n\n${[`Canonical URL: ${canonical}`, ...others].join('\n')}\n`;
}

// llms.txt sections in order; a published page lands in the first that takes it.
const SECTIONS = [
  { title: 'Guides in English', takes: (p) => ['index', 'guide'].includes(p.kind) && p.locale === 'en' },
  { title: 'Guides in German', takes: (p) => ['index', 'guide'].includes(p.kind) && p.locale === 'de' },
  { title: 'Help', takes: (p) => p.group === 'page:support' },
  { title: 'Comparisons', takes: (p) => p.kind === 'comparison' },
  { title: 'Legal', takes: (p) => p.kind === 'page' },
  { title: 'Optional', takes: (p) => ['changelog', 'history', 'landing'].includes(p.kind) },
];
const KIND_ORDER = ['landing', 'index', 'guide', 'comparison', 'page', 'changelog', 'history'];
const LOCALE_ORDER = ['en', 'de'];
const pageOrder = (a, b) =>
  KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind) || LOCALE_ORDER.indexOf(a.locale) - LOCALE_ORDER.indexOf(b.locale) || a.title.localeCompare(b.title, 'en');

function llmsTxt(head, published, siteUrl, publicApi) {
  const item = (name, url, notes) => `- [${name}](${url}): ${notes}`;
  const sections = SECTIONS.map(({ title }) => ({
    title,
    items: published
      .filter((p) => SECTIONS.find((s) => s.takes(p)).title === title)
      .sort(pageOrder)
      .map((p) => ({ url: siteUrl + twinPath(p.route), line: item(p.title, siteUrl + twinPath(p.route), p.locale === 'de' ? `${p.description} (German)` : p.description) })),
  }));
  const api = publicApi ? [{ title: 'API', items: [{ line: item('OpenAPI description', `${siteUrl}/openapi.yaml`, 'The Snacklist REST API (/v1), OpenAPI 3') }] }] : [];
  const full = { line: item('llms-full.txt', `${siteUrl}/llms-full.txt`, 'Every page listed here in one Markdown file') };
  const all = [...sections.slice(0, -1), ...api, { ...sections.at(-1), items: [...sections.at(-1).items, full] }];
  const text = `${head.trim()}\n${all.map((s) => `\n## ${s.title}\n\n${s.items.map((i) => i.line).join('\n')}\n`).join('')}`;
  return { text, twins: all.flatMap((s) => s.items).filter((i) => i.url).map((i) => i.url) };
}

const escapeXml = (s) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

// Writes every agent file into outDir. `rendered` is build's [{ page, html }]; published pages
// are the ones without a notice (draft or unreleased), which carry noindex.
export function writeAgentFiles({ outDir, rendered, siteUrl, contentDir, repoDir, publicApi, stage }) {
  const twins = new Map();
  for (const { page, html } of rendered) {
    const file = join(outDir, twinPath(page.route).slice(1));
    const text = markdownTwin(page.route, html, siteUrl);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, text);
    twins.set(siteUrl + twinPath(page.route), text);
  }
  // The pages behind the waitlist's mail links (job 82) are noindex and no content to list.
  const published = rendered.map((r) => r.page).filter((p) => p.notices.length === 0 && !p.unlisted && p.kind !== 'waitlist');
  // While the waitlist is open, assistants also read how a sign-up works (Legal L-1, job 82).
  const waitlist = stage === 'waitlist' ? `\n${readFileSync(join(contentDir, 'llms-waitlist.md'), 'utf8')}` : '';
  const head = `${readFileSync(join(contentDir, 'llms.md'), 'utf8').trimEnd()}\n${waitlist}`;
  const plain = llmsTxt(head, published, siteUrl, publicApi);
  // llms.txt's sections hold only links, so its trademark lines close the head.
  const marks = marksIn(plain.text);
  const llms = marks.length === 0 ? plain : llmsTxt(`${head.trimEnd()}\n\n${marks.join('\n')}\n`, published, siteUrl, publicApi);
  writeFileSync(join(outDir, 'llms.txt'), llms.text);
  writeFileSync(join(outDir, 'llms-full.txt'), `${head.trim()}${marks.length === 0 ? '' : `\n\n${marks.join('\n')}`}\n${llms.twins.map((url) => `\n---\n\nURL: ${url}\n\n${twins.get(url)}`).join('')}`);
  const urls = published.map((p) => `<url><loc>${escapeXml(siteUrl + p.route)}</loc>${p.updated ? `<lastmod>${p.updated}</lastmod>` : ''}</url>`);
  writeFileSync(join(outDir, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n`);
  writeFileSync(join(outDir, 'robots.txt'), `User-agent: *\nAllow: /\n\nSitemap: ${siteUrl}/sitemap.xml\n`);
  if (publicApi) writeFileSync(join(outDir, 'openapi.yaml'), readFileSync(join(repoDir, 'docs/api/openapi.yaml')));
}

// --- Checks: dist/ as an agent sees it ---

const isFile = (path) => existsSync(path) && statSync(path).isFile();
const fileRoute = (file) => (file === 'index.html' ? '/' : `/${file.slice(0, -'.html'.length)}`);

export function loadSite({ dist, siteUrl, vercel, stage, publicApi }) {
  const files = readdirSync(dist, { recursive: true }).filter((f) => isFile(join(dist, f)));
  const pages = files
    .filter((f) => f.endsWith('.html'))
    .map((file) => {
      const doc = parse(readFileSync(join(dist, file), 'utf8'));
      const alternates = Object.fromEntries(
        doc.querySelectorAll('link[rel="alternate"][hreflang]').map((l) => [l.getAttribute('hreflang'), l.getAttribute('href')]),
      );
      return {
        file,
        route: fileRoute(file),
        doc,
        lang: doc.querySelector('html')?.getAttribute('lang'),
        canonical: doc.querySelector('link[rel="canonical"]')?.getAttribute('href') ?? siteUrl + fileRoute(file),
        alternates,
        noindex: /\bnoindex\b/i.test(doc.querySelector('meta[name="robots"]')?.getAttribute('content') ?? ''),
        // The root redirect and the 404 page are no content pages.
        special: file === 'index.html' || file === '404.html',
      };
    });
  const byFile = new Map(pages.map((p) => [p.file, p]));
  const read = (rel) => (isFile(join(dist, rel)) ? readFileSync(join(dist, rel), 'utf8') : null);
  // The dist file an internal URL serves (cleanUrls), or null for an external URL.
  const resolve = (href, fromRoute) => {
    const local = href === siteUrl ? '/' : href.startsWith(`${siteUrl}/`) ? href.slice(siteUrl.length) : href.startsWith('#') ? fromRoute + href : href;
    if (!local.startsWith('/') || local.startsWith('//')) return null;
    const [rawPath, fragment] = local.split('#');
    const path = decodeURIComponent(rawPath.split('?')[0]);
    // A vercel.json rewrite (such as /get, job 82) is answered by a function, not a file.
    if ((vercel.rewrites ?? []).some((rule) => rule.source === path)) return null;
    const rel = path === '/' ? 'index.html' : path.endsWith('/') ? null : [path.slice(1), `${path.slice(1)}.html`].find((f) => isFile(join(dist, f)));
    return { rel: rel ?? null, fragment, page: byFile.get(rel) };
  };
  // Why an internal link doesn't work, or null when it does.
  const brokenLink = (href, fromRoute) => {
    const target = resolve(href, fromRoute);
    if (!target) return null;
    if (!target.rel) return `broken link ${href}: no such file in dist`;
    if (target.fragment === undefined) return null;
    if (!target.page) return `link ${href} has a #fragment, but its target is no HTML page`;
    return target.page.doc.querySelector(`[id="${target.fragment}"]`) ? null : `link ${href}: ${target.rel} has no id "${target.fragment}"`;
  };
  // The source of a vercel.json header rule that sends X-Robots-Tag noindex for this route.
  const headerNoindex = (route) =>
    (vercel.headers ?? []).find((rule) => matchesSource(rule.source, route) && rule.headers.some((h) => h.key.toLowerCase() === 'x-robots-tag' && /\bnoindex\b/i.test(h.value)))?.source ?? null;
  return {
    dist,
    siteUrl,
    vercel,
    stage,
    publicApi,
    files,
    pages,
    content: pages.filter((p) => !p.special),
    public: pages.filter((p) => !p.special && !p.noindex),
    read,
    resolve,
    brokenLink,
    headerNoindex,
  };
}

const MD_LINK = /!?\[(?:[^\]\\]|\\.)*\]\(\s*<?([^\s)>]+)>?(?:\s+"[^"]*")?\s*\)/g;
const BARE_URL = /\b(?:https?:\/\/|mailto:)[^\s<>()\]"'`]+/g;
// Link targets of a Markdown text: link and image targets, then bare URLs outside them.
export function markdownUrls(text) {
  const linked = [...text.matchAll(MD_LINK)].map((m) => m[1]);
  const bare = [...text.replace(MD_LINK, ' ').matchAll(BARE_URL)].map((m) => m[0].replace(/[.,;:!?]+$/, ''));
  return [...linked, ...bare];
}

// llms.txt per https://llmstxt.org: one H1, an optional blockquote, plain blocks, then H2
// sections of link items only.
export function parseLlms(text) {
  const problems = [];
  const items = [];
  let state = 'start';
  let section = null;
  const head = [];
  text.split('\n').forEach((line, i) => {
    const where = `line ${i + 1}`;
    if (line.trim() === '') return;
    const heading = /^(#{1,6})\s/.exec(line);
    if (state === 'start') {
      if (!/^# \S/.test(line)) problems.push(`${where}: must start with one H1 "# Name"`);
      state = 'quote';
    } else if (heading) {
      if (heading[1] !== '##') problems.push(`${where}: only one H1 and then H2 sections are allowed, got "${line}"`);
      state = 'section';
      section = line.slice(heading[0].length).trim();
    } else if (state === 'section') {
      const item = /^- \[([^\]]+)\]\((\S+)\)(?:: (.+))?$/.exec(line);
      if (item) items.push({ section, name: item[1], url: item[2], notes: item[3] });
      else problems.push(`${where}: a section holds only "- [name](url)" or "- [name](url): notes" items, got "${line}"`);
    } else {
      head.push(line);
      state = 'body';
    }
  });
  return { h1: text.split('\n')[0], head: head.join('\n'), items, problems };
}

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// RFC 9309 2.2.2: `*` matches any run, a final `$` ends the path; the longest matching rule wins,
// Allow on a tie, and no match allows.
function allowedByRobots(rules, path) {
  const matches = (pattern) => new RegExp(`^${pattern.split('*').map(escapeRegex).join('.*')}`.replace(/\\\$$/, '$')).test(path);
  const best = rules
    .filter((r) => r.path !== '' && matches(r.path))
    .sort((a, b) => b.path.length - a.path.length || Number(b.allow) - Number(a.allow))[0];
  return !best || best.allow;
}

export function robotsGroups(text) {
  const groups = [];
  let current = null;
  let agentLine = false;
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*/, '').trim();
    const record = /^([A-Za-z-]+)\s*:\s*(.*)$/.exec(line);
    if (!record) continue;
    const key = record[1].toLowerCase();
    if (key === 'user-agent') {
      if (!agentLine) groups.push((current = { agents: [], rules: [] }));
      current.agents.push(record[2]);
      agentLine = true;
    } else if (key === 'allow' || key === 'disallow') {
      current?.rules.push({ allow: key === 'allow', path: record[2] });
      agentLine = false;
    }
  }
  return groups;
}

const guideIndexes = (site) => site.public.filter((p) => p.doc.querySelector('main ul.guide-list'));
const guidesOf = (site, index) => site.public.filter((p) => p.route.startsWith(`${index.route}/`));
const ldBlocks = (page) => page.doc.querySelectorAll('script[type="application/ld+json"]').map((s) => s.innerHTML);
const at = (file, message) => ({ file, message });

export const CHECKS = [
  {
    id: 'md-twin',
    run: (site) =>
      site.public.flatMap((page) => {
        const rel = twinPath(page.route).slice(1);
        const text = site.read(rel);
        const h1 = page.doc.querySelector('h1')?.text.trim();
        const link = page.doc.querySelector('link[rel="alternate"][type="text/markdown"]')?.getAttribute('href');
        return [
          ...(text?.trim() ? [] : [at(rel, `missing or empty: every public page has its Markdown twin at ${twinPath(page.route)}`)]),
          ...(text?.trim() && text.split('\n')[0] !== `# ${h1}` ? [at(rel, `first line must be "# ${h1}" (the page's h1), got "${text.split('\n')[0]}"`)] : []),
          ...(link === twinPath(page.route) ? [] : [at(page.file, `head needs <link rel="alternate" type="text/markdown" href="${twinPath(page.route)}">, got ${link ?? 'none'}`)]),
        ];
      }),
  },
  {
    id: 'llms-txt',
    run: (site) => {
      const text = site.read('llms.txt');
      if (text === null) return [at('llms.txt', 'missing')];
      const llms = parseLlms(text);
      const listed = new Set(llms.items.map((i) => i.url));
      return [
        ...llms.problems.map((m) => at('llms.txt', m)),
        ...[...llms.items.map((i) => i.url), ...markdownUrls(llms.head)].flatMap((url) => {
          if (!url.startsWith('https://')) return [at('llms.txt', `link ${url} must be absolute https`)];
          if (new URL(url).origin === MCP_URL) return [];
          if (!url.startsWith(`${site.siteUrl}/`) && url !== site.siteUrl) return [at('llms.txt', `link ${url}: the only external URL allowed is ${MCP_URL}`)];
          const broken = site.brokenLink(url, '/');
          return broken ? [at('llms.txt', broken)] : [];
        }),
        ...site.public
          .filter((p) => !listed.has(site.siteUrl + twinPath(p.route)))
          .map((p) => at('llms.txt', `does not list ${site.siteUrl}${twinPath(p.route)}, the twin of public page ${p.file}`)),
      ];
    },
  },
  {
    id: 'llms-full',
    run: (site) => {
      const full = site.read('llms-full.txt');
      if (full === null) return [at('llms-full.txt', 'missing')];
      const llms = site.read('llms.txt') ?? '';
      const h1 = llms.split('\n')[0];
      return [
        ...(full.split('\n')[0] === h1 ? [] : [at('llms-full.txt', `must start with llms.txt's H1 "${h1}"`)]),
        ...parseLlms(llms)
          .items.map((i) => ({ url: i.url, target: site.resolve(i.url, '/') }))
          .filter(({ target }) => target?.rel?.endsWith('.md'))
          .filter(({ target }) => !full.includes(site.read(target.rel).trim()))
          .map(({ url }) => at('llms-full.txt', `does not contain the twin ${url}`)),
      ];
    },
  },
  {
    id: 'robots',
    run: (site) => {
      const text = site.read('robots.txt');
      if (text === null) return [at('robots.txt', 'missing')];
      const sitemap = `${site.siteUrl}/sitemap.xml`;
      const noindex = site.pages.filter((p) => p.file !== '404.html' && (p.noindex || site.headerNoindex(p.route)));
      return [
        ...(new RegExp(`^Sitemap:\\s*${sitemap.replace(/[.]/g, '\\.')}\\s*$`, 'mi').test(text) ? [] : [at('robots.txt', `needs the line "Sitemap: ${sitemap}"`)]),
        // A crawler must be allowed to fetch a page to see its noindex.
        ...robotsGroups(text).flatMap((group) =>
          noindex
            .filter((p) => !allowedByRobots(group.rules, p.route))
            .map((p) => at('robots.txt', `user-agent ${group.agents.join(', ')} disallows ${p.route}, which is noindex; a crawler must fetch it to see that`)),
        ),
      ];
    },
  },
  {
    id: 'launch',
    run: (site) => {
      if (site.stage !== 'launch') return [];
      const rules = (site.vercel.headers ?? []).filter((rule) => rule.headers.some((h) => h.key.toLowerCase() === 'x-robots-tag' && /\bnoindex\b/i.test(h.value)));
      return [
        ...rules.map((rule) => at('site/vercel.json', `stage is launch (site/config/stage.ts), so remove the X-Robots-Tag noindex header of the rule "${rule.source}"`)),
        ...site.content
          // The pages behind the waitlist's mail links (job 82) and an unlisted guide (job 415) stay noindex for good.
          .filter((p) => p.noindex && !p.doc.querySelector('.draft-banner') && !p.doc.querySelector('.wl-page') && !p.doc.querySelector('meta[name="snacklist-unlisted"]'))
          .map((p) => at(p.file, 'stage is launch (site/config/stage.ts), but this page has <meta name="robots" content="noindex"> without a draft or unreleased banner')),
      ];
    },
  },
  {
    id: 'hreflang',
    run: (site) =>
      site.content.flatMap((page) => {
        const alts = page.alternates;
        const problems = [];
        if (alts[page.lang] !== page.canonical) problems.push(`alternates must include itself: hreflang="${page.lang}" href="${page.canonical}"`);
        if (!alts['x-default']) problems.push('alternates must include x-default');
        for (const [code, href] of Object.entries(alts)) {
          const target = site.resolve(href, page.route)?.page;
          if (!target) {
            problems.push(`hreflang="${code}" target ${href} is no page in dist`);
          } else if (code === 'x-default') {
            if (target.alternates['x-default'] !== href) problems.push(`x-default ${href} does not name itself as x-default`);
          } else {
            if (target.lang !== code) problems.push(`hreflang="${code}" target ${href} has <html lang="${target.lang}">`);
            if (target.alternates[page.lang] !== page.canonical) problems.push(`${href} does not link back with hreflang="${page.lang}" href="${page.canonical}"`);
            if (target.alternates['x-default'] !== alts['x-default']) problems.push(`${href} has another x-default (${target.alternates['x-default']}) than this page (${alts['x-default']})`);
          }
        }
        return problems.map((m) => at(page.file, m));
      }),
  },
  {
    id: 'sitemap',
    run: (site) => {
      const text = site.read('sitemap.xml');
      if (text === null) return [at('sitemap.xml', 'missing')];
      const unescape = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
      const locs = new Set([...text.matchAll(/<loc>([^<]*)<\/loc>/g)].map((m) => unescape(m[1].trim())));
      const expected = new Set(site.public.map((p) => p.canonical));
      return [
        ...(/<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/.test(text) ? [] : [at('sitemap.xml', 'needs <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')]),
        ...[...expected].filter((u) => !locs.has(u)).map((u) => at('sitemap.xml', `missing public page ${u}`)),
        ...[...locs].filter((u) => !expected.has(u)).map((u) => at('sitemap.xml', `lists ${u}, which is no public page (missing, noindex, or not its canonical URL)`)),
      ];
    },
  },
  {
    id: 'jsonld',
    run: (site) =>
      site.pages.flatMap((page) => {
        const problems = [];
        const faq = faqOf(page.doc).map((q) => q.question);
        const faqPages = [];
        for (const raw of ldBlocks(page)) {
          let data;
          try {
            data = JSON.parse(raw);
          } catch (error) {
            problems.push(`JSON-LD does not parse: ${error.message}`);
            continue;
          }
          const schema = SCHEMAS[data['@type']];
          if (data['@context'] !== 'https://schema.org') problems.push(`JSON-LD @context must be "https://schema.org", got ${JSON.stringify(data['@context'])}`);
          if (!schema) {
            problems.push(`JSON-LD @type ${JSON.stringify(data['@type'])} is not one of ${Object.keys(SCHEMAS).join(', ')}`);
            continue;
          }
          for (const key of schema.required) {
            const value = data[key];
            if (value === undefined || value === null || value === '' || (Array.isArray(value) && value.length === 0)) problems.push(`JSON-LD ${data['@type']} needs "${key}"`);
          }
          if (data['@type'] === 'FAQPage') faqPages.push((data.mainEntity ?? []).map((q) => q?.name));
        }
        if (faq.length > 0 && faqPages.length === 0) problems.push('has a FAQ section but no FAQPage JSON-LD');
        for (const names of faqPages) {
          if (JSON.stringify(names) !== JSON.stringify(faq)) problems.push(`FAQPage questions ${JSON.stringify(names)} differ from the FAQ section's h3s ${JSON.stringify(faq)}`);
        }
        return problems.map((m) => at(page.file, m));
      }),
  },
  {
    id: 'structure',
    run: (site) => [
      ...guideIndexes(site).flatMap((index) => {
        const listed = new Set(index.doc.querySelectorAll('main ul.guide-list a').map((a) => a.getAttribute('href')));
        return guidesOf(site, index)
          .filter((g) => !listed.has(g.route))
          .map((g) => at(index.file, `guide index does not list ${g.route}`));
      }),
      ...guideIndexes(site)
        .flatMap((index) => guidesOf(site, index))
        .flatMap((guide) => {
          const main = guide.doc.querySelector('main');
          const children = main.childNodes.filter((n) => n.tagName);
          const h1 = children.findIndex((n) => n.tagName === 'H1');
          const h2 = children.findIndex((n) => n.tagName === 'H2');
          const intro = children.slice(h1 + 1, h2 === -1 ? undefined : h2).some((n) => n.tagName === 'P' && !n.hasAttribute('hidden') && n.text.trim() !== '');
          const problems = [
            ...(guide.doc.querySelector('meta[name="description"]')?.getAttribute('content')?.trim() ? [] : ['needs <meta name="description">']),
            ...(h1 === -1 ? ['needs an h1 in <main>'] : []),
            ...(/^\d{4}-\d{2}-\d{2}$/.test(main.querySelector('time[datetime]')?.getAttribute('datetime') ?? '') ? [] : ['needs the updated date as <time datetime="YYYY-MM-DD">']),
            ...(h1 !== -1 && intro ? [] : ['needs an intro paragraph between the h1 and the first h2']),
          ];
          return problems.map((m) => at(guide.file, m));
        }),
      ...site.content.flatMap((page) =>
        faqOf(page.doc).flatMap(({ question, answer }) => [
          ...(question.endsWith('?') ? [] : [at(page.file, `FAQ question "${question}" must end with "?"`)]),
          ...(answer ? [] : [at(page.file, `FAQ question "${question}" has no answer`)]),
        ]),
      ),
    ],
  },
  {
    id: 'links',
    run: (site) => {
      const check = (file, href, fromRoute) => {
        if (site.resolve(href, fromRoute)) {
          const broken = site.brokenLink(href, fromRoute);
          return broken ? [at(file, broken)] : [];
        }
        let protocol;
        try {
          protocol = new URL(href).protocol;
        } catch {
          return [at(file, `link ${href} is neither site-absolute (/...) nor an absolute URL`)];
        }
        return ['http:', 'https:', 'mailto:'].includes(protocol) ? [] : [at(file, `link ${href} must be http(s) or mailto`)];
      };
      const markdown = site.files.filter((f) => f.endsWith('.md') || f === 'llms.txt' || f === 'llms-full.txt');
      return [
        ...site.pages.flatMap((page) => page.doc.querySelectorAll('a[href], link[href]').flatMap((el) => check(page.file, el.getAttribute('href'), page.route))),
        ...markdown.flatMap((file) => markdownUrls(site.read(file)).flatMap((url) => check(file, url, '/'))),
      ];
    },
  },
  {
    id: 'openapi',
    skip: (site) => (site.publicApi ? null : API_OFF),
    run: (site) => {
      const text = site.read('openapi.yaml');
      if (text === null) return [at('openapi.yaml', 'missing, but the public-api flag is on')];
      let spec;
      try {
        spec = yaml.safeLoad(text);
      } catch (error) {
        return [at('openapi.yaml', `does not parse: ${error.message}`)];
      }
      const refs = new Set();
      const walk = (node) => {
        if (Array.isArray(node)) node.forEach(walk);
        else if (node && typeof node === 'object') {
          if (typeof node.$ref === 'string' && node.$ref.startsWith('#')) refs.add(node.$ref);
          Object.values(node).forEach(walk);
        }
      };
      walk(spec);
      const resolves = (ref) => {
        let node = spec;
        for (const part of ref.replace(/^#\/?/, '').split('/').filter((p) => p !== '')) {
          const key = decodeURIComponent(part).replace(/~1/g, '/').replace(/~0/g, '~');
          if (!node || typeof node !== 'object' || !(key in node)) return false;
          node = node[key];
        }
        return true;
      };
      return [
        ...(String(spec?.openapi ?? '').startsWith('3.') ? [] : ['"openapi" must be a 3.x version']),
        ...(spec?.info?.title && spec?.info?.version ? [] : ['needs info.title and info.version']),
        ...(spec?.paths && Object.keys(spec.paths).length > 0 ? [] : ['needs at least one path']),
        ...[...refs].filter((ref) => !resolves(ref)).map((ref) => `$ref ${ref} does not resolve`),
      ].map((m) => at('openapi.yaml', m));
    },
  },
];

// Runs every check on dist/: { problems: [{ check, file, message }], skipped: [{ check, reason }] }.
// `previewStage`: the stage came from SITE_STAGE (a preview build), so the launch guard, which
// protects the real launch, has nothing to say.
export function checkAgentSite(opts) {
  const site = loadSite(opts);
  const problems = [];
  const skipped = [];
  for (const { id, skip, run } of CHECKS) {
    if (id === 'launch' && opts.previewStage) continue;
    const reason = skip?.(site);
    if (reason) skipped.push({ check: id, reason });
    else problems.push(...run(site).map((p) => ({ check: id, ...p })));
  }
  return { problems, skipped };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { problems, skipped } = checkAgentSite({
    dist: process.argv[2] ?? join(SITE_DIR, 'dist'),
    siteUrl: JSON.parse(readFileSync(join(SITE_DIR, 'config.json'), 'utf8')).siteUrl,
    vercel: readVercel(),
    stage: readStage(),
    publicApi: readPublicApi(join(SITE_DIR, '..')),
  });
  for (const { check, reason } of skipped) console.log(`skipped ${check}: ${reason}`);
  for (const { check, file, message } of problems) console.error(`${check}: ${file}: ${message}`);
  console.log(`${CHECKS.length - skipped.length} checks, ${problems.length} problems`);
  process.exitCode = problems.length > 0 ? 1 : 0;
}
