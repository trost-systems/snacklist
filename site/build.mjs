import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import MarkdownIt from 'markdown-it';
import container from 'markdown-it-container';
import { parse } from 'node-html-parser';
import { CATEGORIES, RecordError, compareVersions, draftFileNames, isVersion, parseDraft, parseRecord, publicReleases } from './releases.mjs';
import { APP_URL, CopyError, readCopy, renderLanding } from './landing.mjs';

const SITE_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_DIR = join(SITE_DIR, '..');
const PUBLIC_DIR = join(SITE_DIR, 'public');

export const LOCALES = {
  de: {
    name: 'Deutsch',
    landing: '/de',
    guidesBase: '/de/anleitungen',
    ogLocale: 'de_DE',
    footer: {
      imprint: { label: 'Impressum', href: '/impressum' },
      privacy: { label: 'Datenschutz', href: '/datenschutz' },
      support: { label: 'Hilfe', href: '/support' },
      changelog: { label: 'Neuigkeiten', href: '/de/changelog' },
    },
    ui: {
      updated: 'Aktualisiert',
      languageNav: 'Sprache',
      mainNav: 'Hauptnavigation',
      footerNav: 'Rechtliches',
      siteNav: 'Hummlist',
      home: 'Hummlist, zur Startseite',
      skip: 'Zum Inhalt',
      guides: 'Anleitungen',
      draft: 'ENTWURF: Freigabe durch Peter',
      unreleased: (v) => `Ab Version ${v}, noch nicht im Store`,
      since: (v) => `Ab App-Version ${v}`,
      changelog: {
        title: 'Neuigkeiten',
        description: 'Was jede Version von Hummlist neu bringt, verbessert und behebt.',
        version: (v) => `Version ${v}`,
        categories: { new: 'Neu', improved: 'Verbessert', fixed: 'Behoben' },
        neutral: 'Fehlerbehebungen und Verbesserungen.',
        draft: 'Entwurf, noch nicht im Store',
        empty: 'Die erste Version von Hummlist ist bald in den Stores. Hier steht dann, was jede neue Version bringt.',
      },
    },
  },
  en: {
    name: 'English',
    landing: '/en',
    guidesBase: '/en/guides',
    ogLocale: 'en_US',
    footer: {
      imprint: { label: 'Imprint', href: '/en/imprint' },
      privacy: { label: 'Privacy', href: '/en/privacy' },
      support: { label: 'Support', href: '/en/support' },
      changelog: { label: "What's new", href: '/en/changelog' },
    },
    ui: {
      updated: 'Updated',
      languageNav: 'Language',
      mainNav: 'Main',
      footerNav: 'Legal',
      siteNav: 'Hummlist',
      home: 'Hummlist, home',
      skip: 'Skip to content',
      guides: 'Guides',
      draft: "DRAFT: pending Peter's approval",
      unreleased: (v) => `From version ${v}, not in the stores yet`,
      since: (v) => `From app version ${v}`,
      changelog: {
        title: "What's new",
        description: 'What each version of Hummlist adds, improves and fixes.',
        version: (v) => `Version ${v}`,
        categories: { new: 'New', improved: 'Improved', fixed: 'Fixed' },
        neutral: 'Bug fixes and improvements.',
        draft: 'Draft, not in the stores yet',
        empty: "Hummlist's first version is coming to the stores soon. This page will then list what each new version brings.",
      },
    },
  },
};

const SITE_NAME = 'Hummlist';

// A footer link to a page that isn't built yet fails the build, so each waits for its flag.
const FOOTER_LINKS = [
  { key: 'imprint', shown: () => true },
  { key: 'privacy', shown: (config) => config.privacyPublished },
  { key: 'support', shown: (config) => config.supportPublished },
];

// `draft: true` in the frontmatter: built with a banner and noindex in preview and local builds,
// left out of Vercel production builds, so the path answers 404 there as before.
const isProduction = (env) => env.VERCEL_ENV === 'production';

// Content tagged `since` a version above the live one is not in the stores yet: production leaves
// it out, preview and local builds show it with a banner, like a draft.
const released = (since, versions) => since === undefined || compareVersions(since, versions.live) <= 0;
// Before the first public release everything is day-one content, so nothing gets the note.
const noted = (since, versions) =>
  since !== undefined && versions.firstPublic !== null && compareVersions(since, versions.firstPublic) > 0;
