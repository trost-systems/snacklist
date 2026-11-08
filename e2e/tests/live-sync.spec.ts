import { expect, test } from './fixtures';
import { addField, addItem, apiAs, confirmJoin, createHousehold, createInviteCode, editField, householdChip, invitePreview, itemRow, joinWithCode, must, newEmail, offlineIndicator, openEdit, openMore, saveEdit, screenshot, signUp, signUpWithHousehold, skipInvite, switchHousehold, tick, typeInto, within } from './helpers';

test('two members of one household see each other\'s changes live', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();

  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Milch');
  const code = await createInviteCode(peter);

  const leaEmail = newEmail('lea');
  await signUp(lea, leaEmail);
  await joinWithCode(lea, code, 'Unser Haushalt');
  await expect(addField(lea)).toBeFocused();
  await expect(itemRow(lea, 'Milch'), 'the joiner sees the existing list').toBeVisible();

  await addItem(peter, 'Bananen');
  await within(2_000, (timeout) => expect(itemRow(lea, 'Bananen'), 'an add in A appears in B').toBeVisible({ timeout }));

  await tick(lea, 'Milch');
  await within(2_000, (timeout) => expect(itemRow(peter, 'Milch'), 'a tick in B disappears in A').toHaveCount(0, { timeout }));

  await addItem(lea, 'Windeln');
  await within(2_000, (timeout) => expect(itemRow(peter, 'Windeln'), 'an add in B appears in A').toBeVisible({ timeout }));

  await openEdit(peter, 'Bananen');
  await typeInto(editField(peter, 'Menge'), '6');
  await saveEdit(peter);
  // "Neu" (read last) stays on a partner's item until it was on screen for 3 s, which this test may not reach.
  await within(2_000, (timeout) => expect(itemRow(lea, 'Bananen'), 'an edit in A updates B').toHaveAccessibleName(/^Bananen 6( Neu)?$/, { timeout }));

  // The app's only delete is a screen-reader action Playwright cannot trigger (job 149): delete as B through the API.
  const deleted = await (await apiAs(leaEmail)).from('items').delete().eq('name', 'Windeln').select('id');
  expect(deleted.error).toBeNull();
  expect(deleted.data).toHaveLength(1);
  await within(2_000, (timeout) => expect(itemRow(peter, 'Windeln'), 'a delete in B disappears in A').toHaveCount(0, { timeout }));

  await screenshot(peter, '05-live-sync-a');
  await screenshot(lea, '06-live-sync-b');
});

test('an invite link takes a new user through sign-up straight into the household', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);

  await signUp(lea, newEmail('lea'), `/join/${code}`);
  // Job 22: the link skips Step 1; the join screen names the household before joining.
  await expect(lea).toHaveURL(new RegExp(`/join/${code}$`));
  // The household's name shows: the screen looked the code up (a field's value is not in the DOM).
  await confirmJoin(lea, 'Unser Haushalt');
  await expect(itemRow(lea, 'Kaffee')).toBeVisible();
  // AC4: the same list, live, both ways.
  await addItem(peter, 'Milch');
  await within(2_000, (timeout) => expect(itemRow(lea, 'Milch'), 'an add by the inviter appears for the joiner').toBeVisible({ timeout }));
  await addItem(lea, 'Brot');
  await within(2_000, (timeout) => expect(itemRow(peter, 'Brot'), 'and the other way').toBeVisible({ timeout }));
});

