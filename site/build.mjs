import process from 'node:process';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import MarkdownIt from 'markdown-it';
import container from 'markdown-it-container';
import { parse } from 'node-html-parser';
import { CATEGORIES, RecordError, compareVersions, draftFileNames, isVersion, parseDraft, parseGates, parseRecord, publicReleases } from './releases.mjs';
import { CopyError, STAGES, STAGE_CTA, copyReader, readCopy, renderLanding } from './landing.mjs';
import { HISTORY_ROUTES, HistoryCopyError, historyBody, t as historyText } from './history.mjs';
import { ACTION_PAGES, actionPage, readConsent } from './waitlist.mjs';
import { insertReportForm, reportForm, reportFormProblem } from './report.mjs';
import { AgentError, MARKS, agentHead, checkAgentSite, readPublicApi, readStage, readVercel, stageOverride, writeAgentFiles } from './agent.mjs';
import { ALEXA_SKILL_URLS, WEB_APP_URL } from './config/stores.mjs';
import { writeGuideData } from './guide-data.mjs';

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
      terms: { label: 'Nutzungsbedingungen', href: '/nutzungsbedingungen' },
      report: { label: 'Inhalte melden', href: '/inhalte-melden' },
      support: { label: 'Hilfe', href: '/support' },
      changelog: { label: 'Neuigkeiten', href: '/de/changelog' },
      history: { label: historyText('history.footer', 'de'), href: HISTORY_ROUTES.de },
    },
    ui: {
      updated: 'Aktualisiert',
      languageNav: 'Sprache',
      mainNav: 'Hauptnavigation',
      footerNav: 'Rechtliches',
      siteNav: 'Snacklist',
      home: 'Snacklist, zur Startseite',
      skip: 'Zum Inhalt',
      guides: 'Anleitungen',
      openInApp: 'In der App öffnen',
      draft: 'ENTWURF: Freigabe durch Peter',
      unreleased: (v) => `Ab Version ${v}, noch nicht im Store`,
      since: (v) => `Ab App-Version ${v}`,
      once: (key) => `Erst wenn ${key} freigegeben ist, noch nicht live`,
      until: (key) => `Nur bis ${key} freigegeben ist`,
      changelog: {
        title: 'Neuigkeiten',
        description: 'Was jede Version von Snacklist neu bringt, verbessert und behebt.',
        version: (v) => `Version ${v}`,
        categories: { new: 'Neu', improved: 'Verbessert', fixed: 'Behoben' },
        neutral: 'Fehlerbehebungen und Verbesserungen.',
        draft: 'Entwurf, noch nicht im Store',
        empty: 'Die erste Version von Snacklist ist bald in den Stores. Hier steht dann, was jede neue Version bringt.',
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
      terms: { label: 'Terms', href: '/en/terms' },
      report: { label: 'Report content', href: '/en/report' },
      support: { label: 'Support', href: '/en/support' },
      changelog: { label: "What's new", href: '/en/changelog' },
      history: { label: historyText('history.footer', 'en'), href: HISTORY_ROUTES.en },
    },
    ui: {
      updated: 'Updated',
      languageNav: 'Language',
      mainNav: 'Main',
      footerNav: 'Legal',
      siteNav: 'Snacklist',
      home: 'Snacklist, home',
      skip: 'Skip to content',
      guides: 'Guides',
      openInApp: 'Open in the app',
      draft: "DRAFT: pending Peter's approval",
      unreleased: (v) => `From version ${v}, not in the stores yet`,
      since: (v) => `From app version ${v}`,
      once: (key) => `Only once ${key} is released, not live yet`,
      until: (key) => `Only until ${key} is released`,
      changelog: {
        title: "What's new",
        description: 'What each version of Snacklist adds, improves and fixes.',
        version: (v) => `Version ${v}`,
        categories: { new: 'New', improved: 'Improved', fixed: 'Fixed' },
        neutral: 'Bug fixes and improvements.',
        draft: 'Draft, not in the stores yet',
        empty: "Snacklist's first version is coming to the stores soon. This page will then list what each new version brings.",
      },
    },
  },
};

const SITE_NAME = 'Snacklist';

