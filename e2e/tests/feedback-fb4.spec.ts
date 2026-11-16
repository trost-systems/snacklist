import { expect, type Page, test } from './fixtures';
import {
  adminClient,
  apiAs,
  fakeCollector,
  firstOf,
  must,
  newEmail,
  openTab,
  screenshot,
  signUpWithHousehold,
  typeInto,
  wheelTo,
} from './helpers';

// Job 268 (flag feedback-fb4): More's Feedback & Ideen. The user's notes with the status and reply
// Peter sets by hand in the dashboard (the service role here), and the listed ideas a household +1s.

const phone = { width: 390, height: 844 };
const flagOn = { flags: { 'feedback-fb4': true } };

type Note = { id: string; status: string; 'seen_at': string | null; 'answered_at': string | null };

async function userIdOf(email: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).auth.getUser();
  if (error) throw error;
  return data.user.id;
}

async function householdOf(userId: string): Promise<string> {
  const { data, error } = await adminClient().from('household_members').select('household_id').eq('user_id', userId)
    .single();
  if (error) throw error;
  return must(data, 'membership').household_id as string;
}

async function notesOf(userId: string): Promise<Note[]> {
  const { data, error } = await adminClient().from('feedback').select('id, status, seen_at, answered_at')
    .eq('user_id', userId).order('created_at');
  if (error) throw error;
  return data as Note[];
}

/** More's list, from wherever the user is: the tab returns to the page it was left on. */
async function openMoreList(page: Page): Promise<void> {
  await openTab(page, 'Mehr');
  await expect(page).toHaveURL(/\/more\b/);
  if (new URL(page.url()).pathname !== '/more') await openTab(page, 'Mehr');
  await expect(page).toHaveURL(/\/more$/);
}

const hubRow = (page: Page) => page.getByRole('button', { name: /^Feedback & Ideen( |,|$)/ });
const writeButton = (page: Page) => page.getByRole('button', { name: 'An Snacklist Support schreiben' });
const noteCard = (page: Page, message: string) => page.getByRole('button', { name: new RegExp(escape(message)) });
/** The +1 of [title]: its name carries the count ("<title>: +1, 2 Stimmen"). */
const voteButton = (page: Page, title: string) =>
  page.getByRole('button', { name: new RegExp(`^${escape(title)}: \\+1, `) })
    .or(page.getByRole('switch', { name: new RegExp(`^${escape(title)}: \\+1, `) }))
    .or(page.getByRole('checkbox', { name: new RegExp(`^${escape(title)}: \\+1, `) }));

function escape(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Every word the page shows or names for a screen reader: semantics text and labels. */
async function shownWords(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host');
    if (host === null) return '';
    const labels = [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label') ?? '');
    return [host.textContent ?? '', ...labels].join('\n');
  });
}

async function expectNoPeter(page: Page, where: string): Promise<void> {
  const words = await shownWords(page);
  expect(words.length, `${where}: the semantics tree has text`).toBeGreaterThan(0);
  expect(words, where).not.toMatch(/Peter/i);
}

/** Whether the +1 shows as given: aria-pressed or aria-checked, whichever role the web gives it. */
async function pressed(target: ReturnType<typeof voteButton>): Promise<boolean> {
  const state = (await target.getAttribute('aria-pressed')) ?? (await target.getAttribute('aria-checked'));
  return state === 'true';
}

test('flag off: More keeps "Feedback senden" and /more/feedback lands on More', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  await fakeCollector(context);
  const page = await context.newPage();
  await signUpWithHousehold(page, newEmail('fb4-off'));
  await openMoreList(page);
  const sendRow = page.getByRole('button', { name: /^Feedback senden( |$)/ });
  await wheelTo(page, sendRow);
  await expect(sendRow).toBeVisible();
  await expect(hubRow(page)).toHaveCount(0);
  await page.goto('/more/feedback');
  await expect(page).toHaveURL(/\/more$/);
  await expect(writeButton(page)).toHaveCount(0);
  await context.close();
});

