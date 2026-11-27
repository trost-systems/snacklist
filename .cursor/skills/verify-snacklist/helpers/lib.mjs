// Shared by the verify-snacklist journeys and the snacklist-howto-clips scripts: the running
// instance (launch.sh's instance.json), its seeded members, UI labels from the ARB files, a
// browser on the web build signed in through the real login screen, and a second view of the data.
import process from 'node:process';
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { execFileSync } from 'node:child_process';

export const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const fromE2e = createRequire(resolve(repo, 'e2e/package.json'));
export const { chromium } = fromE2e('@playwright/test');
const { createClient } = fromE2e('@supabase/supabase-js');

/** launch.sh's record of the instance: URLs, run id, credentials file, evidence dir. */
export function instance() {
  const prefix = /^port = ([56]\d\d)21$/m.exec(readFileSync(join(repo, 'supabase/config.toml'), 'utf8'))?.[1];
  const stateDir = process.env.VH_STATE_DIR ?? join(homedir(), '.cache/verify-snacklist', prefix ?? '543');
  const file = join(stateDir, 'instance.json');
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    throw new Error(`no instance at ${file}: run .cursor/skills/verify-snacklist/helpers/launch.sh first`);
  }
}

/** A seeded member ({ handle, email, password, name, locale }) of the instance's run; the first by default. */
export function member(inst, handle) {
  const run = JSON.parse(readFileSync(inst.credentials, 'utf8'));
  const users = Object.values(run.users);
  const user = handle ? run.users[handle] : users[0];
  if (!user) throw new Error(`run ${inst.run} has no member ${handle}; it has ${Object.keys(run.users).join(', ')}`);
  return { ...user, householdId: run.households[user.household]?.id };
}

/** The app's UI strings for a language, by ARB key ('de' or 'en'). */
export function labels(lang) {
  const arb = JSON.parse(readFileSync(join(repo, `app/l10n/app_${lang}.arb`), 'utf8'));
  return (key, params = {}) => {
    const value = arb[key];
    if (typeof value !== 'string') throw new Error(`app_${lang}.arb has no ${key}`);
    return value.replace(/\{(\w+)\}/g, (_, p) => params[p] ?? `{${p}}`);
  };
}

/** Whether the build has a PostHog flag on: env.sh's FLAGS_ON from the same VH_* variables doctor.sh checks the build against. */
export function flagOn(key) {
  const { flags } = JSON.parse(readFileSync(join(repo, 'releases/flags.json'), 'utf8'));
  const off = (process.env.VH_FLAGS_OFF ?? '').split(',').map((s) => s.trim());
  const full = process.env.VH_FLAGS_FULL === '0' ? [] : Object.keys(flags).filter((k) => flags[k].rollout === 'full' && !off.includes(k));
  const extra = (process.env.VH_DEFINES ?? '').split(/\s+/).filter((p) => p.startsWith('FLAGS_ON=')).flatMap((p) => p.slice('FLAGS_ON='.length).split(','));
  return [...full, ...extra].includes(key);
}

/** The add field, found like a user finds it: by its hint. */
export const addField = (page, L) => page.getByRole('textbox', { name: L('addFieldHint') });

/** The add sheet (a group named like the add button). */
export const addSheet = (page, L) => page.getByRole('group', { name: L('addButton'), exact: true });

/** A list row by item name: a checkbox (since job 57) named by the item, then the quantity. */
export const itemRow = (page, name) => page.getByRole('checkbox', { name: new RegExp(`^${escape(name)}( |$)`) });

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Resolves once Flutter has drawn the frame it had scheduled. */
export const nextFrames = (page) => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));

/**
 * Focus first, then insert: Flutter swaps in its own editor on focus, and synthetic key events
 * drop umlauts (e2e/tests/helpers.ts typeInto). With `perKey` it types visibly, a key at a time.
 */
