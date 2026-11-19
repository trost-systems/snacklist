// Feature report-content, sub-feature rc-app (job 281, flag report-content-entry): More's feedback
// row with „Auch: Inhalte melden“, „Inhalt melden“ in Feedback & Ideen (--fb4, launched with
// VH_DEFINES="FLAGS_ON=report-content-entry,feedback-fb4") or on top of the feedback sheet
// (without --fb4, launched with VH_DEFINES="FLAGS_ON=report-content-entry"), the form's errors,
// an item picked in the picker, the prefilled e-mail, the send through /functions/v1/report/app
// and the number on the confirmation; Fertig goes back where it started. The stored row is read
// by the caller (journey.log prints the number).
//
//   node journeys/report-content.mjs <evidence dir> [--lang de|en] [--fb4] [--screenshot] [--csam] [--clear] [--item <name>]
import process from 'node:process';
import { capture, instance, logger, member, openApp, openTab, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'de');
const fb4 = rest.includes('--fb4');
// The seeded household's language, not the UI's: demo-familie holds „Bananen“ in either.
const item = arg('--item', instance().scenario === 'demo-family-en' ? 'Bananas' : 'Bananen');
// With feedback-fb2 on: attach the screen before More, covered with the cover tool.
const shot = rest.includes('--screenshot');
// Switch to child sexual abuse material after the prefill check: the contact hides and empties.
const csam = rest.includes('--csam');
// Clear the prefilled e-mail, then pick another kind: it must stay empty and not go.
const clear = rest.includes('--clear');
if (!dir) throw new Error('usage: report-content.mjs <evidence dir> [--lang de|en] [--fb4]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, context, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  await openTab(page, L, 'tabMore');
  const also = page.getByText(L('reportEntryAlso'));
  await also.first().waitFor({ timeout: 15_000 });
  await capture(page, dir, '01-more');
  log(`More shows „${L('reportEntryAlso')}“ under ${fb4 ? L('feedbackHubRow') : L('feedbackRow')}`);
  await page.getByRole('button', { name: new RegExp(`^${fb4 ? L('feedbackHubRow') : L('feedbackRow')}`) }).first().click();
  const entry = page.getByRole('button', { name: L('reportContent'), exact: true });
  await entry.waitFor({ timeout: 15_000 });
  await capture(page, dir, fb4 ? '02-hub' : '02-sheet');
  await entry.click();

  const send = page.getByRole('button', { name: L('reportSend'), exact: true });
  await page.getByText(L('reportIntro')).first().waitFor({ timeout: 15_000 });
  await capture(page, dir, '03-form');
  await reveal(page, send);
  await send.click();
  await page.getByText(L('reportErrorAbout')).first().waitFor({ timeout: 5_000 });
  await capture(page, dir, '04-errors');
  log('Send on an empty form names what is missing');

  await page.getByRole('radio', { name: L('reportCategoryHate') }).click();
  const choose = page.getByRole('button', { name: L('reportWhereChoose') });
  await reveal(page, choose);
  await choose.click();
  const search = page.getByRole('textbox', { name: L('reportPickerSearch') });
  await search.waitFor({ timeout: 10_000 });
  await capture(page, dir, '05-picker');
  await typeInto(search, item.slice(0, 3));
  await page.getByRole('button', { name: new RegExp(`^${item}`) }).first().click();
  await page.getByText(L('reportWhereHelp')).first().waitFor({ timeout: 5_000 });

  const reason = page.getByRole('textbox', { name: new RegExp(L('reportWhy')) });
  await reveal(page, reason);
  await typeInto(reason, lang === 'de'
    ? 'Dieser Eintrag ist ein Test der Meldung aus der App, keine echte Meldung.'
    : 'This item is a test of reporting from the app, not a real report.');
  const email = page.getByRole('textbox', { name: new RegExp(L('reportEmail')) });
  await reveal(page, email);
  // Flutter web puts an <input> with its value only under the focused field.
  await email.click();
  let prefilled = '';
  for (let i = 0; i < 20 && !prefilled; i++) {
    await page.waitForTimeout(100);
    prefilled = await page.evaluate(() => document.activeElement?.value ?? '');
  }
  log(`e-mail field prefilled: ${prefilled === user.email ? "the member's address" : JSON.stringify(prefilled)}`);
  if (prefilled !== user.email) throw new Error('the e-mail is not prefilled');
  if (clear) {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Delete');
    const kind = page.getByRole('radio', { name: L('reportCategoryDanger') });
    await reveal(page, kind);
    await kind.click();
    await reveal(page, email);
    await email.click();
    await page.waitForTimeout(500);
    const after = await page.evaluate(() => document.activeElement?.value ?? null);
    log(`cleared the e-mail, picked „${L('reportCategoryDanger')}“: the field holds ${JSON.stringify(after)}`);
    if (after !== '') throw new Error('the cleared e-mail came back after another kind');
    await capture(page, dir, '06d-cleared-after-repick');
  }
  if (csam) {
    const kind = page.getByRole('radio', { name: L('reportCategoryCsam') });
    await reveal(page, kind);
    await kind.click();
    const add = page.getByRole('button', { name: L('reportCsamAdd') });
    await add.waitFor({ timeout: 5_000 });
    if (await email.count()) throw new Error('the e-mail field still shows under CSAM');
    await capture(page, dir, '06b-csam-hidden');
    await reveal(page, add);
    await add.click();
    await reveal(page, email);
    await email.click();
    await page.waitForTimeout(500);
    const shown = await page.evaluate(() => document.activeElement?.value ?? null);
    log(`CSAM: fields hidden; after „${L('reportCsamAdd')}“ the e-mail field holds ${JSON.stringify(shown)}`);
    if (shown !== '') throw new Error('the e-mail field is not empty after adding it under CSAM');
    await capture(page, dir, '06c-csam-added-empty');
  }
  if (shot) {
    const attach = page.getByRole('button', { name: L('reportScreenshot') });
    await reveal(page, attach);
    await attach.click();
    const done = page.getByRole('button', { name: L('feedbackAnnotateDone'), exact: true });
    await done.waitFor({ timeout: 15_000 });
    // BetterFeedback animates its frame in after Fertig shows (feedback.spec.ts).
    await page.waitForTimeout(1500);
    const cover = page.getByRole('radio', { name: L('feedbackToolCover'), exact: true });
    await cover.click();
    await page.mouse.move(60, 150);
    await page.mouse.down();
    for (const [x, y] of [[120, 200], [200, 260], [300, 300]]) await page.mouse.move(x, y, { steps: 4 });
    await page.mouse.up();
    await capture(page, dir, '06a-annotator-cover');
    await done.click();
    await page.getByText(L('reportScreenshotAttached')).first().waitFor({ timeout: 15_000 });
    log('screenshot attached through the annotator with a cover');
  }
  const good = page.getByRole('checkbox', { name: new RegExp(L('reportGoodFaith').slice(0, 30)) });
  await reveal(page, good);
  await good.click();
  await capture(page, dir, '06-filled');
  await reveal(page, send);
  await send.click();

  await page.getByText(L('reportSentTitle')).first().waitFor({ timeout: 20_000 });
  const body = await page.locator('flt-semantics-host, body').first().innerText().catch(() => '');
  const ref = /M-[0-9A-Z]{4}-[0-9A-Z]{4}/.exec(body)?.[0]
    ?? /M-[0-9A-Z]{4}-[0-9A-Z]{4}/.exec(await page.content())?.[0];
  if (!ref) throw new Error('no number on the confirmation');
  log(`sent: number ${ref}`);
  if ((csam || clear) && !(await page.getByText(L('reportNotMailed')).count())) throw new Error('the no-mail line is missing');
  await capture(page, dir, '07-sent');
  await page.getByRole('button', { name: L('reportDone'), exact: true }).click();
  await (fb4 ? entry : also.first()).waitFor({ timeout: 10_000 });
  await capture(page, dir, '08-back');
  log(`Fertig went back to ${fb4 ? 'the hub' : 'More'}`);
  console.log(`REF ${ref}`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await context.close();
  await browser.close();
}
if (failed) {
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
console.log('PASS');