// A footer link to a page that isn't built yet fails the build, so each waits for its flag.
const FOOTER_LINKS = [
  { key: 'imprint', shown: () => true },
  { key: 'privacy', shown: (config) => config.privacyPublished },
  { key: 'terms', shown: (config) => config.termsPublished },
  // The DSA notice route (Art. 16 DSA, job 275) must always be reachable.
  { key: 'report', shown: () => true },
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

// `once` content waits for a hold in releases/flags.json to be released, `until` content goes when
// it is: what users see follows the release decision, not the app version. Production renders only
// the side that is current; preview and local builds show the other side too, with a banner.
// `launch-stage` is no hold but the site's stage (site/config/stage.ts, SITE_STAGE in previews): a
// page says what is true in the stage it is built for, so every build shows only that side (job 402).
const STAGE_GATE = 'launch-stage';
function checkGate(mode, key, file, holds, where) {
  if (!Object.hasOwn(holds, key)) fail(file, `${where} "${mode}" names the hold "${key}", but releases/flags.json has only ${Object.keys(holds).filter((k) => k !== STAGE_GATE).join(', ')} (and the stage gate ${STAGE_GATE})`);
  return { mode, key, shown: mode === 'once' ? holds[key] : !holds[key], strict: key === STAGE_GATE };
}

function checkSince(value, file, kind, where) {
  if (kind !== 'guide') fail(file, `${where} "since" is only allowed on guides (legal texts and indexes are not versioned)`);
  if (!isVersion(value)) fail(file, `${where} "since" must be a version MAJOR.MINOR.PATCH, got ${JSON.stringify(value)}`);
  return value;
}

// `## Heading {#id since=1.4.0}`: `#id` gives the heading a stable anchor, e.g. /datenschutz#rechte
// for the stores; `since=` versions the section up to the next heading of the same or a higher level,
// `once=<hold>` or `until=<hold>` gates it on a hold. Braces holding anything else stay text.
const HEADING_ATTRS = /\s*\{([^{}]*)\}$/;
function headingAttrs(text) {
  const match = HEADING_ATTRS.exec(text);
  const parts = match?.[1].trim().split(/\s+/).filter(Boolean) ?? [];
  if (parts.length === 0 || !parts.every((p) => /^#[a-z0-9-]+$/.test(p) || /^(since|once|until)=/.test(p))) return null;
  const gate = parts.find((p) => /^(once|until)=/.test(p));
  return {
    index: match.index,
    id: parts.find((p) => p.startsWith('#'))?.slice(1),
    since: parts.find((p) => p.startsWith('since='))?.slice('since='.length),
    gate: gate && { mode: gate.slice(0, gate.indexOf('=')), key: gate.slice(gate.indexOf('=') + 1) },
  };
}

const md = new MarkdownIt({ html: false, linkify: false, typographer: false, breaks: true });

// Code blocks and tables scroll sideways on phones; keyboard users reach them with tabindex.
for (const rule of ['fence', 'code_block']) {
  const render = md.renderer.rules[rule];
  md.renderer.rules[rule] = (...args) => render(...args).replace(/^<pre>/, '<pre tabindex="0">');
}
md.renderer.rules.table_open = () => '<table tabindex="0">\n';

// `::: since 1.4.0`, `::: once <hold>` or `::: until <hold>` ... `:::` versions or gates the blocks
// between; the `since` core rule decides what renders.
const BLOCKS = ['since', 'once', 'until'];
for (const name of BLOCKS) {
  md.use(container, name, {
    validate: (params) => new RegExp(`^${name}\\b`).test(params.trim()),
    render: (tokens, idx, options, _env, self) => self.renderToken(tokens, idx, options),
  });
}

md.core.ruler.push('since', (state) => {
  const { file, kind, locale, versions, since: pageSince } = state.env;
  const { tokens } = state;
  const lines = state.src.split('\n');
  const ui = LOCALES[locale].ui;
  // `meta.note` marks the one notice production shows, for the guide JSON.
  const html = (content, meta = null) => Object.assign(new state.Token('html_block', '', 0), { content, meta });
  const note = (since) => (noted(since, versions) ? [html(`<p class="since-note">${escapeHtml(ui.since(since))}</p>\n`, { note: ui.since(since) })] : []);
  // A section or block repeats no note its guide already shows; unreleased content shows the banner instead.
  const inner = (since) => (pageSince !== undefined && compareVersions(since, pageSince) <= 0 ? [] : note(since));
  const notices = (since) => (released(since, versions) ? inner(since) : [html(banner(ui.unreleased(since)))]);
  const gateBanner = (gate) => (gate && !gate.shown ? [html(banner(ui[gate.mode](gate.key)))] : []);
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
      fail(file, `"${tokens[i + 1].content.split('\n')[0]}" is not a block this site knows; a versioned block is "::: since 1.4.0" up to a line ":::", a gated one "::: once <hold>" or "::: until <hold>"`);
    }
    if (token.type === 'heading_open') {
      const last = tokens[i + 1].children.at(-1);
      const attrs = last?.type === 'text' ? headingAttrs(last.content) : null;
      if (attrs) {
        if (attrs.id) token.attrSet('id', attrs.id);
        last.content = last.content.slice(0, attrs.index);
      }
      if (attrs?.since !== undefined || attrs?.gate) {
        const since = attrs.since === undefined ? undefined : checkSince(attrs.since, file, kind, 'heading attribute');
        const gate = attrs.gate && checkGate(attrs.gate.mode, attrs.gate.key, file, versions.holds, 'heading attribute');
        if (token.level !== 0) fail(file, `heading attribute "${since === undefined ? gate.mode : 'since'}" only works on headings outside lists, quotes and blocks`);
        const depth = Number(token.tag[1]);
        const next = tokens.findIndex((t, j) => j > i && t.type === 'heading_open' && t.level === 0 && Number(t.tag[1]) <= depth);
        if ((!released(since, versions) || gate?.shown === false) && (versions.production || gate?.strict)) hide(i, (next === -1 ? tokens.length : next) - 1);
        else insert(i + 2, [...(since === undefined ? [] : notices(since)), ...gateBanner(gate)]);
      }
      if (token.tag === 'h1' && !h1Seen) {
        h1Seen = true;
        if (pageSince !== undefined) insert(i + 2, note(pageSince));
      }
    }
    const block = BLOCKS.find((name) => token.type === `container_${name}_open`);
    if (block) {
      const param = token.info.trim().slice(block.length).trim();
      const since = block === 'since' ? checkSince(param, file, kind, 'block') : undefined;
      const gate = block === 'since' ? undefined : checkGate(block, param, file, versions.holds, 'block');
      // The plugin closes an unclosed block silently at its parent's end.
      if (!/^[\s>]*:{3,}\s*$/.test(lines[token.map[1]] ?? '')) fail(file, `"::: ${token.info.trim()}" is not closed; end it with a line ":::"`);
      const close = tokens.findIndex((t, j) => j > i && t.type === `container_${block}_close` && t.level === token.level);
      // The plugin's search for the closing line doesn't skip code fences, so a ":::" line in a
      // fence ends the block there and leaves the fence open up to it.
      const cut = tokens.slice(i, close).find((t) => {
        if (t.type !== 'fence') return false;
        const end = t.map[1] - 1;
        const closer = (lines[end] ?? '').replace(/^[\s>]*/, '');
        return end === t.map[0] || !closer.startsWith(t.markup) || closer.replace(/^[`~]+/, '').trim() !== '';
      });
      if (cut) fail(file, `a code fence inside "::: ${token.info.trim()}" holds a ":::" line, which ends the block; open and close the block with more colons ("::::")`);
      if (gate ? gate.shown : released(since, versions)) {
        unwrapped.add(i).add(close);
        insert(i, gate ? [] : inner(since));
      } else if (versions.production || gate?.strict) hide(i, close);
      else {
        token.attrSet('class', 'since-block');
        insert(i, gate ? gateBanner(gate) : notices(since));
      }
    }
  });
  const kept = tokens.flatMap((t, j) => (hidden.has(j) ? [] : [...(unwrapped.has(j) ? [] : [t]), ...(after.get(j) ?? [])]));
  // A quote or list whose only content was hidden would render empty.
  const empty = (t, next) => t.nesting === 1 && next?.nesting === -1 && next.type === t.type.replace(/_open$/, '_close');
  for (let k = kept.length - 2; k >= 0; k--) if (empty(kept[k], kept[k + 1])) kept.splice(k, 2);
  state.tokens = kept;
});

// A Markdown link to `alexa-skill:<locale>` goes to that locale's skill page (config/stores.mjs)
// while config.json's alexaPublished is on; off, only its text stays.
md.core.ruler.push('skill-links', (state) => {
  for (const token of state.tokens) {
    if (token.type !== 'inline') continue;
    let dropClose = false;
    token.children = token.children.filter((child) => {
      if (child.type === 'link_close' && dropClose) {
        dropClose = false;
        return false;
      }
      const href = child.type === 'link_open' ? child.attrGet('href') : null;
      if (!href?.startsWith('alexa-skill:')) return true;
      const locale = href.slice('alexa-skill:'.length);
      const url = ALEXA_SKILL_URLS[locale];
      if (!url) fail(state.env.file, `link alexa-skill:${locale}: config/stores.mjs has skill URLs for ${Object.keys(ALEXA_SKILL_URLS).join(', ')}`);
      child.attrSet('href', url);
      dropClose = state.env.skills !== true;
      return !dropClose;
    });
  }
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
  // Comparison pages (ST5): German only, at /<locale>/<slug>, e.g. /de/einkaufsliste-vergleich-bring.
  // The title is the page's whole <title>, without the "| Snacklist" suffix.
  comparison: {
    fields: ['title', 'description', 'slug', 'locale', 'updated'],
    ogType: 'article',
    files: (contentDir) => {
      const root = join(contentDir, 'comparisons');
      if (!existsSync(root)) return [];
      return readdirSync(root).flatMap((folder) =>
        markdownFiles(join(root, folder)).map((file) => ({
          file,
          expect: { locale: folder, slug: file.slice(file.lastIndexOf('/') + 1, -3) },
        })),
      );
    },
    route: (fm) => `${LOCALES[fm.locale].landing}/${fm.slug}`,
    group: (fm) => `comparison:${fm.slug}`,
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

function loadPage(kindName, { file, expect }, contentDir, versions, skills) {
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
  // The apps open a guide by its slug (app/lib/guides/model.dart, GuideRef); any other would show the index.
  if (kindName === 'guide' && !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(fm.slug)) fail(name, `frontmatter field "slug" must be lowercase words joined by hyphens (the apps open guides by it), got "${fm.slug}"`);
  if (kindName === 'guide' && fm.slug === 'index') fail(name, 'frontmatter field "slug" must not be "index": data/guides/<locale>/index.json is the index');
  if (fm.draft !== undefined && typeof fm.draft !== 'boolean') fail(name, `frontmatter field "draft" must be true or false, got ${JSON.stringify(fm.draft)}`);
  if (fm.unlisted !== undefined && (typeof fm.unlisted !== 'boolean' || kindName !== 'guide')) fail(name, 'frontmatter field "unlisted" must be true or false and is only allowed on guides');
  if (fm.since !== undefined) checkSince(fm.since, name, kindName, 'frontmatter field');
  if (kindName === 'page' && !/^\/[a-z0-9/-]*[a-z0-9]$/.test(fm.path)) fail(name, `frontmatter field "path" must look like /some/path, got "${fm.path}"`);
  if (fm.form !== undefined) {
    if (kindName !== 'page') fail(name, 'frontmatter field "form" (the report form) is only allowed on legal pages');
    const problem = reportFormProblem(fm.form);
    if (problem) fail(name, `frontmatter field ${problem}`);
  }
  const ui = LOCALES[fm.locale].ui;
  return {
    kind: kindName,
    file: name,
    route: kind.route(fm),
    group: kind.group(fm),
    ogType: kind.ogType,
    locale: fm.locale,
    slug: fm.slug,
    title: fm.title,
    description: fm.description,
    updated: fm.updated,
    // Why the page is not published: production leaves out a page with any notice.
    notices: [...(fm.draft === true ? [ui.draft] : []), ...(released(fm.since, versions) ? [] : [ui.unreleased(fm.since)])],
    unlisted: fm.unlisted === true,
    report: fm.form !== undefined,
    ...pageBody(content, fm, { file: name, kind: kindName, locale: fm.locale, versions, since: fm.since, skills }),
  };
}

// The tokens are what the HTML shows, gating done; a guide's JSON for the app is built from them.
// A legal page with `form:` in its front matter gets the report form (job 275, report.mjs).
function pageBody(content, fm, env) {
  const tokens = md.parse(content, env);
  const body = md.renderer.render(tokens, md.options, env);
  if (fm.form === undefined) return { tokens, body };
  return { tokens, body: insertReportForm(body, reportForm(fm.form, { locale: fm.locale, inline: (text) => md.renderInline(text, env) })) };
}

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function formatDate(iso, locale) {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(iso));
}

// The app claims the guide paths (public/.well-known); open-in-app.js shows this on phones.
const openInApp = (locale) => `<p class="open-in-app" hidden><a data-open-in-app>${LOCALES[locale].ui.openInApp}</a></p>\n`;

function mainContent(page, guidesByLocale) {
  if (page.kind === 'index') {
    const items = guidesByLocale[page.locale]
      .map((g) => `<li><a href="${g.route}">${escapeHtml(g.title)}</a><p>${escapeHtml(g.description)}</p></li>`)
      .join('\n');
    return `<h1>${escapeHtml(page.title)}</h1>\n${openInApp(page.locale)}${page.body}<ul class="guide-list">\n${items}\n</ul>`;
  }
  if (page.kind === 'landing') return page.body;
  if (page.kind === 'guide') {
    const label = LOCALES[page.locale].ui.updated;
    const body = page.body.replace(/(<\/h1>\n(?:<p class="since-note">.*<\/p>\n)?)/, `$1${openInApp(page.locale)}`);
    return `${body}<p class="updated">${label}: <time datetime="${page.updated}">${formatDate(page.updated, page.locale)}</time></p>`;
  }
  return page.body;
}

// The header and footer every page shares: the brand back to the landing page, the guides and
// the changelog, the language switch, the stage's call to action (site/config/stage.ts); in the
// footer also the release timeline and the legal links by their flags.
function siteHeader(page, { switches, copy, current, stage }) {
  const locale = LOCALES[page.locale];
  const cta = STAGE_CTA[stage];
  const href = `${page.kind === 'landing' ? '' : locale.landing}#${cta.anchor[page.locale]}`;
  const link = (href, label) => `<li><a href="${href}"${current === href ? ' aria-current="page"' : ''}>${label}</a></li>`;
  const webApp = stage === 'launch' ? `<li><a href="${WEB_APP_URL}" data-copy-id="nav.web-app">${escapeHtml(copy.get('nav.web-app')[page.locale])}</a></li>` : '';
  return `<a class="skip" href="#inhalt">${locale.ui.skip}</a>
<header class="site-header">
<div class="wrap">
<a class="brand" href="${locale.landing}" aria-label="${locale.ui.home}"><span class="mark" aria-hidden="true"></span>${SITE_NAME}</a>
<nav class="nav" aria-label="${locale.ui.mainNav}"><ul>${link(locale.guidesBase, locale.ui.guides)}${link(locale.footer.changelog.href, locale.footer.changelog.label)}${webApp}</ul></nav>
<nav class="lang" aria-label="${locale.ui.languageNav}">${switches}</nav>
<a class="hex hex--small header-cta" href="${href}"><span class="face" data-copy-id="${cta.id}">${escapeHtml(copy.get(cta.id)[page.locale])}</span></a>
</div>
</header>`;
}

function siteFooter(page, { config, copy, text }) {
  const locale = LOCALES[page.locale];
  const marks = MARKS.filter(({ mark }) => mark.test(text)).map((m) => `<p class="marks">${escapeHtml(m[page.locale])}</p>\n`).join('');
  const legal = FOOTER_LINKS.filter((link) => link.shown(config))
    .map(({ key }) => `<li><a href="${locale.footer[key].href}">${locale.footer[key].label}</a></li>`)
    .join('');
  return `<footer class="site-footer">
<div class="wrap">
<a class="brand" href="${locale.landing}" aria-label="${locale.ui.home}"><span class="mark" aria-hidden="true"></span>${SITE_NAME}</a>
<nav class="footer-site" aria-label="${locale.ui.siteNav}"><ul><li><a href="${locale.guidesBase}">${locale.ui.guides}</a></li><li><a href="${locale.footer.changelog.href}">${locale.footer.changelog.label}</a></li><li><a href="${locale.footer.history.href}">${escapeHtml(locale.footer.history.label)}</a></li></ul></nav>
<nav class="footer-legal" aria-label="${locale.ui.footerNav}"><ul>${legal}</ul></nav>
<p class="tagline" data-copy-id="footer.tagline">${escapeHtml(copy.get('footer.tagline')[page.locale])}</p>
${marks}</div>
</footer>`;
}

function renderPage(page, { config, groups, guidesByLocale, copy, stage }) {
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
  // The pages behind the mail links are never indexed; the sign-up form ships with the landing
  // page while the stage has one.
  const waitlistPage = page.kind === 'waitlist';
  const noindex = page.notices.length > 0 || waitlistPage || page.unlisted;
  const form = waitlistPage || (landing && stage !== 'launch');
  const report = page.report === true;
  const main = mainContent(page, guidesByLocale);
  const assets = [
    landing && '<link rel="stylesheet" href="/landing.css">',
    (form || report) && '<link rel="stylesheet" href="/waitlist.css">',
    report && '<link rel="stylesheet" href="/report.css">',
    landing && '<script src="/demo.js" defer></script>',
    landing && '<script type="module" src="/stores.js"></script>',
    landing && stage === 'launch' && '<script src="/get-app.js" defer></script>',
    form && '<script src="/waitlist.js" defer></script>',
    report && '<script type="module" src="/report.js"></script>',
    (page.kind === 'guide' || page.kind === 'index') && '<script src="/open-in-app.js" defer></script>',
  ].filter(Boolean).map((line) => `${line}\n`).join('');
  return `<!doctype html>
<html lang="${page.locale}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${comments}${noindex ? '<meta name="robots" content="noindex">\n' : ''}${page.unlisted ? '<meta name="snacklist-unlisted" content="true">\n' : ''}<title>${landing || page.kind === 'comparison' ? title : `${title} | ${SITE_NAME}`}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${url}">
${alternates}
${agentHead(page, url)}<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:type" content="${page.ogType}">
<meta property="og:url" content="${url}">
<meta property="og:locale" content="${locale.ogLocale}">
<meta property="og:site_name" content="${SITE_NAME}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="${title}">
<meta name="twitter:description" content="${description}">
${HEAD_ASSETS}${assets}</head>
<body${landing ? ' class="landing"' : ''}>
${page.notices.map(banner).join('')}${siteHeader(page, { switches, copy, current, stage })}
<main id="inhalt"${landing ? '' : ' class="wrap prose"'}>
${main}
</main>
${siteFooter(page, { config, copy, text: `${page.title} ${page.description} ${main.replace(/<[^>]*>/g, ' ')}` })}
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

// `rewrites` (vercel.json) are routes a function answers, such as /get.
export function checkHtml(file, html, outDir, siteUrl, rewrites = []) {
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
  // Only script files from this site (the CSP blocks inline code and other origins anyway), and
  // JSON-LD, which is data the browser never runs.
  for (const script of doc.querySelectorAll('script')) {
    if (script.getAttribute('type') === 'application/ld+json' && !script.getAttribute('src')) continue;
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
      rewrites.some((rule) => rule.source === path) ||
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

// The release timeline per locale (history.mjs), from the record alone.
function historyPages(repoDir) {
  const record = parseRecord(readRepoFile(repoDir, 'releases/releases.json'));
  const releases = publicReleases(record);
  return Object.keys(LOCALES).map((locale) => ({
    kind: 'history',
    file: `(history ${locale})`,
    route: HISTORY_ROUTES[locale],
    group: 'history',
    ogType: 'website',
    locale,
    title: historyText('history.title', locale),
    description: historyText('history.description', locale),
    notices: [],
    body: historyBody(record, releases, locale),
  }));
}

// The landing page per locale and the pages behind the mail links. Every copy id in copy.yml must
// appear on one of them in some stage, so the file holds no strings nobody sees.
function landingPages(contentDir, publicDir, config, stage) {
  const copy = readCopy(contentDir);
  const consent = readConsent(contentDir);
  const confirmConsent = readConsent(contentDir, 'waitlist-confirm');
  const used = new Set(['meta.title', 'meta.description', 'footer.tagline', 'nav.web-app']);
  const pages = Object.keys(LOCALES).flatMap((locale) => {
    const render = (s) => renderLanding({ locale, copy, config, publicDir, stage: s, consent: consent[locale] });
    for (const other of STAGES) for (const id of render(other).used) used.add(id);
    for (const other of STAGES) used.add(STAGE_CTA[other].id);
    const landing = render(stage);
    const actions = Object.entries(ACTION_PAGES).map(([action, routes]) => {
      const reader = copyReader(copy, locale);
      const body = actionPage(action, { locale, reader, consent: confirmConsent[locale], cta: STAGE_CTA[stage] });
      const title = reader.text(`waitlist.${action}.meta-title`);
      const description = reader.text(`waitlist.${action}.description`);
      for (const id of reader.used) used.add(id);
      return {
        kind: 'waitlist',
        file: `content/landing/copy.yml (${locale}, ${action} page)`,
        route: routes[locale],
        group: `waitlist:${action}`,
        ogType: 'website',
        locale,
        title,
        description,
        notices: [],
        body,
      };
    });
    return [
      {
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
      },
      ...actions,
    ];
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
  stage = readStage(),
  vercel = readVercel(),
} = {}) {
  const live = liveVersion(repoDir);
  const holds = Object.fromEntries(Object.entries(parseGates(readRepoFile(repoDir, 'releases/flags.json')).holds).map(([key, hold]) => [key, hold.released]));
  holds[STAGE_GATE] = stage === 'launch';
  const versions = { live: live.live, firstPublic: live.firstPublic, production: isProduction(env), holds };
  const pages = Object.keys(KINDS)
    .flatMap((kind) => KINDS[kind].files(contentDir).map((entry) => loadPage(kind, entry, contentDir, versions, config.alexaPublished)))
    .filter((page) => !(versions.production && page.notices.length > 0))
    .concat(changelogPages(repoDir, versions.production), historyPages(repoDir));
  const landing = landingPages(contentDir, publicDir, config, stage);
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
      pages.filter((p) => p.kind === 'guide' && p.locale === code && !p.unlisted).sort((a, b) => a.title.localeCompare(b.title, code)),
    ]),
  );

  const rendered = pages.map((page) => ({ page, html: renderPage(page, { config, groups, guidesByLocale, copy: landing.copy, stage }) }));

  const warnings = [];
  // A ⟦…⟧ marker stood for copy or legal text not written yet (job 82); none may ship in any build.
  const shipped = [
    ...rendered.map(({ page, html }) => ({ file: page.file, text: html })),
    ...['waitlist.js', 'waitlist.css', 'report.js', 'report.css'].map((f) => ({ file: `public/${f}`, text: readFileSync(join(publicDir, f), 'utf8') })),
  ];
  const markers = shipped.flatMap(({ file, text }) => [...new Set(text.match(/⟦[^⟧]*⟧?/g) ?? [])].map((p) => `${file}: ${p}`));
  if (markers.length > 0) throw new BuildError(`placeholder markers left; replace them with the approved text:\n  ${markers.join('\n  ')}`);
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
  writeGuideData({ outDir, pages, guidesByLocale, siteUrl: config.siteUrl });
  write('/', rootPage(config));
  write('/404', notFoundPage(config));
  const publicApi = readPublicApi(repoDir);
  writeAgentFiles({ outDir, rendered, siteUrl: config.siteUrl, contentDir, repoDir, publicApi, stage });

  for (const file of htmlFiles(outDir)) checkHtml(file, readFileSync(file, 'utf8'), outDir, config.siteUrl, vercel.rewrites);
  const { problems } = checkAgentSite({ dist: outDir, siteUrl: config.siteUrl, vercel, stage, publicApi, previewStage: Boolean(env.SITE_STAGE) });
  if (problems.length > 0) throw new BuildError(`agent checks failed:\n  ${problems.map((p) => `${p.check}: ${p.file}: ${p.message}`).join('\n  ')}`);

  return { routes: ['/', ...pages.map((p) => p.route)], warnings, live };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { routes, warnings, live } = build({ env: { VERCEL_ENV: process.env.VERCEL_ENV, SITE_STAGE: stageOverride() } });
    for (const w of warnings) console.warn(`warning: ${w}`);
    console.log(`live version: ${live.live} (from ${live.source})`);
    console.log(`built ${routes.length} pages into dist/`);
  } catch (error) {
    if (!(error instanceof BuildError || error instanceof RecordError || error instanceof CopyError || error instanceof AgentError || error instanceof HistoryCopyError)) throw error;
    console.error(`build failed: ${error.message}`);
    process.exit(1);
  }
}
