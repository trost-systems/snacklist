// Feature account-deletion, sub-feature acct-entry (job 80): the Konto page shows the email as
// plain text with a copy button. Proves the button's accessible name, the clipboard content and
// the „Kopiert“ snackbar. With --dialog it opens „Konto löschen“ instead (sub-feature
// acct-premium, job 104) and proves the Premium tick box is there (premium) or not (none); it
// cancels, so nothing is deleted. Since job 392 the card shows for the account's own Premium only,
// with „Abo verwalten“ while the account's yearly plan renews. Export and deletion: e2e/tests/account-*.spec.ts.
//
//   node journeys/account-deletion.mjs <evidence dir> [--lang de|en] [--dialog premium|none]
import process from 'node:process';
import { capture, instance, logger, member, openApp, openTab, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dialog = rest.includes('--dialog') ? rest[rest.indexOf('--dialog') + 1] : null;
if (!dir) throw new Error('usage: account-deletion.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, context, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: inst.webUrl });
let failed = null;
try {
  await signIn(page, L, user);
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${L('account')}`) }).first().click();
  if (dialog) {
    await page.getByRole('button', { name: L('accountDelete'), exact: true }).click();
    const box = page.getByRole('checkbox', { name: L('accountDeletePremiumAck') });
    const field = page.getByRole('textbox', { name: L('accountDeleteConfirmLabel') });
    // A household with a yearly plan hears first that the billing goes on (H-85).
    const billing = page.getByRole('button', { name: L('premiumContinueAnyway'), exact: true });
    await field.or(billing).first().waitFor({ timeout: 15_000 });
    if (await billing.isVisible()) {
      log('billing notice shown first; „Trotzdem fortfahren“');
      await billing.click();
    }
    await field.waitFor({ timeout: 15_000 });
    const shown = await box.isVisible();
    log(`deletion dialog for ${user.handle}: Premium tick box ${shown ? 'shown' : 'not shown'}`);
    if (shown) {
      // The card's text and buttons reach the screen reader as one group (job 392, Legal N-362).
      await page.getByRole('group', { name: L('accountDeletePremium') }).waitFor({ timeout: 5_000 });
      const manage = await page.getByRole('button', { name: L('premiumManageSubscription'), exact: true }).isVisible();
      log(`card text accountDeletePremium shown; „${L('premiumManageSubscription')}“ ${manage ? 'shown' : 'not shown'}`);
    }
    await capture(page, dir, `01-delete-dialog-${dialog}`);
    await page.getByRole('button', { name: L('cancel'), exact: true }).click();
    if (shown !== (dialog === 'premium')) throw new Error(`expected the Premium warning to be ${dialog === 'premium' ? 'shown' : 'absent'}`);
  } else {
  const copy = page.getByRole('button', { name: L('copyEmail') });
  await copy.waitFor({ timeout: 15_000 });
  await capture(page, dir, '01-account');
  await copy.click();
  await page.getByText(L('copied'), { exact: true }).first().waitFor({ timeout: 5_000 });
  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  log(`copied: ${clipboard === user.email ? 'the member\'s email' : JSON.stringify(clipboard)}`);
  if (clipboard !== user.email) throw new Error('the clipboard does not hold the email');
  await capture(page, dir, '02-copied');
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await context.close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS account-deletion (evidence: ${dir})`);