test('a member of another household joins with a code from the menu and keeps both', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();
  const errors: string[] = [];
  lea.on('pageerror', (e) => errors.push(e.message));
  lea.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await signUp(peter, newEmail('peter'));
  await createHousehold(peter, { name: 'Familie Trost' });
  await skipInvite(peter);
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);
  await signUpWithHousehold(lea, newEmail('lea'));
  await addItem(lea, 'Tee');

  await openMore(lea, 'Anderem Haushalt beitreten');
  await expect(lea).toHaveURL(/\/more\/join$/);
  await typeInto(lea.getByRole('textbox', { name: 'Einladungscode' }), code.toLowerCase());
  await lea.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(invitePreview(lea, 'Familie Trost')).toBeVisible();
  // Job 169b: joining adds a household, so nothing warns about leaving the old one.
  await expect(lea.getByText('Du bist schon in einem Haushalt'), 'no move warning').toHaveCount(0);
  await screenshot(lea, '07-join-confirm');
  await confirmJoin(lea, 'Familie Trost');

  await expect(householdChip(lea, 'Familie Trost'), 'the joined household shows').toBeVisible();
  await expect(itemRow(lea, 'Kaffee'), 'the joiner sees the new household\'s list').toBeVisible();
  await expect(itemRow(lea, 'Tee'), 'the other household\'s list is not mixed in').toHaveCount(0);
  // Both opening resyncs have answered by now; a lost race shows Offline.
  await lea.waitForTimeout(1_000);
  await expect(offlineIndicator(lea), 'the new list is online').toHaveCount(0);
  await addItem(lea, 'Brot');
  await expect(itemRow(peter, 'Brot'), 'and both now share one list').toBeVisible();

  await switchHousehold(lea, 'Familie Trost', 'Unser Haushalt');
  await expect(itemRow(lea, 'Tee'), 'the joiner\'s own household and list stay').toBeVisible();
  await expect(itemRow(lea, 'Kaffee')).toHaveCount(0);
  expect(errors, 'no Flutter errors on the way').toEqual([]);
});

test('a tick made while offline syncs when the connection returns', async ({ browser }) => {
  const peterContext = await browser.newContext();
  const peter = await peterContext.newPage();
  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Brot');
  const code = await createInviteCode(peter);
  await signUp(lea, newEmail('lea'), `/join/${code}`);
  await confirmJoin(lea);
  await expect(itemRow(lea, 'Brot')).toBeVisible();

  await peterContext.setOffline(true);
  await tick(peter, 'Brot');
  await addItem(peter, 'Eier');
  await expect(itemRow(peter, 'Brot'), 'optimistic while offline').toHaveCount(0);
  await expect(itemRow(peter, 'Eier')).toBeVisible();
  await expect(offlineIndicator(peter)).toHaveCount(1);
  await screenshot(peter, '07-offline-pending');
  await expect(itemRow(lea, 'Brot'), 'the other side has not seen it yet').toBeVisible();

  await peterContext.setOffline(false);
  await expect(itemRow(lea, 'Brot')).toHaveCount(0, { timeout: 15_000 });
  await expect(itemRow(lea, 'Eier')).toBeVisible({ timeout: 15_000 });
});

test('a change made before the channel is live still shows up', async ({ page }) => {
  // Realtime confirms the join before its Postgres listener runs and says
  // "Subscribed to PostgreSQL" when it does; a change in between is never
  // delivered. Simulate that window by holding the message back.
  let ready: string | undefined;
  let live = false;
  let release = () => {};
  await page.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => {
    const server = ws.connectToServer();
    ws.onMessage((message) => server.send(message));
    server.onMessage((message) => {
      const frame = String(message);
      // Only the list's channel: other channels (job 25's entitlements) pass through untouched.
      const list = frame.includes('"realtime:household:');
      if (!live && list && frame.includes('Subscribed to PostgreSQL')) ready = frame;
      else if (!live && list && frame.includes('"postgres_changes",{"data"')) return;
      else ws.send(message);
    });
    release = () => {
      live = true;
      if (ready === undefined) throw new Error('released before the list channel was live');
      ws.send(ready);
    };
  });
  const email = newEmail('gap');
  await signUpWithHousehold(page, email);
  await expect.poll(() => ready, { message: 'the server says it is live' }).toBeTruthy();

  const api = await apiAs(email);
  const { data } = await api.from('household_members').select('household_id').single();
  await api.from('items').insert({ household_id: must(data, 'membership').household_id, name: 'Zwischendurch' });
  await page.waitForTimeout(1_000);
  await expect(itemRow(page, 'Zwischendurch'), 'not delivered while the listener starts').toHaveCount(0);

  release();
  await expect(itemRow(page, 'Zwischendurch'), 'caught up once the channel is live').toBeVisible();
});