const banner = (text) => `<p class="draft-banner" role="note"><strong>${escapeHtml(text)}</strong></p>\n`;

function checkSince(value, file, kind, where) {
  if (kind !== 'guide') fail(file, `${where} "since" is only allowed on guides (legal texts and indexes are not versioned)`);
  if (!isVersion(value)) fail(file, `${where} "since" must be a version MAJOR.MINOR.PATCH, got ${JSON.stringify(value)}`);
  return value;
}

// `## Heading {#id since=1.4.0}`: `#id` gives the heading a stable anchor, e.g. /datenschutz#rechte
// for the stores; `since=` versions the section up to the next heading of the same or a higher level.
// Braces holding anything else stay text.
const HEADING_ATTRS = /\s*\{([^{}]*)\}$/;
function headingAttrs(text) {
  const match = HEADING_ATTRS.exec(text);
  const parts = match?.[1].trim().split(/\s+/).filter(Boolean) ?? [];
  if (parts.length === 0 || !parts.every((p) => /^#[a-z0-9-]+$/.test(p) || p.startsWith('since='))) return null;
  return {
    index: match.index,
    id: parts.find((p) => p.startsWith('#'))?.slice(1),
    since: parts.find((p) => p.startsWith('since='))?.slice('since='.length),
  };
}

const md = new MarkdownIt({ html: false, linkify: false, typographer: false, breaks: true });

// Code blocks and tables scroll sideways on phones; keyboard users reach them with tabindex.
for (const rule of ['fence', 'code_block']) {
  const render = md.renderer.rules[rule];
  md.renderer.rules[rule] = (...args) => render(...args).replace(/^<pre>/, '<pre tabindex="0">');
}
md.renderer.rules.table_open = () => '<table tabindex="0">\n';

// `::: since 1.4.0` ... `:::` versions the blocks between; the `since` core rule decides what renders.
md.use(container, 'since', {
  validate: (params) => /^since\b/.test(params.trim()),
  render: (tokens, idx, options, env, self) => self.renderToken(tokens, idx, options),
});

md.core.ruler.push('since', (state) => {
  const { file, kind, locale, versions, since: pageSince } = state.env;
  const { tokens } = state;
  const lines = state.src.split('\n');
  const ui = LOCALES[locale].ui;
  const html = (content) => Object.assign(new state.Token('html_block', '', 0), { content });
  const note = (since) => (noted(since, versions) ? [html(`<p class="since-note">${escapeHtml(ui.since(since))}</p>\n`)] : []);
  // A section or block repeats no note its guide already shows; unreleased content shows the banner instead.
  const inner = (since) => (pageSince !== undefined && compareVersions(since, pageSince) <= 0 ? [] : note(since));
  const notices = (since) => (released(since, versions) ? inner(since) : [html(banner(ui.unreleased(since)))]);
  const hidden = new Set();
  const unwrapped = new Set();
  const after = new Map();
  const insert = (i, list) => after.set(i, [...(after.get(i) ?? []), ...list]);
  const hide = (from, to) => {
    for (let j = from; j <= to; j++) hidden.add(j);
  };
  let h1Seen = false;
  tokens.forEach((token, i) => {
    if (token.type === 'paragraph_open' && tokens[i + 1].content.startsWith(':::')) {
      fail(file, `"${tokens[i + 1].content.split('\n')[0]}" is not a block this site knows; a versioned block is "::: since 1.4.0" up to a line ":::"`);
    }
    if (token.type === 'heading_open') {
      const last = tokens[i + 1].children.at(-1);
      const attrs = last?.type === 'text' ? headingAttrs(last.content) : null;
      if (attrs) {
        if (attrs.id) token.attrSet('id', attrs.id);
        last.content = last.content.slice(0, attrs.index);
      }
      if (attrs?.since !== undefined) {
        const since = checkSince(attrs.since, file, kind, 'heading attribute');
        if (token.level !== 0) fail(file, `heading attribute "since" only works on headings outside lists, quotes and blocks`);
        const depth = Number(token.tag[1]);
        const next = tokens.findIndex((t, j) => j > i && t.type === 'heading_open' && t.level === 0 && Number(t.tag[1]) <= depth);
        if (!released(since, versions) && versions.production) hide(i, (next === -1 ? tokens.length : next) - 1);
        else insert(i + 2, notices(since));
      }
      if (token.tag === 'h1' && !h1Seen) {
        h1Seen = true;
        if (pageSince !== undefined) insert(i + 2, note(pageSince));
      }
    }
    if (token.type === 'container_since_open') {
      const since = checkSince(token.info.trim().slice('since'.length).trim(), file, kind, 'block');
      // The plugin closes an unclosed block silently at its parent's end.
      if (!/^[\s>]*:{3,}\s*$/.test(lines[token.map[1]] ?? '')) fail(file, `"::: ${token.info.trim()}" is not closed; end it with a line ":::"`);
      const close = tokens.findIndex((t, j) => j > i && t.type === 'container_since_close' && t.level === token.level);
      // The plugin's search for the closing line doesn't skip code fences, so a ":::" line in a
      // fence ends the block there and leaves the fence open up to it.
      const cut = tokens.slice(i, close).find((t) => {
        if (t.type !== 'fence') return false;
        const end = t.map[1] - 1;
        const closer = (lines[end] ?? '').replace(/^[\s>]*/, '');
        return end === t.map[0] || !closer.startsWith(t.markup) || closer.replace(/^[`~]+/, '').trim() !== '';
      });
      if (cut) fail(file, `a code fence inside "::: ${token.info.trim()}" holds a ":::" line, which ends the block; open and close the block with more colons ("::::")`);
      if (released(since, versions)) {
        unwrapped.add(i).add(close);
        insert(i, inner(since));
      } else if (versions.production) hide(i, close);
      else {
        token.attrSet('class', 'since-block');
        insert(i, notices(since));
      }
    }
  });
  const kept = tokens.flatMap((t, j) => (hidden.has(j) ? [] : [...(unwrapped.has(j) ? [] : [t]), ...(after.get(j) ?? [])]));
  // A quote or list whose only content was hidden would render empty.
  const empty = (t, next) => t.nesting === 1 && next?.nesting === -1 && next.type === t.type.replace(/_open$/, '_close');
  for (let k = kept.length - 2; k >= 0; k--) if (empty(kept[k], kept[k + 1])) kept.splice(k, 2);
  state.tokens = kept;
});

function markdownFiles(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter((f) => f.endsWith('.md')).map((f) => join(dir, f));
}

export const KINDS = {
  guide: {
    fields: ['title', 'description', 'slug', 'locale', 'translation_key', 'updated'],
    ogType: 'article',
    files: (contentDir) => {
      const root = join(contentDir, 'guides');
      if (!existsSync(root)) return [];
      return readdirSync(root).flatMap((folder) =>
        markdownFiles(join(root, folder)).map((file) => ({
          file,
          expect: { locale: folder, slug: file.slice(file.lastIndexOf('/') + 1, -3) },
        })),
      );
    },
    route: (fm) => `${LOCALES[fm.locale].guidesBase}/${fm.slug}`,
    group: (fm) => `guide:${fm.translation_key}`,
  },
  page: {
    fields: ['title', 'description', 'locale', 'path', 'translation_key', 'updated'],
    ogType: 'website',
    files: (contentDir) => markdownFiles(join(contentDir, 'legal')).map((file) => ({ file, expect: {} })),
    route: (fm) => fm.path,
    group: (fm) => `page:${fm.translation_key}`,
  },
  index: {
    fields: ['title', 'description', 'locale'],
    ogType: 'website',
    files: (contentDir) =>
      markdownFiles(join(contentDir, 'indexes')).map((file) => ({
        file,
        expect: { locale: file.slice(file.lastIndexOf('/') + 1, -3) },
      })),
    route: (fm) => LOCALES[fm.locale].guidesBase,
    group: () => 'index',
  },
};

class BuildError extends Error {}

function fail(file, reason) {
  throw new BuildError(`${file}: ${reason}`);
}

function normalizeDate(value, file) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0, 10);
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value))) return value;
  fail(file, `frontmatter field "updated" must be a date (YYYY-MM-DD), got ${JSON.stringify(value)}`);
}

function loadPage(kindName, { file, expect }, contentDir, versions) {
  const kind = KINDS[kindName];
  const name = relative(contentDir, file);
  const { data, content } = matter(readFileSync(file, 'utf8'));
  for (const field of kind.fields) {
    const value = data[field];
    if (value === undefined || value === null || value === '') fail(name, `missing required frontmatter field "${field}"`);
  }
  const fm = { ...data };
  if (fm.updated !== undefined) fm.updated = normalizeDate(fm.updated, name);
  for (const field of kind.fields.filter((f) => f !== 'updated')) {
    if (typeof fm[field] !== 'string') fail(name, `frontmatter field "${field}" must be a string`);
  }
  if (!LOCALES[fm.locale]) fail(name, `frontmatter field "locale" must be one of ${Object.keys(LOCALES).join(', ')}, got "${fm.locale}"`);
  for (const [field, expected] of Object.entries(expect)) {
    if (fm[field] !== expected) fail(name, `frontmatter field "${field}" is "${fm[field]}" but the file location requires "${expected}"`);
  }
  if (fm.draft !== undefined && typeof fm.draft !== 'boolean') fail(name, `frontmatter field "draft" must be true or false, got ${JSON.stringify(fm.draft)}`);
  if (fm.since !== undefined) checkSince(fm.since, name, kindName, 'frontmatter field');
  if (kindName === 'page' && !/^\/[a-z0-9/-]*[a-z0-9]$/.test(fm.path)) fail(name, `frontmatter field "path" must look like /some/path, got "${fm.path}"`);
  const ui = LOCALES[fm.locale].ui;
  return {
    kind: kindName,
    file: name,
    route: kind.route(fm),
    group: kind.group(fm),
    ogType: kind.ogType,
    locale: fm.locale,
    title: fm.title,
    description: fm.description,
    updated: fm.updated,
    // Why the page is not published: production leaves out a page with any notice.
    notices: [...(fm.draft === true ? [ui.draft] : []), ...(released(fm.since, versions) ? [] : [ui.unreleased(fm.since)])],
    body: md.render(content, { file: name, kind: kindName, locale: fm.locale, versions, since: fm.since }),
  };
}

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function formatDate(iso, locale) {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(iso));
}

function mainContent(page, guidesByLocale) {
  if (page.kind === 'index') {
    const items = guidesByLocale[page.locale]
      .map((g) => `<li><a href="${g.route}">${escapeHtml(g.title)}</a><p>${escapeHtml(g.description)}</p></li>`)
      .join('\n');
    return `<h1>${escapeHtml(page.title)}</h1>\n${page.body}<ul class="guide-list">\n${items}\n</ul>`;
  }
  if (page.kind === 'landing') return page.body;
  if (page.kind === 'guide') {
    const label = LOCALES[page.locale].ui.updated;
    return `${page.body}<p class="updated">${label}: <time datetime="${page.updated}">${formatDate(page.updated, page.locale)}</time></p>`;
  }
  return page.body;
}

// The header and footer every page shares: the brand back to the landing page, the guides and
// the changelog, the language switch, the web app; in the footer the legal links by their flags.
function siteHeader(page, { switches, copy, current }) {
  const locale = LOCALES[page.locale];
  const link = (href, label) => `<li><a href="${href}"${current === href ? ' aria-current="page"' : ''}>${label}</a></li>`;
  return `<a class="skip" href="#inhalt">${locale.ui.skip}</a>
<header class="site-header">
<div class="wrap">
<a class="brand" href="${locale.landing}" aria-label="${locale.ui.home}"><span class="mark" aria-hidden="true"></span>${SITE_NAME}</a>
<nav class="nav" aria-label="${locale.ui.mainNav}"><ul>${link(locale.guidesBase, locale.ui.guides)}${link(locale.footer.changelog.href, locale.footer.changelog.label)}</ul></nav>
<nav class="lang" aria-label="${locale.ui.languageNav}">${switches}</nav>
<a class="hex hex--small header-cta" href="${APP_URL}"><span class="face" data-copy-id="header.open-app">${escapeHtml(copy.get('header.open-app')[page.locale])}</span></a>
</div>
</header>`;
}

function siteFooter(page, { config, copy }) {
  const locale = LOCALES[page.locale];
  const legal = FOOTER_LINKS.filter((link) => link.shown(config))
    .map(({ key }) => `<li><a href="${locale.footer[key].href}">${locale.footer[key].label}</a></li>`)
    .join('');
  return `<footer class="site-footer">
<div class="wrap">
<a class="brand" href="${locale.landing}" aria-label="${locale.ui.home}"><span class="mark" aria-hidden="true"></span>${SITE_NAME}</a>
<nav class="footer-site" aria-label="${locale.ui.siteNav}"><ul><li><a href="${locale.guidesBase}">${locale.ui.guides}</a></li><li><a href="${locale.footer.changelog.href}">${locale.footer.changelog.label}</a></li></ul></nav>
<nav class="footer-legal" aria-label="${locale.ui.footerNav}"><ul>${legal}</ul></nav>
<p class="tagline" data-copy-id="footer.tagline">${escapeHtml(copy.get('footer.tagline')[page.locale])}</p>
</div>
</footer>`;
}

function renderPage(page, { config, groups, guidesByLocale, copy }) {
  const { siteUrl, defaultLocale } = config;
  const locale = LOCALES[page.locale];
  const versions = groups.get(page.group);
  const url = siteUrl + page.route;
  const xDefault = versions[defaultLocale] ?? page;
  const alternates = Object.values(versions)
    .map((v) => `<link rel="alternate" hreflang="${v.locale}" href="${siteUrl}${v.route}">`)
    .concat(`<link rel="alternate" hreflang="x-default" href="${siteUrl}${xDefault.route}">`)
    .join('\n');
  const switches = Object.keys(LOCALES)
    .filter((code) => code !== page.locale)
    .map((code) => {
      const href = versions[code]?.route ?? LOCALES[code].guidesBase;
      return `<a href="${href}" lang="${code}" hreflang="${code}">${LOCALES[code].name}</a>`;
    })
    .join(' ');
  const landing = page.kind === 'landing';
  const current = page.kind === 'index' ? locale.guidesBase : page.kind === 'changelog' ? locale.footer.changelog.href : null;
  const title = escapeHtml(page.title);
  const description = escapeHtml(page.description);
  const comments = page.notices.map((text) => `<!-- ${text} -->\n`).join('');
  return `<!doctype html>
<html lang="${page.locale}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${page.notices.length > 0 ? `${comments}<meta name="robots" content="noindex">\n` : ''}<title>${landing ? title : `${title} | ${SITE_NAME}`}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${url}">
${alternates}
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:type" content="${page.ogType}">
<meta property="og:url" content="${url}">
<meta property="og:locale" content="${locale.ogLocale}">
<meta property="og:site_name" content="${SITE_NAME}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="${title}">
<meta name="twitter:description" content="${description}">
${HEAD_ASSETS}${landing ? '<link rel="stylesheet" href="/landing.css">\n<script src="/demo.js" defer></script>\n' : ''}</head>
<body${landing ? ' class="landing"' : ''}>
${page.notices.map(banner).join('')}${siteHeader(page, { switches, copy, current })}
<main id="inhalt"${landing ? '' : ' class="wrap prose"'}>
${mainContent(page, guidesByLocale)}
</main>
${siteFooter(page, { config, copy })}
</body>
</html>
`;
}

const HEAD_ASSETS = `<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/fonts/bricolage-grotesque-latin-standard-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/fonts/inter-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/tokens.css">
<link rel="stylesheet" href="/styles.css">
`;

function standalonePage({ lang, title, head = '', body }) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
${head}${HEAD_ASSETS}</head>
<body>
<main id="inhalt" class="wrap prose">
${body}
</main>
</body>
</html>
`;
}

function indexLinks() {
  return Object.entries(LOCALES)
    .map(([code, l]) => `<li><a href="${l.landing}" lang="${code}" hreflang="${code}">${l.name}</a></li>`)
    .join('\n');
}

function rootPage(config) {
  const target = LOCALES[config.defaultLocale].landing;
  return standalonePage({
    lang: config.defaultLocale,
    title: SITE_NAME,
    head: `<meta http-equiv="refresh" content="0; url=${target}">\n`,
    body: `<h1>${SITE_NAME}</h1>\n<ul class="guide-list">\n${indexLinks()}\n</ul>`,
  });
}

function notFoundPage(config) {
  return standalonePage({
    lang: config.defaultLocale,
    title: `Seite nicht gefunden | Page not found | ${SITE_NAME}`,
    body: `<h1>Seite nicht gefunden <span lang="en">/ Page not found</span></h1>
<p>Diese Seite gibt es nicht. <span lang="en">This page does not exist.</span></p>
<ul class="guide-list">\n${indexLinks()}\n</ul>`,
  });
}

const routeFile = (route) => (route === '/' ? 'index.html' : `${route.slice(1)}.html`);

function htmlFiles(dir) {
  return readdirSync(dir, { recursive: true })
    .filter((f) => f.endsWith('.html'))
    .map((f) => join(dir, f));
}

const EXTERNAL = /^(https?:)?\/\//i;

export function checkHtml(file, html, outDir, siteUrl) {
  const name = relative(outDir, file);
  const doc = parse(html);
  const h1s = doc.querySelectorAll('h1').length;
  if (h1s !== 1) fail(name, `expected exactly one <h1>, found ${h1s}`);
  let previous = 0;
  for (const h of doc.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    const level = Number(h.tagName[1]);
    if (level > previous + 1) fail(name, `heading level skipped: <h${level}> "${h.text.trim()}" follows <h${previous}>`);
    previous = level;
  }
  for (const img of doc.querySelectorAll('img')) {
    if (!img.getAttribute('alt')?.trim()) fail(name, `<img src="${img.getAttribute('src')}"> has no alt text`);
  }
  for (const tag of ['iframe', 'object', 'embed']) {
    if (doc.querySelector(tag)) fail(name, `<${tag}> is not allowed`);
  }
  // Only script files from this site (the CSP blocks inline code and other origins anyway).
  for (const script of doc.querySelectorAll('script')) {
    if (!script.getAttribute('src') || script.innerHTML.trim() !== '') fail(name, '<script> is allowed only as a file from this site, without inline code');
  }
  const resources = [
    ...doc.querySelectorAll('link').filter((l) => !['canonical', 'alternate'].includes(l.getAttribute('rel'))).map((l) => l.getAttribute('href')),
    ...doc.querySelectorAll('img, source, video, track, script').flatMap((el) => [
      el.getAttribute('src'),
      el.getAttribute('poster'),
      ...(el.getAttribute('srcset') ?? '').split(',').map((s) => s.trim().split(/\s+/)[0]),
    ]),
  ].filter(Boolean);
  for (const url of resources) {
    if (EXTERNAL.test(url)) fail(name, `external resource ${url} is not allowed`);
    const path = decodeURIComponent(url.split(/[#?]/)[0]);
    if (!path.startsWith('/') || !existsSync(join(outDir, path)) || !statSync(join(outDir, path)).isFile()) fail(name, `missing resource ${url}`);
  }
  const ids = new Set(doc.querySelectorAll('[id]').map((el) => el.getAttribute('id')));
  for (const a of doc.querySelectorAll('a[href^="#"]')) {
    if (!ids.has(a.getAttribute('href').slice(1))) fail(name, `link ${a.getAttribute('href')} has no target on the page`);
  }
  const hrefs = doc.querySelectorAll('a[href], link[href]').map((el) => el.getAttribute('href'));
  for (const href of hrefs) {
    const local = href.startsWith(siteUrl + '/') ? href.slice(siteUrl.length) : href;
    if (!local.startsWith('/') || local.startsWith('//')) continue;
    const path = decodeURIComponent(local.split(/[#?]/)[0]);
    const exists =
      path === '/' ||
      (!path.endsWith('/') && (existsSync(join(outDir, `${path}.html`)) || (existsSync(join(outDir, path)) && statSync(join(outDir, path)).isFile())));
    if (!exists || path.endsWith('.html')) fail(name, `broken internal link ${href}`);
  }
}

export function readConfig(siteDir = SITE_DIR) {
  return JSON.parse(readFileSync(join(siteDir, 'config.json'), 'utf8'));
}

const OUTSIDE_SITE =
  'the site build needs releases/releases.json and app/pubspec.yaml from outside site/ (on Vercel the project setting "Include files outside the root directory in the Build Step" must stay on)';

function readRepoFile(repoDir, rel) {
  const path = join(repoDir, rel);
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    throw new BuildError(`cannot read ${path} (${error.code}): ${OUTSIDE_SITE}`);
  }
}

// The newest version in the stores, from the public release record; before the first public
// release, the version on this commit, which is what TestFlight and Play internal testers get.
export function liveVersion(repoDir = REPO_DIR) {
  const releases = publicReleases(parseRecord(readRepoFile(repoDir, 'releases/releases.json')));
  if (releases.length > 0) return { live: releases.at(-1).version, firstPublic: releases[0].version, source: 'public release record' };
  const version = /^version:\s*([^\s+]*)/m.exec(readRepoFile(repoDir, 'app/pubspec.yaml'))?.[1];
  if (!isVersion(version)) throw new BuildError(`${join(repoDir, 'app/pubspec.yaml')}: needs a line "version: MAJOR.MINOR.PATCH+BUILD", got ${JSON.stringify(version ?? null)}`);
  return { live: version, firstPublic: null, source: 'app/pubspec.yaml, no public release yet' };
}

// The changelog's releases, newest first: every public release of the record and, outside
// production, the drafts in releases/changelog/ for versions the record doesn't have yet.
// Every draft is checked in every build, so a broken one fails before it could go live.
function changelogEntries(repoDir, production) {
  const releases = publicReleases(parseRecord(readRepoFile(repoDir, 'releases/releases.json')));
  const recorded = new Set(releases.map((r) => r.version));
  const dir = join(repoDir, 'releases/changelog');
  // pending.json and the store-text overrides are not drafts and never shown (job 40).
  const drafts = draftFileNames(existsSync(dir) ? readdirSync(dir) : [])
    .map((f) => {
      const source = `releases/changelog/${f}`;
      const draft = parseDraft(readFileSync(join(dir, f), 'utf8'), source);
      if (f !== `${draft.version}.json`) fail(source, `holds version ${draft.version}, so the file must be named ${draft.version}.json`);
      return draft;
    });
  return [
    ...(production ? [] : drafts.filter((d) => !recorded.has(d.version)).map((d) => ({ version: d.version, date: null, changelog: d }))),
    ...releases.map((r) => ({ version: r.version, date: r.date, changelog: r.changelog ?? null })),
  ].sort((a, b) => compareVersions(b.version, a.version));
}

function changelogBody(entries, locale) {
  const ui = LOCALES[locale].ui.changelog;
  const sections = entries.map(({ version, date, changelog }) => {
    const title = changelog?.title[locale] ?? '';
    const categories = CATEGORIES.filter((c) => changelog?.items[c].length > 0).map(
      (c) => `<h3>${escapeHtml(ui.categories[c])}</h3>\n<ul>\n${changelog.items[c].map((item) => `<li>${escapeHtml(item[locale])}</li>`).join('\n')}\n</ul>\n`,
    );
    return [
      `<section id="v${version.replaceAll('.', '-')}">\n<h2>${escapeHtml(ui.version(version))}</h2>\n`,
      date === null ? banner(ui.draft) : `<p class="release-date"><time datetime="${date}">${formatDate(date, locale)}</time></p>\n`,
      title.trim() === '' ? '' : `<p class="release-title">${escapeHtml(title)}</p>\n`,
      ...(categories.length > 0 ? categories : [`<p>${escapeHtml(ui.neutral)}</p>\n`]),
      '</section>\n',
    ].join('');
  });
  return `<h1>${escapeHtml(ui.title)}</h1>\n${sections.length > 0 ? sections.join('') : `<p>${escapeHtml(ui.empty)}</p>\n`}`;
}

// The landing page per locale. Every copy id in copy.yml must appear on it, so the file holds no
// strings nobody sees.
function landingPages(contentDir, publicDir, config) {
  const copy = readCopy(contentDir);
  const used = new Set(['meta.title', 'meta.description', 'header.open-app', 'footer.tagline']);
  const pages = Object.keys(LOCALES).map((locale) => {
    const landing = renderLanding({ locale, copy, config, publicDir });
    for (const id of landing.used) used.add(id);
    return {
      kind: 'landing',
      file: `content/landing/copy.yml (${locale})`,
      route: LOCALES[locale].landing,
      group: 'landing',
      ogType: 'website',
      locale,
      title: copy.get('meta.title')[locale],
      description: copy.get('meta.description')[locale],
      notices: [],
      body: landing.html,
    };
  });
  const unused = [...copy.keys()].filter((id) => !used.has(id));
  if (unused.length > 0) fail('content/landing/copy.yml', `copy ids not used on the landing page: ${unused.join(', ')}`);
  return { pages, copy };
}

function changelogPages(repoDir, production) {
  const entries = changelogEntries(repoDir, production);
  return Object.keys(LOCALES).map((locale) => ({
    kind: 'changelog',
    file: `(changelog ${locale})`,
    route: LOCALES[locale].footer.changelog.href,
    group: 'changelog',
    ogType: 'website',
    locale,
    title: LOCALES[locale].ui.changelog.title,
    description: LOCALES[locale].ui.changelog.description,
    notices: [],
    body: changelogBody(entries, locale),
  }));
}

export function build({
  contentDir = join(SITE_DIR, 'content'),
  outDir = join(SITE_DIR, 'dist'),
  publicDir = PUBLIC_DIR,
  repoDir = REPO_DIR,
  env = {},
  config = readConfig(),
} = {}) {
  const live = liveVersion(repoDir);
  const versions = { live: live.live, firstPublic: live.firstPublic, production: isProduction(env) };
  const pages = Object.keys(KINDS)
    .flatMap((kind) => KINDS[kind].files(contentDir).map((entry) => loadPage(kind, entry, contentDir, versions)))
    .filter((page) => !(versions.production && page.notices.length > 0))
    .concat(changelogPages(repoDir, versions.production));
  const landing = landingPages(contentDir, publicDir, config);
  pages.push(...landing.pages);

  const byRoute = new Map([['/', { file: '(root page)' }], ['/404', { file: '(404 page)' }]]);
  for (const page of pages) {
    const other = byRoute.get(page.route);
    if (other) fail(page.file, `route ${page.route} is also produced by ${other.file}`);
    byRoute.set(page.route, page);
  }

  const groups = new Map();
  for (const page of pages) {
    const versions = groups.get(page.group) ?? {};
    if (versions[page.locale]) fail(page.file, `translation_key also used by ${versions[page.locale].file} for locale ${page.locale}`);
    groups.set(page.group, { ...versions, [page.locale]: page });
  }

  const guidesByLocale = Object.fromEntries(
    Object.keys(LOCALES).map((code) => [
      code,
      pages.filter((p) => p.kind === 'guide' && p.locale === code).sort((a, b) => a.title.localeCompare(b.title, code)),
    ]),
  );

  const rendered = pages.map((page) => ({ page, html: renderPage(page, { config, groups, guidesByLocale, copy: landing.copy }) }));

  const warnings = [];
  const placeholders = rendered.flatMap(({ page, html }) =>
    [...new Set(html.match(/\[PETER:[^\]]*\]?/g) ?? [])].map((p) => `${page.file}: ${p}`),
  );
  if (placeholders.length > 0) {
    const list = placeholders.join('\n  ');
    if (isProduction(env)) throw new BuildError(`placeholders left in published pages:\n  ${list}`);
    warnings.push(`placeholders left in published pages (production builds fail on these):\n  ${list}`);
  }

  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  cpSync(publicDir, outDir, { recursive: true });
  const write = (route, html) => {
    const file = join(outDir, routeFile(route));
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, html);
  };
  for (const { page, html } of rendered) write(page.route, html);
  write('/', rootPage(config));
  write('/404', notFoundPage(config));

  for (const file of htmlFiles(outDir)) checkHtml(file, readFileSync(file, 'utf8'), outDir, config.siteUrl);

  return { routes: ['/', ...pages.map((p) => p.route)], warnings, live };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { routes, warnings, live } = build({ env: { VERCEL_ENV: process.env.VERCEL_ENV } });
    for (const w of warnings) console.warn(`warning: ${w}`);
    console.log(`live version: ${live.live} (from ${live.source})`);
    console.log(`built ${routes.length} pages into dist/`);
  } catch (error) {
    if (!(error instanceof BuildError || error instanceof RecordError || error instanceof CopyError)) throw error;
    console.error(`build failed: ${error.message}`);
    process.exit(1);
  }
}