test('a note, its status, Snacklist Support\'s reply and the badge until it is opened', async ({ browser }) => {
  const context = await browser.newContext({ viewport: phone });
  await fakeCollector(context, flagOn);
  const page = await context.newPage();
  const email = newEmail('fb4-note');
  await signUpWithHousehold(page, email);
  const userId = await userIdOf(email);

  await openMoreList(page);
  await wheelTo(page, hubRow(page));
  await expect(page.getByRole('button', { name: /^Feedback senden( |$)/ })).toHaveCount(0);
  await hubRow(page).click();
  await expect(page).toHaveURL(/\/more\/feedback$/);
  await expect(page.getByText('Noch keine Notizen.', { exact: false }).first()).toBeVisible();
  await expectNoPeter(page, 'empty hub');

  await writeButton(page).click();
  const message = 'Die Suche findet Hafermilch nicht';
  await typeInto(page.getByRole('textbox', { name: 'Deine Nachricht' }), message);
  await screenshot(page, 'job268-compose-de');
  await expectNoPeter(page, 'compose');
  await page.getByRole('button', { name: 'Senden', exact: true }).click();
  await expect(page.getByRole('group', { name: 'Feedback senden', exact: true })).toHaveCount(0);
  await expect(noteCard(page, message)).toBeVisible();
  await expect(noteCard(page, message)).toHaveAccessibleName(/Gesendet/);
  await screenshot(page, 'job268-hub-sent-de');
  await expectNoPeter(page, 'hub with a note');

  await expect.poll(async () => (await notesOf(userId)).length).toBe(1);
  const note = firstOf(await notesOf(userId), 'feedback row');
  expect(note).toMatchObject({ status: 'sent', seen_at: null, answered_at: null });

  // Peter answers in the Table Editor: status, version and reply; the trigger stamps the rest.
  const { error } = await adminClient().from('feedback')
    .update({ status: 'fixed', fixed_in: '1.4.1', reply: 'Danke, behoben.' }).eq('id', note.id);
  if (error) throw error;

  await page.reload();
  await openMoreList(page);
  await wheelTo(page, hubRow(page));
  await expect(hubRow(page)).toHaveAccessibleName('Feedback & Ideen, 1 Neuigkeit');
  await screenshot(page, 'job268-more-badge-de');
  await hubRow(page).click();
  const card = noteCard(page, message);
  await expect(card).toHaveAccessibleName(/Behoben in 1\.4\.1/);
  await expect(card).toHaveAccessibleName(/Neue Antwort/);
  await screenshot(page, 'job268-hub-de');

  await card.click();
  await expect(page).toHaveURL(new RegExp(`/more/feedback/${note.id}$`));
  // The web merges the page's texts into one group.
  const thread = page.getByRole('group').filter({ hasText: message });
  await expect(thread).toHaveText(new RegExp(
    `^Behoben in 1\\.4\\.1\\s*${escape(message)}\\s*[^\\n]+ · gelesen\\s*Danke, behoben\\.\\s*Snacklist Support · \\d`,
  ));
  const whatsNew = page.getByRole('link', { name: 'Was ist neu in 1.4.1' });
  await expect(whatsNew).toBeVisible();
  await expect(whatsNew).toHaveAttribute('href', 'https://snacklist.app/de/changelog#v1-4-1');
  await screenshot(page, 'job268-note-reply-de');
  await expectNoPeter(page, 'note with a reply');

  await expect.poll(async () => firstOf(await notesOf(userId), 'feedback row').seen_at).not.toBeNull();
  const seen = firstOf(await notesOf(userId), 'feedback row');
  expect(Date.parse(must(seen.seen_at, 'seen_at'))).toBeGreaterThanOrEqual(Date.parse(must(seen.answered_at, 'answered_at')));

  await openMoreList(page);
  await wheelTo(page, hubRow(page));
  await expect(hubRow(page)).toHaveAccessibleName('Feedback & Ideen');
  await page.reload();
  await openMoreList(page);
  await wheelTo(page, hubRow(page));
  await expect(hubRow(page), 'still read after a reload').toHaveAccessibleName('Feedback & Ideen');
  await context.close();
});