export async function typeInto(field, text, { perKey = 0 } = {}) {
  const page = field.page();
  for (let attempt = 0; ; attempt++) {
    await field.click();
    const focused = await field.evaluate((el) => el === document.activeElement || el.contains(document.activeElement)).catch(() => false);
    if (focused) {
      await nextFrames(page);
      await page.keyboard.press('ControlOrMeta+a');
      if (perKey) {
        await page.keyboard.press('Backspace');
        for (const ch of text) {
          await page.keyboard.insertText(ch);
          await page.waitForTimeout(perKey);
        }
      } else {
        await page.keyboard.insertText(text);
      }
      await nextFrames(page);
      if ((await field.inputValue().catch(() => '')) === text) return;
    }
    if (attempt === 20) throw new Error(`could not type "${text}"`);
    await page.waitForTimeout(250);
  }
}

/**
 * A fresh browser context on the web build. lang 'de' or 'en' sets the browser locale, which the
 * app follows while its language is "System". Video goes to `videoDir` when given.
 */
export async function openApp(inst, { lang = 'de', locale, viewport = { width: 390, height: 844 }, dpr = 2, dark = false, videoDir, headless = true } = {}) {
  const browser = await chromium.launch({ headless });
  const context = await browser.newContext({
    baseURL: inst.webUrl,
    viewport,
    deviceScaleFactor: dpr,
    // The browser's language region is the phone's region on the web (`de-AT`: Austria's store chips).
    locale: locale ?? (lang === 'en' ? 'en-US' : 'de-DE'),
    timezoneId: 'Europe/Berlin',
    colorScheme: dark ? 'dark' : 'light',
    ...(videoDir && { recordVideo: { dir: videoDir, size: viewport } }),
  });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  return { browser, context, page, L: labels(lang), errors };
}

/**
 * Signs a member in on the login screen with email and password, declines the analytics question
 * a new install asks, dismisses the Erste Schritte card, and waits for the focused add field.
 */
export async function signIn(page, L, user) {
  // Signed out, `/` is the guided start's first screen (job 168b); `/login` is the sign-in.
  await page.goto('/login');
  // Builds with Google or Apple keep the email form behind „Weiter mit E-Mail“ (job 70).
  const withEmail = page.getByRole('button', { name: L('continueWithEmail') });
  await withEmail.or(page.getByRole('textbox', { name: L('email') })).waitFor({ timeout: 30_000 });
  if (await withEmail.isVisible()) await withEmail.click();
  await typeInto(page.getByRole('textbox', { name: L('email') }), user.email);
  await typeInto(page.getByRole('textbox', { name: L('password') }), user.password);
  await page.keyboard.press('Enter');
  const decline = page.getByRole('button', { name: L('analyticsDecline'), exact: true });
  const landed = await Promise.race([
    addField(page, L).waitFor({ timeout: 30_000 }).then(() => 'list'),
    page.waitForURL(/\/analytics-consent(\?|$)/, { timeout: 30_000 }).then(() => 'consent'),
  ]);
  if (landed === 'consent') {
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    for (let i = 0; i < 10 && !(await decline.isVisible()); i++) {
      await page.mouse.wheel(0, 400);
      await page.waitForTimeout(200);
    }
    await decline.click();
    await addField(page, L).waitFor({ timeout: 30_000 });
  }
  const hint = page.getByRole('button', { name: L('checklistDismiss'), exact: true });
  if (await hint.waitFor({ timeout: 3_000 }).then(() => true, () => false)) await hint.click();
}

/** A supabase-js client signed in as the member: the read-only second view of what the UI did. */
export async function apiAs(inst, user) {
  const client = createClient(inst.apiUrl, inst.publishableKey, { auth: { persistSession: false } });
  const { error } = await client.auth.signInWithPassword({ email: user.email, password: user.password });
  if (error) throw error;
  return client;
}

