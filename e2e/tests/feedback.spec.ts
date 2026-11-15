import { expect, type Page, test } from './fixtures';
import {
  addItem,
  adminClient,
  apiAs,
  type Collector,
  expectOnlyNoConsentFlags,
  fakeCollector,
  firstOf,
  must,
  newEmail,
  openTab,
  screenshot,
  signUp,
  signUpWithHousehold,
  typeInto, createHousehold, skipInvite,
  openEmailSignIn,
} from './helpers';

// Job 21: in-app feedback (docs/FEEDBACK.md). More -> "Feedback senden" -> a note with the app's
// context, insert-only into public.feedback; read back here with the service role, as Peter does.

const phone = { width: 390, height: 844 };

const messageField = (page: Page, label = 'Deine Nachricht') => page.getByRole('textbox', { name: label });
const sendButton = (page: Page, label = 'Senden') => page.getByRole('button', { name: label, exact: true });
const retryButton = (page: Page, label = 'Erneut senden') => page.getByRole('button', { name: label, exact: true });
/** The snackbar's text in the semantics tree, not the screen-reader announcement that repeats it. */
const thanks = (page: Page, text = 'Danke!') =>
  page.locator('[id^="flt-semantic-node-"]').getByText(text, { exact: true }).first();
const failedText = 'Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.';

type Row = Record<string, unknown> & { message: string; screen: string | null; household_id: string | null };

async function userIdOf(email: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).auth.getUser();
  if (error) throw error;
  return data.user.id;
}

/** The user's notes, read with the service role as Peter does in the dashboard. */
async function rowsOf(userId: string): Promise<Row[]> {
  const { data, error } = await adminClient().from('feedback').select('*').eq('user_id', userId).order('created_at');
  if (error) throw error;
  return data as Row[];
}

/** Opens More from wherever the user is and taps "Feedback senden" (the row's label may vary). */
async function openFeedback(page: Page, row = 'Feedback senden', more = 'Mehr', shot: string | undefined = undefined) {
  await openTab(page, more as 'Mehr');
  await expect(page).toHaveURL(/\/more$/);
  const entry = page.getByRole('button', { name: new RegExp(`^${row}( |$)`) });
  await entry.scrollIntoViewIfNeeded();
  if (shot) await screenshot(page, shot);
  await entry.click();
  await expect(page.getByRole('group', { name: row, exact: true })).toBeVisible();
}

test('a note from More after the list: one row, no screen, the context, no list data (AC1-3, 6, 8, 9, 11)', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  const email = newEmail('feedback');
  await signUpWithHousehold(page, email);
  // AC9: a household with items whose names must not appear anywhere but in the message.
  await addItem(page, 'Hafermilch');
  await addItem(page, 'Zimtschnecken');
  await addItem(page, 'Geheimzutat Kardamom');

  await openFeedback(page, 'Feedback senden', 'Mehr', 'job21-more-entry-de');
  await expect(page.getByText('App-Version, Gerät und Sprache. Keine Listeneinträge.', { exact: false }))
    .toBeVisible();
  await expect(sendButton(page)).toBeDisabled();
  await screenshot(page, 'job21-form-empty-de');
  await typeInto(messageField(page), 'Beim Abhaken springt die Liste nach oben.');
  await screenshot(page, 'job21-form-filled-de');
  const sentAt = Date.now();
  await sendButton(page).click();
  await expect(thanks(page)).toBeVisible();
  await expect(page.getByRole('group', { name: 'Feedback senden', exact: true })).toHaveCount(0);
  await screenshot(page, 'job21-thanks-de');

  // AC6: the service role sees it within a minute.
  const userId = await userIdOf(email);
  await expect.poll(async () => (await rowsOf(userId)).length, { timeout: 60_000 }).toBe(1);
  expect(Date.now() - sentAt).toBeLessThan(60_000);
  const row = firstOf(await rowsOf(userId), 'feedback row');
  const { data: member } = await adminClient().from('household_members').select('household_id').eq('user_id', userId)
    .single();
  expect(row).toMatchObject({
    user_id: userId,
    household_id: must(member, 'membership').household_id,
    message: 'Beim Abhaken springt die Liste nach oben.',
    category: null,
    contact_ok: false,
    platform: 'web',
    locale: 'de',
    screen: null,
    // AC11: an @example.test account is a test account.
    is_internal: true,
  });
  for (const field of ['app_version', 'build', 'os_version']) {
    expect(String(row[field]).length, field).toBeGreaterThan(0);
  }
  expect(row.os_version).toMatch(/^Chrome on (Linux|macOS|Windows)$/);
  // AC9: no item name or list text in any column but the message.
  const { message: _, ...rest } = row;
  const scanned = JSON.stringify(rest);
  for (const listText of ['Hafermilch', 'Zimtschnecken', 'Geheimzutat', 'Kardamom', 'Abhaken']) {
    expect(scanned, listText).not.toContain(listText);
  }

  // AC8, declined consent (signUp declines): no event, the row is saved anyway.
  await page.waitForTimeout(7_000);
  expectOnlyNoConsentFlags(collector, 'declined: no event');
  await context.close();
});