test.describe('ideas', () => {
  const title = `Rezepte teilen ${crypto.randomUUID().slice(0, 6)}`;
  let ideaId: string | undefined;

  test.beforeAll(async () => {
    const { data, error } = await adminClient().from('feedback_ideas')
      .insert({ title_de: title, title_en: `Share recipes ${title.slice(-6)}`, position: -1000 })
      .select('id').single();
    if (error) throw error;
    ideaId = must(data, 'idea').id as string;
  });

  test.afterAll(async () => {
    if (ideaId !== undefined) await adminClient().from('feedback_ideas').delete().eq('id', ideaId);
  });

  test('one +1 per household; nobody reads another\'s notes or votes', async ({ browser }) => {
    const contextA = await browser.newContext({ viewport: phone });
    await fakeCollector(contextA, flagOn);
    const a = await contextA.newPage();
    const emailA = newEmail('fb4-idea-a');
    await signUpWithHousehold(a, emailA);
    const householdA = await householdOf(await userIdOf(emailA));
    // A note of A's, for B to try to read.
    const { error: noteError } = await (await apiAs(emailA)).from('feedback').insert({
      id: crypto.randomUUID(),
      message: 'Notiz von A',
      app_version: '0.1.0',
      build: '1',
      platform: 'web',
      os_version: 'Chrome on Linux',
      locale: 'de',
      screen: null,
    });
    if (noteError) throw noteError;

    await openMoreList(a);
    await wheelTo(a, hubRow(a));
    await hubRow(a).click();
    await expect(a.getByText('Ideen, die wir abwägen', { exact: true })).toBeVisible();
    const voteA = voteButton(a, title);
    await wheelTo(a, voteA);
    await expect(voteA).toHaveAccessibleName(`${title}: +1, 0 Stimmen`);
    expect(await pressed(voteA)).toBe(false);
    await voteA.click();
    await expect(voteA).toHaveAccessibleName(`${title}: +1, 1 Stimme`);
    await expect.poll(() => pressed(voteA)).toBe(true);
    await expect.poll(async () => {
      const { data } = await adminClient().from('feedback_idea_votes').select('household_id').eq('idea_id', must(ideaId, 'idea'));
      return data?.map((v) => v.household_id);
    }).toEqual([householdA]);
    await screenshot(a, 'job268-idea-voted-de');
    await expectNoPeter(a, 'hub with ideas');

    const contextB = await browser.newContext({ viewport: phone });
    await fakeCollector(contextB, flagOn);
    const b = await contextB.newPage();
    const emailB = newEmail('fb4-idea-b');
    await signUpWithHousehold(b, emailB);
    const householdB = await householdOf(await userIdOf(emailB));
    expect(householdB).not.toBe(householdA);
    await openMoreList(b);
    await wheelTo(b, hubRow(b));
    await hubRow(b).click();
    const voteB = voteButton(b, title);
    await wheelTo(b, voteB);
    await expect(voteB).toHaveAccessibleName(`${title}: +1, 1 Stimme`);
    expect(await pressed(voteB)).toBe(false);
    await expect(b.getByText('Notiz von A')).toHaveCount(0);
    await voteB.click();
    await expect(voteB).toHaveAccessibleName(`${title}: +1, 2 Stimmen`);
    await expect.poll(() => pressed(voteB)).toBe(true);

    // A sees B's +1 in the count on the next load, still as A's own +1.
    await a.reload();
    await openMoreList(a);
    await wheelTo(a, hubRow(a));
    await hubRow(a).click();
    await wheelTo(a, voteButton(a, title));
    await expect(voteButton(a, title)).toHaveAccessibleName(`${title}: +1, 2 Stimmen`);
    expect(await pressed(voteButton(a, title))).toBe(true);

    // B through PostgREST: no note of A's, only B's household's vote, no ideas table.
    const apiB = await apiAs(emailB);
    const notes = await apiB.from('feedback').select('id, message');
    expect(notes.error).toBeNull();
    expect(notes.data).toEqual([]);
    const votes = await apiB.from('feedback_idea_votes').select('idea_id, household_id');
    expect(votes.error).toBeNull();
    expect(votes.data).toEqual([{ idea_id: ideaId, household_id: householdB }]);
    const ideas = await apiB.from('feedback_ideas').select('id');
    expect(ideas.error?.code, 'the ideas table is closed to clients').toBe('42501');
    const asOther = await apiB.rpc('feedback_ideas', { p_household: householdA });
    expect(asOther.error?.code, 'ideas for a household B is not in').toBe('42501');
    const voteAsOther = await apiB.rpc('vote_feedback_idea', { p_idea: ideaId, p_household: householdA, p_on: false });
    expect(voteAsOther.error?.code, 'a vote for a household B is not in').toBe('42501');
    const { count } = await adminClient().from('feedback_idea_votes').select('*', { count: 'exact', head: true })
      .eq('idea_id', must(ideaId, 'idea'));
    expect(count).toBe(2);

    await contextA.close();
    await contextB.close();
  });
});