/** Writes a screenshot and an ARIA snapshot of the page under dir as <name>.png / .aria.txt. */
export async function capture(page, dir, name) {
  mkdirSync(dir, { recursive: true });
  await nextFrames(page);
  await page.screenshot({ path: join(dir, `${name}.png`) });
  writeFileSync(join(dir, `${name}.aria.txt`), await page.locator('body').ariaSnapshot());
  return join(dir, `${name}.png`);
}

/** Records one line of a journey's log (stdout and <dir>/journey.log). */
export function logger(dir) {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, 'journey.log');
  writeFileSync(file, '');
  return (line) => {
    const stamped = `[${new Date().toISOString().slice(11, 23)}Z] ${line}`;
    console.log(stamped);
    writeFileSync(file, `${stamped}\n`, { flag: 'a' });
  };
}

export const commit = () => execFileSync('git', ['-C', repo, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();

/** The accessible name in one line of an ARIA snapshot (`- button "Joghurt, Aus dem Katalog"`). */
export const accessibleName = (snapshotLine) => /"(.*)"/.exec(snapshotLine.split('\n')[0])?.[1] ?? snapshotLine.trim();

/** The text of the nearest level-2 heading (a category or store divider) above a row. */
export async function headingAbove(page, row) {
  const y = (await row.boundingBox()).y;
  let best = null;
  for (const heading of await page.getByRole('heading', { level: 2 }).all()) {
    const box = await heading.boundingBox();
    if (box && box.y < y && (!best || box.y > best.y)) best = { y: box.y, text: (await heading.textContent()).trim() };
  }
  return best?.text ?? null;
}

/**
 * The list's button naming household [name]: the switcher („Einkaufsliste · Familie Brandt“, with
 * list-declutter, as users have it) or the household chip of a `VH_FLAGS_FULL=0` build.
 */
export const householdButton = (page, name) => page.getByRole('button', { name: new RegExp(`(^|· )${escape(name)}(\\s|$)`) });

/**
 * Opens „Deine Haushalte“ from the list showing household [name]: the switcher sheet opens on the
 * household's page, whose „Zurück: Haushalte“ leads there; the chip opens it directly.
 */
export async function openHouseholds(page, L, name) {
  await householdButton(page, name).first().click();
  const heading = page.getByRole('heading', { name: L('householdsTitle') });
  const back = page.getByRole('button', { name: L('switcherBack', { page: L('switcherHouseholds') }), exact: true });
  await heading.or(back).first().waitFor({ timeout: 10_000 });
  if (!(await heading.count())) await back.click();
  await heading.waitFor({ timeout: 10_000 });
}

/**
 * Shows household [to]'s first list from the list showing [from]: on „Deine Haushalte“ its row
 * switches at once with the chip; the switcher sheet opens the household's page, whose list row
 * („Einkaufsliste nichts offen“) switches and closes the sheet.
 */
export async function switchHousehold(page, L, from, to) {
  await openHouseholds(page, L, from);
  await page.getByRole('button', { name: new RegExp(`^${escape(to)}\\s+\\d+ `) }).click();
  const listRow = page.getByRole('button', { name: /\s(nichts offen|nothing open|\d+ (offen|open))( \S+)?$/ });
  const back = page.getByRole('button', { name: L('switcherBack', { page: L('switcherHouseholds') }), exact: true });
  if (await back.waitFor({ timeout: 3_000 }).then(() => true, () => false)) {
    await listRow.first().click();
    await back.waitFor({ state: 'detached', timeout: 10_000 });
  }
  await householdButton(page, to).first().waitFor({ timeout: 10_000 });
}

/**
 * Answers „Kaufst du gerade ein?“, the question trip-mode asks after a member's own tick while no
 * trip runs (off for users since 2026-11-22, Peter HP2, job 401; `VH_DEFINES="FLAGS_ON=trip-mode"`
 * turns it on), with the button of ARB key [key]: 'shopAskNo', 'shopAskYes' or 'shopAskTakeBack'. Returns false when the question did not come within [timeout] ms (a
 * pharmacy's item, a running trip, the hour after a 'shopAskNo' in this browser context, a
 * build without trip-mode, a plain launch included).
 */
export async function answerShopAsk(page, L, key = 'shopAskNo', timeout = 3_000) {
  const button = page.getByRole('button', { name: L(key), exact: true });
  try {
    await button.waitFor({ timeout });
  } catch {
    return false;
  }
  await button.click();
  await button.waitFor({ state: 'detached', timeout: 5_000 });
  return true;
}

/**
 * Folds „Zuletzt verwendet“ when it is open, as it starts with recently-used-open (full since
 * 2026-11-22). A journey that scrolls to the list's end needs it: the open section's rows push the
 * summary block and the store sections out of the rows the list builds. The fold is kept per device.
 */
export async function foldRecentlyUsed(page, L) {
  const section = page.getByRole('button', { name: L('recentlyUsed'), exact: true });
  const rows = page.getByRole('button', { name: new RegExp(` ${escape(L('readd'))}$`) });
  // Below a few open rows the list has not built the section yet (vmaint-20261127: list-summary
  // then found nothing to fold), so wheel to it first, and back to the top after.
  if (!(await reveal(page, section).then(() => true, () => false))) return false;
  await rows.first().waitFor({ state: 'attached', timeout: 2_000 }).catch(() => {});
  if (!(await rows.count())) return false;
  await section.click();
  await rows.first().waitFor({ state: 'detached', timeout: 5_000 });
  await page.mouse.wheel(0, -20_000);
  await page.waitForTimeout(300);
  return true;
}

/** A tab of the shell by its ARB key ('tabList' or 'tabMore'): the bottom bar on phones, the rail from 840 px. */
export async function openTab(page, L, key) {
  await page.getByRole('tab', { name: L(key), exact: true }).click();
}

/**
 * Scrolls with the mouse wheel until [target] is fully on screen, above the add bar when there is
 * one (e2e helpers' reveal). The list builds rows lazily, so a row far below is not in the page
 * until the list scrolls near it; a built row below the screen still counts as visible to
 * Playwright, so a click there lands on whatever is drawn at that spot. A target the list cannot
 * move further (its start or end) is as far in as it gets.
 */
export async function reveal(page, target) {
  const { width, height } = page.viewportSize();
  const top = async (locator) => ((await locator.count()) ? await locator.boundingBox({ timeout: 5_000 }).catch(() => null) : null)?.y ?? height;
  const hint = new RegExp(`^(${escape(labels('de')('addFieldHint'))}|${escape(labels('en')('addFieldHint'))})$`);
  const tabs = await top(page.getByRole('tablist'));
  const bottom = Math.min((await top(page.getByRole('textbox', { name: hint }))) - 12, tabs > height / 2 ? tabs : height);
  await page.mouse.move(width / 2, Math.min(height / 3, bottom / 2));
  // A row cut off at the list's edge keeps only its visible part as its box, so a box that touches
  // the edge counts as cut off until the wheel no longer moves it. 44: the bar above the list.
  const listTop = 44;
  let last;
  for (let i = 0; i < 40; i++) {
    const box = (await target.count()) ? await target.boundingBox({ timeout: 5_000 }).catch(() => null) : null;
    const inside = box && box.y > listTop + 0.5 && box.y + box.height < bottom - 0.5;
    const stuck = box && last && box.y === last.y && box.height === last.height;
    if ((inside && stuck) || (stuck && last.wheeled)) return;
    const down = box ? box.y + box.height >= bottom - 0.5 : i < 20;
    const wheeled = !inside;
    const near = box && box.y < bottom && box.y + box.height > listTop;
    if (wheeled) await page.mouse.wheel(0, (down ? 1 : -1) * (near ? 100 : 250));
    last = box && { y: box.y, height: box.height, wheeled };
    await page.waitForTimeout(150);
  }
  throw new Error(`could not scroll ${target} into view`);
}