test('with analytics consent: one feedback_submitted, without the text (AC8)', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const collector: Collector = await fakeCollector(context);
  const page = await context.newPage();
  const email = newEmail('feedback-consent');
  await signUp(page, email, '/', { consent: 'accept' });
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Hafermilch');
  await openFeedback(page);
  await typeInto(messageField(page), 'Idee: Hafermilch als Favorit merken');
  await page.getByRole('checkbox', { name: 'Idee', exact: true }).click();
  await page.getByRole('checkbox', { name: 'Snacklist Support darf mich dazu kontaktieren' }).click();
  await sendButton(page).click();
  await expect(thanks(page)).toBeVisible();

  const userId = await userIdOf(email);
  await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
  expect((await rowsOf(userId))[0]).toMatchObject({ category: 'idea', contact_ok: true });
  const submitted = () => collector.events.filter((e) => e.event === 'feedback_submitted');
  await expect.poll(() => submitted().length, { timeout: 20_000 }).toBe(1);
  // A later flush sends nothing more for it.
  await page.waitForTimeout(7_000);
  expect(submitted()).toHaveLength(1);
  const event = firstOf(submitted(), 'feedback_submitted event');
  expect(event.properties).toMatchObject({
    category: 'idea',
    entry_point: 'settings',
    contact_ok: true,
    is_internal: true,
  });
  const everything = JSON.stringify(collector.events);
  for (const text of ['Favorit', 'Hafermilch', 'Idee:', email]) {
    expect(everything, text).not.toContain(text);
  }
  expect(collector.leaks).toEqual([]);
  await context.close();
});

test('a double tap on Send stores one row', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const page = await context.newPage();
  const email = newEmail('feedback-double');
  await signUpWithHousehold(page, email);
  let posts = 0;
  // A slow answer leaves time for the second tap.
  await page.route('**/rest/v1/feedback*', async (route) => {
    if (route.request().method() === 'POST') posts++;
    await new Promise((resolve) => setTimeout(resolve, 1_500));
    await route.continue();
  });
  await openFeedback(page);
  await typeInto(messageField(page), 'Doppelt getippt');
  await sendButton(page).dblclick();
  await expect(thanks(page)).toBeVisible();
  expect(posts, 'one request').toBe(1);
  const userId = await userIdOf(email);
  await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
  await context.close();
});

test('offline: an error, the note stays, Retry works once online, one row (AC7)', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const page = await context.newPage();
  const email = newEmail('feedback-offline');
  await signUpWithHousehold(page, email);
  const userId = await userIdOf(email);
  await openFeedback(page);
  await typeInto(messageField(page), 'Im Keller ohne Netz geschrieben');
  await page.getByRole('checkbox', { name: 'Bug', exact: true }).click();
  await context.setOffline(true);
  await sendButton(page).click();
  await expect(page.getByText(failedText).first()).toBeVisible();
  await expect(messageField(page)).toHaveValue('Im Keller ohne Netz geschrieben');
  await expect(retryButton(page)).toBeEnabled();
  await screenshot(page, 'job21-offline-retry-de');
  expect(await rowsOf(userId), 'nothing while offline').toEqual([]);

  await context.setOffline(false);
  await retryButton(page).click();
  await expect(thanks(page)).toBeVisible();
  await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
  expect((await rowsOf(userId))[0]).toMatchObject({ message: 'Im Keller ohne Netz geschrieben', category: 'bug' });
  // Nothing is sent again later.
  await page.waitForTimeout(5_000);
  expect(await rowsOf(userId)).toHaveLength(1);
  await context.close();
});