/** Routes the page's Realtime socket through the test so it can play the server's part. */
async function interceptRealtime(page: import('@playwright/test').Page) {
  const state: {
    joined?: unknown[];
    live: boolean;
    close: () => void;
    closeServer: () => Promise<void>;
    closeChannel: () => void;
  } = {
    live: false,
    close: () => {},
    closeServer: async () => {},
    closeChannel: () => {},
  };
  await page.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => {
    const server = ws.connectToServer();
    ws.onMessage((message) => {
      const frame = JSON.parse(String(message)) as unknown[];
      if (frame[3] === 'phx_join' && String(frame[2]).startsWith('realtime:household:')) state.joined = frame;
      server.send(message);
    });
    server.onMessage((message) => {
      if (String(message).includes('Subscribed to PostgreSQL')) state.live = true;
      ws.send(message);
    });
    state.close = () => ws.close({ code: 1011, reason: 'server restart' });
    state.closeServer = async () => {
      await server.close({ code: 1001, reason: 'gone' });
      await ws.close({ code: 1001, reason: 'connection lost' });
    };
    state.closeChannel = () => {
      const joined = must(state.joined, 'phx_join of the list channel');
      ws.send(JSON.stringify([joined[0], null, joined[2], 'phx_close', {}]));
    };
  });
  return state;
}

for (const drop of ['closes the list channel', 'drops the socket'] as const) {
  test(`the list recovers when Realtime ${drop}`, async ({ page }) => {
    const realtime = await interceptRealtime(page);
    const email = newEmail('drop');
    await signUpWithHousehold(page, email);
    await expect.poll(() => realtime.live, { message: 'the channel is live' }).toBe(true);
    realtime.live = false;

    if (drop === 'closes the list channel') realtime.closeChannel();
    else realtime.close();
    await expect(offlineIndicator(page), 'the drop shows').toHaveCount(1);

    await expect(offlineIndicator(page), 'and clears again on its own').toHaveCount(0, { timeout: 20_000 });
    await expect.poll(() => realtime.live, { message: 'live again', timeout: 20_000 }).toBe(true);
    const api = await apiAs(email);
    const { data } = await api.from('household_members').select('household_id').single();
    await api.from('items').insert({ household_id: must(data, 'membership').household_id, name: 'Nach dem Abbruch' });
    await expect(itemRow(page, 'Nach dem Abbruch'), 'live updates flow again').toBeVisible();
  });
}

test('a phone that sleeps through a dropped connection and a partner\'s add catches up when it wakes and stays live', async ({ page }) => {
  const realtime = await interceptRealtime(page);
  const email = newEmail('sleep');
  await signUpWithHousehold(page, email);
  await expect.poll(() => realtime.live, { message: 'the channel is live' }).toBe(true);
  realtime.live = false;
  const api = await apiAs(email);
  const { data } = await api.from('household_members').select('household_id').single();
  const household = must(data, 'membership').household_id;

  // Frozen like a suspended app: no script, no timers. Its connection dies meanwhile, and the
  // close event reaches the app only when it wakes, together with every overdue timer.
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Page.setWebLifecycleState', { state: 'frozen' });
  await realtime.closeServer();
  await api.from('items').insert({ household_id: household, name: 'Im Schlaf' });
  await cdp.send('Page.setWebLifecycleState', { state: 'active' });

  await expect(itemRow(page, 'Im Schlaf'), 'what was added during the sleep shows').toBeVisible({ timeout: 20_000 });
  await expect.poll(() => realtime.live, { message: 'the channel is live again', timeout: 20_000 }).toBe(true);
  await api.from('items').insert({ household_id: household, name: 'Nach dem Aufwachen' });
  await expect(itemRow(page, 'Nach dem Aufwachen'), 'live updates flow after waking').toBeVisible();
  await addItem(page, 'Vom Handy');
  await expect.poll(async () => (await api.from('items').select('name').eq('name', 'Vom Handy')).data?.length, {
    message: 'an add after waking reaches the server',
  }).toBe(1);
});
