#!/usr/bin/env node
// The phone screen of the hero (hero.html) from the real app: Jonas's list in „Unser Haushalt“
// („Our Home“) 1 to 2 s after Anna added Hafermilch (Oat milk) at the Wochenmarkt, honey under
// „1 neu von Anna“, light and dark, de and en, from this checkout's verify-snacklist instance.
// Writes hero-screen/<de|en>-<wide|compact>[-dark].webp next to this file. capture-hero.sh launches the
// instance with the launch flags and runs this, then film-all.mjs hero.
//
//   node site/scenes/capture-hero.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { addField, apiAs, chromium, instance, itemRow, labels, repo, signIn } from '../../.claude/skills/verify-snacklist/helpers/lib.mjs';
import { launchLook } from '../../marketing/launch-look.mjs';

const OUT = join(import.meta.dirname, 'hero-screen');
const WIDTH = 360;
const DPR = 3;
// hero.html's phone screen per size in scene px: its width, the height the stage shows of it and
// the band above the shot. The shot ends 6 px under the add field, above the tab bar.
const SIZES = { wide: { screen: 332, shown: 456, top: 0 }, compact: { screen: 286, shown: 336, top: 26 } };
const INPUT = {
  de: { scenario: 'demo-haushalt', added: 'Hafermilch', store: 'Wochenmarkt' },
  en: { scenario: 'demo-household-en', added: 'Oat milk', store: 'Farmers market' },
};

const inst = instance();
const fg = (args) => execFileSync(join(repo, 'scripts/fg'), args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });

function seed(scenario) {
  const doc = JSON.parse(fg(['seed', scenario]));
  if (!doc.ok) throw new Error(`fg seed ${scenario}: ${JSON.stringify(doc.error)}`);
  const manifest = JSON.parse(readFileSync(join(process.env.FG_STATE_DIR, 'runs', `${doc.run}.json`), 'utf8'));
  const members = Object.fromEntries(Object.entries(manifest.users).map(([h, u]) => [h, { ...u, householdId: manifest.households[u.household]?.id }]));
  return { id: doc.run, members, seededAt: Math.floor(Date.parse(manifest.createdAt) / 1000) * 1000 };
}

async function box(locator) {
  const b = await locator.boundingBox();
  if (!b) throw new Error(`${locator} has no box`);
  return { ...b, bottom: b.y + b.height };
}

/** Lets the app lay out and draw on the paused clock: fake frames and real time for the renderer. */
async function settle(page) {
  for (let i = 0; i < 12; i++) {
    await page.clock.runFor(16);
    await new Promise((r) => setTimeout(r, 40));
  }
}

async function must(query) {
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data;
}

const browser = await chromium.launch();
const errors = [];
mkdirSync(OUT, { recursive: true });

async function shoot(lang, dark) {
  const L = labels(lang);
  const input = INPUT[lang];
  const run = seed(input.scenario);
  const context = await browser.newContext({
    baseURL: inst.webUrl,
    viewport: { width: WIDTH, height: 800 },
    deviceScaleFactor: DPR,
    locale: lang === 'en' ? 'en-US' : 'de-DE',
    timezoneId: 'Europe/Berlin',
    colorScheme: dark ? 'dark' : 'light',
    reducedMotion: 'no-preference',
    serviceWorkers: 'block',
  });
  try {
    const page = await context.newPage();
    page.on('pageerror', (e) => errors.push(`${lang}${dark ? ' dark' : ''}: ${e.message}`));
    await page.clock.install({ time: run.seededAt });
    await signIn(page, L, run.members.jonas);
    await launchLook(page, L, `${lang}${dark ? ' dark' : ''}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(800);
    // The resting pointer away from the list (a hover shows the web build's scrollbar).
    await page.mouse.move(2, 798);
    // How far the add field's bottom sits above the screen's bottom edge (the tab bar's band).
    const below = 800 - (await box(addField(page, L))).bottom;
    const now = await page.evaluate(() => Date.now());
    await page.clock.pauseAt(run.seededAt + Math.ceil((now + 1000 - run.seededAt) / 16) * 16);
    const anna = run.members.anna;
    const api = await apiAs(inst, anna);
    const store = await must(api.from('stores').select('id').eq('name', input.store).single());
    await must(api.from('items').insert({ household_id: anna.householdId, name: input.added, store_id: store.id, status: 'active' }));
    const strip = page.getByText(L('newItemsFrom', { count: 1, name: anna.name }));
    const end = Date.now() + 30_000;
    while (!(await strip.isVisible().catch(() => false))) {
      if (Date.now() > end) throw new Error(`${lang}: „${L('newItemsFrom', { count: 1, name: anna.name })}“ did not show`);
      await page.clock.runFor(16);
      await new Promise((r) => setTimeout(r, 15));
    }
    await page.clock.runFor(300);
    for (const [size, { screen, shown, top }] of Object.entries(SIZES)) {
      const height = Math.round(((shown - top) * WIDTH) / screen) + below - 6;
      await page.setViewportSize({ width: WIDTH, height });
      await settle(page);
      // A key restarts the caret's 500 ms blink, so 700 ms later it is off.
      await page.keyboard.press('End');
      await page.clock.runFor(700);
      const field = await box(addField(page, L));
      const row = await box(itemRow(page, input.added));
      if (row.y < 0 || row.bottom > field.y) throw new Error(`${lang} ${size}: ${input.added} is not in view above the add field`);
      const tabs = await box(page.getByRole('tablist').last());
      if (tabs.y < field.bottom + 6) throw new Error(`${lang} ${size}: the tab bar starts ${tabs.y - field.bottom} px under the add field`);
      const png = join(OUT, `${lang}-${size}${dark ? '-dark' : ''}.png`);
      // Down to the add field and 6 px under it: the tab bar stays out of the scene.
      await page.screenshot({ path: png, clip: { x: 0, y: 0, width: WIDTH, height: Math.ceil(field.bottom) + 6 } });
      const webp = png.replace(/\.png$/, '.webp');
      execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', png, '-quality', '92', webp]);
      rmSync(png);
      console.log(`hero screen: ${webp}`);
    }
  } finally {
    await context.close();
    fg(['teardown', run.id]);
  }
}

try {
  for (const lang of ['de', 'en']) for (const dark of [false, true]) await shoot(lang, dark);
} finally {
  await browser.close();
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