test('a lost answer: Retry sends the same note again, still one row', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const page = await context.newPage();
  const email = newEmail('feedback-lost');
  await signUpWithHousehold(page, email);
  const userId = await userIdOf(email);
  let first = true;
  await page.route('**/rest/v1/feedback*', async (route) => {
    if (first && route.request().method() === 'POST') {
      first = false;
      // The server stores the note; its answer never reaches the app.
      await route.fetch();
      await route.abort('connectionreset');
      return;
    }
    await route.continue();
  });
  await openFeedback(page);
  await typeInto(messageField(page), 'Die Antwort ging verloren');
  await sendButton(page).click();
  await expect(page.getByText(failedText).first()).toBeVisible();
  expect(await rowsOf(userId), 'the server has it already').toHaveLength(1);
  await retryButton(page).click();
  await expect(thanks(page)).toBeVisible();
  expect(await rowsOf(userId)).toHaveLength(1);
  await context.close();
});

test('length limits in the app and in the database (AC4)', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  const page = await context.newPage();
  const email = newEmail('feedback-limits');
  await signUpWithHousehold(page, email);
  await openFeedback(page);
  await typeInto(messageField(page), '      ');
  await expect(sendButton(page), 'only spaces').toBeDisabled();
  await typeInto(messageField(page), 'a'.repeat(2001));
  await expect(page.getByText('Höchstens 2000 Zeichen')).toBeVisible();
  await expect(page.getByText('2001 / 2000')).toBeVisible();
  await expect(sendButton(page), 'too long').toBeDisabled();
  await typeInto(messageField(page), `${'a'.repeat(2000)}  `);
  await expect(page.getByText('2000 / 2000')).toBeVisible();
  await expect(sendButton(page), '2000 after trimming').toBeEnabled();

  // The database refuses the same, whatever a client sends.
  const api = await apiAs(email);
  const note = (message: string) => ({
    id: crypto.randomUUID(),
    message,
    app_version: '0.1.0',
    build: '1',
    platform: 'web',
    os_version: 'Chrome on Linux',
    locale: 'de',
    screen: 'more',
  });
  for (const [message, why] of [['', 'empty'], ['     ', 'spaces'], ['a'.repeat(2001), '2001 characters']] as const) {
    const { error } = await api.from('feedback').insert(note(message));
    expect(error?.code, why).toBe('23514');
  }
  const { error } = await api.from('feedback').insert(note(` ${'a'.repeat(2000)} `));
  expect(error, '2000 characters').toBeNull();
  await context.close();
});

test.describe('in English', () => {
  test.use({ locale: 'en-US' });

  test('the row, the form, the error and the thanks are English (AC1, AC10)', async ({ browser }) => {
    const context = await browser.newContext({ viewport: phone, locale: 'en-US' });
    const page = await context.newPage();
    const email = newEmail('feedback-en');
    await page.goto('/login');
    await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
    await typeInto(page.getByRole('textbox', { name: 'Email' }), email);
    await typeInto(page.getByRole('textbox', { name: 'Password' }), 'test-password-123');
    await page.getByRole('button', { name: 'Sign up' }).click();
    await page.getByRole('button', { name: "Don't allow", exact: true }).click();
    await createHousehold(page, { lang: 'en' });
    await page.getByRole('button', { name: 'Later', exact: true }).click();
    await expect(page.getByRole('textbox', { name: 'What do you need?' })).toBeFocused();

    await openFeedback(page, 'Send feedback', 'More', 'job21-more-entry-en');
    for (const text of ['Bug', 'Idea', 'Other']) {
      await expect(page.getByRole('checkbox', { name: text, exact: true })).toBeVisible();
    }
    await expect(page.getByRole('checkbox', { name: 'Snacklist Support may contact me about this' })).toBeVisible();
    await expect(page.getByText('App version, device and language. No list items.', { exact: false }))
      .toBeVisible();
    await typeInto(messageField(page, 'Your message'), 'The list jumps when I tick an item.');
    await screenshot(page, 'job21-form-filled-en');
    await context.setOffline(true);
    await sendButton(page, 'Send').click();
    await expect(page.getByText('Not sent. Check your connection and try again.').first()).toBeVisible();
    await screenshot(page, 'job21-offline-retry-en');
    await context.setOffline(false);
    await retryButton(page, 'Retry').click();
    await expect(thanks(page, 'Thanks!')).toBeVisible();
    await screenshot(page, 'job21-thanks-en');
    const userId = await userIdOf(email);
    await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
    expect((await rowsOf(userId))[0]).toMatchObject({ locale: 'en', screen: null });
    await context.close();
  });
});

