import { expect, test } from './fixtures';
import { addItem, adminClient, anonClient, apiAs, itemRow, must, newEmail, password, signUpWithHousehold } from './helpers';

test('a user from another household can neither see nor change the list', async ({ browser }) => {
  const peterEmail = newEmail('peter');
  const eveEmail = newEmail('eve');
  const peter = await (await browser.newContext()).newPage();
  const eve = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, peterEmail);
  await addItem(peter, 'Geheimzutat');
  await expect(itemRow(peter, 'Geheimzutat')).toBeVisible();
  await signUpWithHousehold(eve, eveEmail);
  await expect(itemRow(eve, 'Geheimzutat'), 'not in the other household\'s UI').toHaveCount(0);

  const peterApi = await apiAs(peterEmail);
  await expect.poll(async () => (await peterApi.from('items').select('id').eq('name', 'Geheimzutat')).data?.length, {
    message: 'the add reached the server',
  }).toBe(1);
  const { data: own } = await peterApi.from('items').select('id, household_id').eq('name', 'Geheimzutat').single();
  if (own === null) throw new Error('no Geheimzutat row');
  const householdId = own.household_id as string;

  const eveApi = await apiAs(eveEmail);
  const read = await eveApi.from('items').select('*').eq('household_id', householdId);
  expect(read.data, 'reading by household id returns nothing').toEqual([]);
  const categories = await eveApi.from('categories').select('*').eq('household_id', householdId);
  expect(categories.data).toEqual([]);

  const insert = await eveApi.from('items').insert({ household_id: householdId, name: 'Eingeschleust' });
  expect(insert.error?.code, 'insert is denied by RLS').toBe('42501');

  const update = await eveApi.from('items').update({ name: 'Gehackt' }).eq('id', own.id).select();
  expect(update.data).toEqual([]);
  const del = await eveApi.from('items').delete().eq('id', own.id).select();
  expect(del.data).toEqual([]);
  const invite = await eveApi.rpc('create_invite', { p_household: householdId });
  expect(invite.error?.message).toBe('not_a_member');
  const classify = await eveApi.rpc('classify_item', { p_household: householdId, p_name: 'Milch' });
  expect(classify.data, 'classify does not reveal another household\'s category ids').toBeNull();
  expect(classify.error?.message).toBe('not_a_member');

  const { data: after } = await peterApi.from('items').select('name').eq('id', own.id).single();
  expect(must(after, 'Geheimzutat row').name, 'the row is untouched').toBe('Geheimzutat');

  // Realtime: Eve listening on Peter's household receives nothing.
  const received: unknown[] = [];
  const channel = eveApi.channel('spy').on(
    'postgres_changes',
    { event: '*', schema: 'public', table: 'items', filter: `household_id=eq.${householdId}` },
    (payload) => received.push(payload),
  );
  await new Promise<void>((resolve) => channel.subscribe((status) => status === 'SUBSCRIBED' && resolve()));
  await addItem(peter, 'Noch geheimer');
  await expect(itemRow(peter, 'Noch geheimer')).toBeVisible();
  await peter.waitForTimeout(1_500);
  expect(received, 'no realtime events leak across households').toEqual([]);
  await eveApi.removeAllChannels();
});

test('feedback: own note yes, another user_id no, only the sender reads it back, no change or delete, anon nothing (jobs 21 and 268)', async () => {
  const [annaEmail, benEmail] = [newEmail('fb-anna'), newEmail('fb-ben')];
  const admin = adminClient();
  for (const email of [annaEmail, benEmail]) {
    const { error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    expect(error).toBeNull();
  }
  const anna = await apiAs(annaEmail);
  const ben = await apiAs(benEmail);
  const annaId = must((await anna.auth.getUser()).data.user, 'Anna').id;
  const benId = must((await ben.auth.getUser()).data.user, 'Ben').id;
  const note = (extra: Record<string, unknown> = {}) => ({
    id: crypto.randomUUID(), message: 'Notiz', app_version: '0.1.0', build: '1', platform: 'web',
    os_version: 'Chrome on Linux', locale: 'de', screen: 'list', ...extra,
  });

  const own = note();
  expect((await anna.from('feedback').insert(own)).error, 'own note').toBeNull();
  expect((await anna.from('feedback').insert({ ...own, message: 'Nochmal' })).error, 'a repeat of its id').toBeNull();
  const asBen = await anna.from('feedback').insert(note({ user_id: benId }));
  expect(asBen.error?.code, 'in another user\'s name').toBe('42501');

  const read = await anna.from('feedback').select('*');
  expect(read.error?.code, 'the sender reads no context columns').toBe('42501');
  const shown = 'id, message, status, reply, answered_at, seen_at';
  const ownRead = await anna.from('feedback').select(shown);
  expect(ownRead.data, 'the sender reads the shown columns of their own note (job 268)').toEqual([
    { id: own.id, message: 'Notiz', status: 'sent', reply: null, answered_at: null, seen_at: null },
  ]);
  const seen = await anna.from('feedback').update({ seen_at: new Date().toISOString() }).eq('id', own.id);
  expect(seen.error?.code, 'nor stamps seen_at by hand').toBe('42501');
  const update = await anna.from('feedback').update({ message: 'Geändert' }).eq('id', own.id);
  expect(update.error?.code, 'nor changes it').toBe('42501');
  const del = await anna.from('feedback').delete().eq('id', own.id);
  expect(del.error?.code, 'nor deletes it').toBe('42501');
  const benRead = await ben.from('feedback').select('*').eq('user_id', annaId);
  expect(benRead.error?.code, 'nor does anyone else').toBe('42501');
  const benShown = await ben.from('feedback').select(shown).eq('id', own.id);
  expect(benShown.data, 'nor any of Anna\'s note, by id').toEqual([]);
  const reused = await ben.from('feedback').insert(note({ id: own.id }));
  expect(reused.error?.code, 'Anna\'s id is not Ben\'s').toBe('23505');

  const anon = anonClient();
  expect((await anon.from('feedback').insert(note())).error?.code, 'anon cannot send').toBe('42501');
  expect((await anon.from('feedback').select('*')).error?.code, 'nor read').toBe('42501');

  const { data: rows } = await admin.from('feedback').select('user_id, message').in('user_id', [annaId, benId]);
  expect(rows, 'one row, Anna\'s first text, untouched').toEqual([{ user_id: annaId, message: 'Notiz' }]);
});
