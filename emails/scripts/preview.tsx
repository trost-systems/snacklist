// Renders every mail to PNG with Playwright's Chromium: 600 px (desktop) and 375 px (mobile),
// light and dark (every mail but the catalog); one with images blocked; both footers on a
// phone; then a contact sheet and index.html, one review page with every mail's subject, PNGs,
// HTML and plain text. Requests to https://snacklist.app/ are served from site/public, so
// the previews show the assets this branch ships before they are deployed. No other network.
//   npx tsx scripts/preview.tsx [--out <dir>] [--scale 1|2] [<id> ...]
//   npx tsx scripts/preview.tsx --sheet --out <dir>    only the contact sheet, from the PNGs in <dir>
// Local only, one browser: flock /tmp/fg-e2e.lock npm run preview
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { chromium, type Page } from 'playwright';
import { renderEmail } from '../src/render.ts';
import { EMAILS, fillDemo, type Email } from '../src/registry.tsx';

const args = process.argv.slice(2);
const option = (name: string): string | undefined => {
  const at = args.indexOf(name);
  if (at < 0) return undefined;
  const [, value] = args.splice(at, 2);
  if (value === undefined) throw new Error(`${name} needs a value`);
  return value;
};
const out = option('--out') ?? '/tmp/fg-email-previews';
const sheetOnly = args.includes('--sheet');
if (sheetOnly) args.splice(args.indexOf('--sheet'), 1);
const scale = Number(option('--scale') ?? 2);
const only = new Set(args);
const sitePublic = fileURLToPath(new URL('../../site/public/', import.meta.url));

const WIDTHS = { desktop: 600, mobile: 375 } as const;
const BLOCKED = 'welcome-android-de';
const FOOTERS = {
  'partner-joined-de': 'transactional-footer-de-mobile', 'partner-joined-en': 'transactional-footer-en-mobile',
  'welcome-android-de': 'onboarding-footer-de-mobile', 'welcome-android-en': 'onboarding-footer-en-mobile',
} as const;

const emails = EMAILS.filter((e) => only.size === 0 || only.has(e.id));

// <email>-<lang>-<desktop|mobile>[-dark]; ids like welcome-android-de already end in their lang.
const base = (e: Email) => (e.id.endsWith(`-${e.lang}`) ? e.id : `${e.id}-${e.lang}`);

mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const shots: string[] = [];
const reviewed: { email: Email; name: string; subject: string; text: string; shots: string[] }[] = [];

async function shoot(email: Email, html: string, name: string, width: number, opts: { dark?: boolean; blockImages?: boolean; footer?: boolean } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 300 }, deviceScaleFactor: scale, colorScheme: opts.dark ? 'dark' : 'light' });
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    if (url.protocol === 'data:') return route.continue();
    if (url.origin === 'https://snacklist.app' && !opts.blockImages) {
      const file = join(sitePublic, decodeURIComponent(url.pathname));
      if (existsSync(file)) return route.fulfill({ body: readFileSync(file), contentType: 'image/png' });
    }
    return route.abort();
  });
  const page: Page = await context.newPage();
  await page.setContent(html, { waitUntil: 'load' });
  const path = join(out, `${name}.png`);
  if (opts.footer) await page.locator('[data-hl-text=footer]').screenshot({ path });
  else await page.screenshot({ path, fullPage: true });
  await context.close();
  shots.push(path);
  console.log(`${email.id}: ${path}`);
}