test('wide: feedback beside an open More page sends no screen (1366x1024)', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 1366, height: 1024 } });
  const page = await context.newPage();
  const email = newEmail('feedback-wide');
  await signUpWithHousehold(page, email);
  await openTab(page, 'Mehr');
  await page.getByRole('button', { name: 'Konto', exact: true }).click();
  await expect(page).toHaveURL(/\/more\/account$/);
  const entry = page.getByRole('button', { name: /^Feedback senden( |$)/ });
  await entry.scrollIntoViewIfNeeded();
  await screenshot(page, 'job21-wide-more');
  await entry.click();
  await typeInto(messageField(page), 'Breites Fenster');
  await screenshot(page, 'job21-wide-form');
  await sendButton(page).click();
  await expect(thanks(page)).toBeVisible();
  const userId = await userIdOf(email);
  await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
  expect(firstOf(await rowsOf(userId), 'feedback row').screen).toBeNull();
  await context.close();
});

// Job 267 (flag feedback-fb2): from More the screen before More can be marked up and sent along; it
// lands in the private bucket under the sender's folder, and the row names it.
test('flag on: a screenshot from More is marked up, uploaded and named by the row', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  await fakeCollector(context, { flags: { 'feedback-fb2': true } });
  const page = await context.newPage();
  const email = newEmail('feedback-shot');
  await signUp(page, email, '/', { consent: 'accept' });
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Hafermilch');
  await openFeedback(page);
  await expect(page.getByText('Bildschirmname', { exact: true }), 'More sends no screen name').toHaveCount(0);
  await page.getByRole('button', { name: 'Bildschirmfoto hinzufügen' }).click();
  const done = page.getByRole('button', { name: 'Fertig', exact: true });
  await expect(done).toBeVisible();
  // A pen stroke across the frozen screen.
  await page.mouse.move(80, 200);
  await page.mouse.down();
  for (const x of [110, 140, 170, 200]) await page.mouse.move(x, 210, { steps: 3 });
  await page.mouse.up();
  await screenshot(page, 'job267-annotator-web-de');
  await done.click();
  await expect(page.getByRole('img', { name: 'Vorschau des Bildschirmfotos' })).toBeVisible({ timeout: 15_000 });
  await typeInto(messageField(page), 'Mit Bildschirmfoto aus dem Menü');
  await screenshot(page, 'job267-form-with-screenshot-web-de');
  await sendButton(page).click();
  await expect(thanks(page)).toBeVisible({ timeout: 15_000 });

  const userId = await userIdOf(email);
  await expect.poll(async () => (await rowsOf(userId)).length).toBe(1);
  const row = firstOf(await rowsOf(userId), 'feedback row');
  expect(row.screen).toBeNull();
  expect(row.screenshot).toBe(`${userId}/${String(row.id)}.png`);
  const { data, error } = await adminClient().storage.from('feedback-screenshots').download(String(row.screenshot));
  if (error) throw error;
  const bytes = new Uint8Array(await data.arrayBuffer());
  expect([...bytes.slice(0, 4)], 'a PNG').toEqual([0x89, 0x50, 0x4e, 0x47]);
  await context.close();
});
