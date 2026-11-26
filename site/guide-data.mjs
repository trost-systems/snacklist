// The guides as JSON for the app's own guide view (job 462, README.md "Data for the app"). The
// blocks come from the markdown-it tokens the guide's HTML is rendered from, gating and skill links
// done, so the app shows what the site shows in the same build, without the page around it.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SCHEMA = 1;

// Site-relative links point at the site; in-page anchors (#id) and absolute URLs stay as they are.
const absolute = (href, siteUrl) => (href.startsWith('/') && !href.startsWith('//') ? siteUrl + href : href);

function spans(children, siteUrl) {
  const out = [];
  const marks = { strong: false, em: false, href: null };
  const push = (text, code = false) => {
    if (text === '') return;
    const span = { text, ...(marks.strong && { strong: true }), ...(marks.em && { em: true }), ...(code && { code: true }), ...(marks.href !== null && { href: marks.href }) };
    const last = out.at(-1);
    if (last && JSON.stringify({ ...last, text: '' }) === JSON.stringify({ ...span, text: '' })) last.text += text;
    else out.push(span);
  };
  for (const child of children) {
    switch (child.type) {
      case 'strong_open':
      case 'strong_close':
        marks.strong = child.nesting === 1;
        break;
      case 'em_open':
      case 'em_close':
        marks.em = child.nesting === 1;
        break;
      case 'link_open':
        marks.href = absolute(child.attrGet('href'), siteUrl);
        break;
      case 'link_close':
        marks.href = null;
        break;
      case 'code_inline':
        push(child.content, true);
        break;
      case 'softbreak':
      case 'hardbreak':
        push('\n');
        break;
      default:
        // text, and an image's alt text
        push(child.content);
    }
  }
  return out;
}

function blocks(tokens, siteUrl) {
  let i = 0;
  // An open token, its inline token and its close token.
  const inline = () => {
    const text = spans(tokens[i + 1].children, siteUrl);
    i += 3;
    return text;
  };
  // The blocks up to the close token at `level`, which is consumed.
  const until = (level) => {
    const out = [];
    while (i < tokens.length && !(tokens[i].nesting === -1 && tokens[i].level === level)) out.push(...next());
    i++;
    return out;
  };
  const listItems = () => {
    const items = [];
    while (tokens[i].type === 'list_item_open') {
      i++;
      items.push(until(tokens[i - 1].level));
    }
    i++;
    return items;
  };
  const table = () => {
    const out = { type: 'table', header: [], rows: [] };
    let head = false;
    while (tokens[i].type !== 'table_close') {
      const token = tokens[i++];
      if (token.type === 'thead_open' || token.type === 'thead_close') head = token.nesting === 1;
      if (token.type !== 'tr_open') continue;
      const cells = [];
      while (tokens[i].type !== 'tr_close') cells.push(inline());
      i++;
      if (head) out.header = cells;
      else out.rows.push(cells);
    }
    i++;
    return out;
  };
  const next = () => {
    const token = tokens[i];
    switch (token.type) {
      case 'heading_open':
        return [{ type: 'heading', level: Number(token.tag.slice(1)), id: token.attrGet('id'), text: inline() }];
      case 'paragraph_open':
        return [{ type: 'paragraph', text: inline() }];
      case 'bullet_list_open':
      case 'ordered_list_open':
        i++;
        return [{ type: 'list', ordered: token.type === 'ordered_list_open', items: listItems() }];
      case 'blockquote_open':
        i++;
        return [{ type: 'quote', blocks: until(token.level) }];
      case 'fence':
      case 'code_block':
        i++;
        return [{ type: 'code', text: token.content.replace(/\n$/, '') }];
      case 'table_open':
        i++;
        return [table()];
      case 'html_block':
        i++;
        // The since note shows in production too; draft and gate banners never do.
        return token.meta?.note ? [{ type: 'paragraph', text: [{ text: token.meta.note, em: true }] }] : [];
      default:
        i++;
        // A shown `::: since` block (preview builds) is transparent; a rule (`---`) has no block.
        return token.nesting === 1 ? until(token.level) : [];
    }
  };
  const out = [];
  while (i < tokens.length) out.push(...next());
  return out;
}

export function guideJson(page, siteUrl) {
  const all = blocks(page.tokens, siteUrl);
  const h1 = all.findIndex((b) => b.type === 'heading' && b.level === 1);
  return {
    schema: SCHEMA,
    locale: page.locale,
    slug: page.slug,
    title: page.title,
    description: page.description,
    updated: page.updated,
    url: siteUrl + page.route,
    blocks: all.filter((_, j) => j !== h1),
  };
}

// dist/data/guides/<locale>/<slug>.json for every guide this build renders (unlisted ones too, as
// their pages exist), and <locale>/index.json listing what the locale's index page lists.
export function writeGuideData({ outDir, pages, guidesByLocale, siteUrl }) {
  for (const [locale, listed] of Object.entries(guidesByLocale)) {
    const dir = join(outDir, 'data/guides', locale);
    mkdirSync(dir, { recursive: true });
    const write = (name, data) => writeFileSync(join(dir, `${name}.json`), `${JSON.stringify(data)}\n`);
    for (const page of pages.filter((p) => p.kind === 'guide' && p.locale === locale)) write(page.slug, guideJson(page, siteUrl));
    const index = pages.find((p) => p.kind === 'index' && p.locale === locale);
    write('index', {
      schema: SCHEMA,
      locale,
      title: index.title,
      guides: listed.map((g) => ({ slug: g.slug, title: g.title, description: g.description, url: siteUrl + g.route })),
    });
  }
}