for (const email of sheetOnly ? [] : emails) {
  const { html, text } = await renderEmail(email.element);
  const shown = fillDemo(html, email.demo);
  const first = shots.length;
  writeFileSync(join(out, `${base(email)}.html`), shown);
  writeFileSync(join(out, `${base(email)}.txt`), fillDemo(text, email.demo));
  for (const [device, width] of Object.entries(WIDTHS)) {
    const name = `${base(email)}-${device}`;
    await shoot(email, shown, name, width);
    if (email.kind !== 'catalog') await shoot(email, shown, `${name}-dark`, width, { dark: true });
  }
  if (email.id === BLOCKED) await shoot(email, shown, `${base(email)}-mobile-images-blocked`, WIDTHS.mobile, { blockImages: true });
  const footer = FOOTERS[email.id as keyof typeof FOOTERS];
  if (footer) await shoot(email, shown, footer, WIDTHS.mobile, { footer: true });
  reviewed.push({ email, name: base(email), subject: fillDemo(email.subject, email.demo), text: fillDemo(text, email.demo), shots: shots.slice(first) });
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
if (reviewed.length && only.size === 0) {
  const kinds = { auth: 'Sign-in and account (Supabase Auth)', notice: 'Service notices', onboarding: 'Onboarding', catalog: 'Component catalog' };
  const sections = reviewed.map(({ email, name, subject, text, shots: pngs }) => `
<section id="${name}">
  <h2>${esc(name)} <small>${kinds[email.kind]} · ${email.lang.toUpperCase()}</small></h2>
  <p class="subject"><b>Subject:</b> ${esc(subject)}</p>
  ${email.note ? `<p class="note">${esc(email.note)}</p>` : ''}
  <p><a href="${name}.html">Open the HTML</a></p>
  <div class="shots">${pngs.map((p) => `<figure><a href="${basename(p)}"><img src="${basename(p)}" loading="lazy" alt="${esc(basename(p))}"></a><figcaption>${esc(basename(p).replace(/\.png$/, ''))}</figcaption></figure>`).join('')}</div>
  <details><summary>Plain text</summary><pre>${esc(text)}</pre></details>
</section>`).join('');
  const nav = reviewed.map(({ name }) => `<a href="#${name}">${esc(name)}</a>`).join(' · ');
  writeFileSync(join(out, 'index.html'), `<!doctype html><html lang="en"><meta charset="utf-8"><title>Snacklist mails: review</title>
<style>body{margin:0 auto;max-width:1400px;padding:24px;font:15px/1.5 system-ui,sans-serif;background:#f4f4f2;color:#1b1b1f}
section{background:#fff;border-radius:12px;padding:16px 20px;margin:20px 0}h2{margin:0 0 4px}small{font-weight:400;color:#666}
.shots{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start}figure{margin:0}figure img{display:block;border:1px solid #ddd}
.shots figure:first-child img{width:600px}.shots img{width:375px}.note{color:#8a5a00}pre{white-space:pre-wrap;background:#f7f7f7;padding:12px}
nav{font-size:13px}</style>
<h1>Snacklist mails: review</h1>
<p>Every mail in German and English, rendered from <code>emails/</code> with demo data (Anna, example.com addresses). The Supabase Auth mails are one template per type: Supabase sends the German version when the account's <code>mail_locale</code> is <code>de</code> and the English one otherwise. Nothing here was sent. PNGs at ${scale}x: desktop 600 px, phone 375 px, some in dark mode.</p>
<nav>${nav}</nav>${sections}</html>
`);
  console.log(`review page: ${join(out, 'index.html')}`);
}

if (sheetOnly) shots.push(...readdirSync(out).filter((n) => n.endsWith('.png') && n !== 'contact-sheet.png').sort().map((n) => join(out, n)));
if (only.size === 0) {
  const tiles = shots.map((p) => {
    const name = basename(p, '.png');
    return `<figure><img src="data:image/png;base64,${readFileSync(p).toString('base64')}"><figcaption>${name}</figcaption></figure>`;
  }).join('');
  const sheet = `<!doctype html><style>body{margin:0;padding:16px;background:#ddd;font:12px sans-serif;columns:10 140px;column-gap:12px}
figure{margin:0 0 12px;break-inside:avoid;background:#fff;padding:6px}img{width:100%;display:block}figcaption{padding-top:4px}</style>${tiles}`;
  const context = await browser.newContext({ viewport: { width: 1600, height: 600 } });
  const page = await context.newPage();
  await page.setContent(sheet, { waitUntil: 'load' });
  await page.screenshot({ path: join(out, 'contact-sheet.png'), fullPage: true });
  console.log(`contact sheet: ${join(out, 'contact-sheet.png')}`);
}
await browser.close();
