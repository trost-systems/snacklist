// Feature language (job 245): the app in English on `demo-family-en`, screen by screen, with a
// screenshot and an ARIA snapshot of each, and a scan of every snapshot for German words. Fails when
// a screen shows German outside the data the household typed (and the store chains' own names).
// Launch with VH_DEFINES="FLAGS_ON=trip-mode,grocery-log,prices-and-trip-total" for the trip steps.
//
//   node journeys/english-sweep.mjs <evidence dir> [--dark]
import process from 'node:process';
import { addField, addSheet, capture, instance, itemRow, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: english-sweep.mjs <evidence dir> [--dark]');

const log = logger(dir);
const inst = instance();
const user = member(inst);

/** Umlauts, ß and German words that do not occur in English UI text. */
const german = /[äöüÄÖÜß]|\b(?:und|oder|nicht|keine?|Bitte|bitte|Liste|Einkauf\w*|Haushalt\w*|Fehler|Abbrechen|Speichern|Löschen|Einladung|Mitglied\w*|Deine?|deine?|wird|ist|sind|einen?|mit|auf|noch|jetzt|hier|Laden|Läden|Artikel|Eintr\w+|Einstellungen|Mehr|Zurück|Weiter|Fertig|Konto|Anmelden|Abmelden|Hilfe|Datenschutz|Impressum|Sprache|Geschäft\w*)\b/g;
/** Store chain names, kept as their owners write them. */
const allowed = ['Aldi Süd'];

const findings = [];
function scan(name, aria) {
  let text = aria;
  for (const a of allowed) text = text.replaceAll(a, '');
  const hits = [...new Set([...text.matchAll(german)].map((m) => m[0]))];
  const lines = text.split('\n').filter((line) => new RegExp(german.source).test(line));
  if (hits.length) findings.push({ name, hits, lines });
  log(`${hits.length ? 'GERMAN' : 'ok'} ${name}${hits.length ? `: ${hits.join(', ')}` : ''}`);
  for (const line of lines) log(`    ${line.trim()}`);
}

const { browser, page, L, errors } = await openApp(inst, { lang: 'en', dark });
async function shot(name) {
  await page.waitForTimeout(700);
  const png = await capture(page, dir, name);
  scan(name, await page.locator('body').ariaSnapshot());
  return png;
}
const failures = [];
async function step(name, run) {
  try {
    await run();
  } catch (error) {
    failures.push(`${name}: ${error.message.split('\n')[0]}`);
    log(`FAIL step ${name}: ${error.message.split('\n')[0]}`);
    await capture(page, dir, `99-${name}`).catch(() => {});
  }
}
const button = (name, exact = true) => page.getByRole('button', { name, exact });
async function go(path, ready) {
  await page.goto(path);
  await ready.waitFor({ timeout: 30_000 });
}

try {
  await step('signed-out', async () => {
    const out = await openApp(inst, { lang: 'en', dark });
    try {
      await out.page.goto('/start');
      await out.page.getByRole('button', { name: L('startLogIn') }).waitFor({ timeout: 30_000 });
      await out.page.waitForTimeout(700);
      await capture(out.page, dir, '00-start');
      scan('00-start', await out.page.locator('body').ariaSnapshot());
      await out.page.getByRole('button', { name: L('startLogIn') }).click();
      await out.page.getByRole('textbox', { name: L('email') }).or(out.page.getByRole('button', { name: L('continueWithEmail') })).first().waitFor({ timeout: 30_000 });
      await out.page.waitForTimeout(700);
      await capture(out.page, dir, '00-login');
      scan('00-login', await out.page.locator('body').ariaSnapshot());
    } finally {
      await out.browser.close();
    }
  });

  await signIn(page, L, user);
  await step('list', () => shot('01-list'));

  await step('add-sheet', async () => {
    await addField(page, L).click();
    await typeInto(addField(page, L), 'Chee');
    await addSheet(page, L).getByRole('button').first().waitFor({ timeout: 10_000 });
    await shot('02-add-sheet');
    await page.keyboard.press('Escape');
    await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  });

  await step('household-sheet', async () => {
    await button('Brandt family').first().click();
    await page.getByRole('heading', { name: L('householdsTitle') }).waitFor({ timeout: 10_000 });
    await shot('03-household-sheet');
    await page.keyboard.press('Escape');
  });

  await step('household-page', async () => {
    await go('/more/household', page.getByText(L('householdMembersTitle'), { exact: true }).first());
    await shot('04-household-members');
  });

  await step('invite', async () => {
    await go('/more/invites', page.getByRole('heading').first());
    await shot('05-invites');
    await button(L('newInvite')).click();
    await page.getByText(/\/join\//).first().or(page.getByRole('button', { name: L('share') })).first().waitFor({ timeout: 15_000 });
    await shot('05-invite-sheet');
  });

  await step('stores', async () => {
    await go('/edit', page.getByRole('heading').first());
    await shot('06-stores');
  });

  await step('trip-mode', async () => {
    await go('/', addField(page, L));
    const row = itemRow(page, 'Bananas');
    await row.click();
    await button(L('shopAskYes')).waitFor({ timeout: 10_000 });
    await shot('07-trip-question');
    await button(L('shopAskYes')).click();
    await button(L('shopEnd')).waitFor({ timeout: 10_000 });
    await itemRow(page, 'Milk').click();
    await shot('08-trip-strip');
    await button(L('shopEnd')).click();
    await page.getByText(L('shopSummaryTitle')).first().waitFor({ timeout: 15_000 });
    await shot('09-trip-summary');
    await button(L('done')).click();
    await addField(page, L).waitFor({ timeout: 15_000 });
  });

  await step('history', async () => {
    await go('/history', page.getByRole('tab', { name: L('tabHistory'), exact: true }));
    await shot('10-history');
  });

  await step('more', async () => {
    await go('/more', page.getByRole('heading', { name: L('tabMore'), exact: true }));
    await shot('11-more');
    await page.mouse.move(195, 400);
    await page.mouse.wheel(0, 2000);
    await shot('12-more-bottom');
  });

  await step('settings', async () => {
    await go('/more/settings', page.getByRole('heading').first());
    await shot('13-settings');
    await go('/more/settings/language', page.getByRole('heading').first());
    await shot('14-language');
  });

  await step('premium', async () => {
    await go('/more/lifetime', page.getByText(L('premiumTitle')).first());
    await shot('15-premium');
    await page.mouse.move(195, 400);
    await page.mouse.wheel(0, 2000);
    await shot('16-premium-bottom');
  });

  await step('account', async () => {
    await go('/more/account', page.getByRole('heading').first());
    await shot('17-account');
    await button(L('accountDelete')).click();
    await page.getByRole('dialog').or(page.getByRole('alertdialog')).first().waitFor({ timeout: 10_000 });
    await shot('18-account-delete');
    await button(L('cancel')).click();
  });

  await step('feedback', async () => {
    await go('/more', page.getByRole('heading', { name: L('tabMore'), exact: true }));
    await button(L('feedbackRow')).click();
    await page.getByRole('textbox').first().waitFor({ timeout: 10_000 });
    await shot('18b-feedback');
    await page.keyboard.press('Escape');
  });

  await step('access', async () => {
    await go('/more/access', page.getByRole('heading').first());
    await shot('19-access');
  });

  await step('tips', async () => {
    await go('/more/tips', page.getByRole('heading').first());
    await shot('20-tips');
  });

  await step('usage-data', async () => {
    await go('/more/usage-data', page.getByRole('heading').first());
    await shot('21-usage-data');
  });

  await step('new-household', async () => {
    await go('/households/new', page.getByRole('heading').first());
    await shot('22-new-household');
    await page.mouse.move(195, 400);
    await page.mouse.wheel(0, 2000);
    await shot('23-new-household-stores');
  });

  await step('join', async () => {
    await go('/join', page.getByRole('textbox').first());
    await shot('24-join');
  });

  if (errors.length) failures.push(`page errors: ${errors.join('; ')}`);
} finally {
  await browser.close();
}
log(`screens with German: ${findings.length}`);
for (const f of findings) log(`  ${f.name}: ${f.hits.join(', ')}`);
if (failures.length || findings.length) {
  log(`FAIL: ${[...failures, ...findings.map((f) => `German on ${f.name}`)].join('; ')}`);
  process.exit(1);
}
log('PASS');
