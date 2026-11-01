import { Client, StreamableHTTPClientTransport, UnauthorizedError } from '@modelcontextprotocol/client';
import { expect, type Page, test } from './fixtures';
import {
  addItem, apiAs, itemRow, newEmail, openMore, openTab, password, publishableKey, screenshot, signUpWithHousehold, supabaseUrl, typeInto, within,
} from './helpers';
import {
  call, callbackParams, callExpectingError, connectWithToken, mcpUrl, openAuthorization, TestOAuthProvider, timedFetch,
} from './mcp-helpers';

type Item = { id: string; name: string; quantity: string | null; category: string; store: string | null };

const metadataUrl = `${mcpUrl}/.well-known/oauth-protected-resource`;

const toolsList = (token: string) =>
  fetch(mcpUrl, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
  });

test('MCP over OAuth 2.1: discovery, registration, consent with PKCE, then tools change the list live', async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  const app = await context.newPage();
  const email = newEmail('oauth');
  await signUpWithHousehold(app, email);
  await addItem(app, 'Brot');

  // Discovery as an MCP host performs it, asserted step by step.
  const unauthenticated = await fetch(mcpUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
  });
  expect(unauthenticated.status, 'no token: 401').toBe(401);
  expect(unauthenticated.headers.get('www-authenticate')).toContain(`resource_metadata="${metadataUrl}"`);
  const prm = await (await fetch(metadataUrl)).json();
  expect(prm.resource).toBe(mcpUrl.toString());
  const issuer = `${supabaseUrl}/auth/v1`;
  expect(prm.authorization_servers).toEqual([issuer]);
  const as = await (await fetch(`${issuer}/.well-known/openid-configuration`)).json();
  expect(as.issuer).toBe(issuer);
  expect(as.registration_endpoint, 'dynamic client registration is enabled').toBe(`${issuer}/oauth/clients/register`);
  expect(as.code_challenge_methods_supported).toContain('S256');

  // The SDK runs the real client flow: PRM -> AS metadata -> DCR -> PKCE authorization URL.
  const provider = new TestOAuthProvider('Claude (E2E)');
  const transport = new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider, fetch: timedFetch });
  await expect(new Client({ name: 'family-groceries-e2e', version: '1.0.0' }).connect(transport))
    .rejects.toThrow(UnauthorizedError);
  expect(provider.client?.client_id, 'registered dynamically').toBeTruthy();
  const authorizationUrl = provider.authorizationUrl!;
  expect(authorizationUrl.origin + authorizationUrl.pathname).toBe(`${issuer}/oauth/authorize`);
  expect(authorizationUrl.searchParams.get('code_challenge_method')).toBe('S256');
  expect(authorizationUrl.searchParams.get('resource')).toBe(mcpUrl.toString());

  // The user approves on the app's consent page, signed in in the same browser.
  const consent = await context.newPage();
  await openAuthorization(consent, authorizationUrl, baseURL!);
  await expect(consent.getByText('Claude (E2E)').first()).toBeVisible();
  await expect(consent.getByText(email).first()).toBeVisible();
  await screenshot(consent, 'mcp-01-consent');
  await consent.getByRole('button', { name: 'Erlauben' }).click();
  const params = await callbackParams(consent);
  expect(params.get('state')).toBe(authorizationUrl.searchParams.get('state'));

  await transport.finishAuth(params.get('code')!);
  const accessToken = provider.saved!.access_token;
  const claims = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url').toString());
  expect(claims.client_id, 'the access token belongs to the registered client').toBe(provider.client!.client_id);

  const client = new Client({ name: 'family-groceries-e2e', version: '1.0.0' });
  await client.connect(new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider, fetch: timedFetch }));
  expect(client.getServerVersion()?.name).toBe('hummlist');
  const { tools } = await client.listTools();
  expect(tools.map((t) => t.name).sort()).toEqual(
    ['add_items', 'list_categories', 'list_items', 'list_stores', 'move_item', 'tick_items'],
  );

  const added = await call<{ added: Item[]; alreadyOnList: Item[] }>(client, 'add_items', {
    items: [{ name: 'Hafermilch' }, { name: 'Äpfel', quantity: '6' }, { name: 'Brot' }],
  });
  expect(added.added.map((i) => [i.name, i.category])).toEqual([
    ['Hafermilch', 'Kühlregal'],
    ['Äpfel', 'Obst & Gemüse'],
  ]);
  expect(added.alreadyOnList.map((i) => i.name), 'no duplicates').toEqual(['Brot']);
  await within(3_000, (timeout) => expect(itemRow(app, 'Hafermilch'), 'an MCP add shows up live in the app').toBeVisible({ timeout }));
  await expect(itemRow(app, 'Äpfel')).toHaveAccessibleName('Äpfel 6');

  const moved = await call<Item>(client, 'move_item', { item: 'hafermilch', category: 'Getränke', store: 'Lidl' });
  expect([moved.category, moved.store]).toEqual(['Getränke', 'Lidl']);
  const db = await apiAs(email);
  await expect.poll(async () =>
    (await db.from('items').select('categories(name)').eq('name', 'Hafermilch').single()).data,
  ).toEqual({ categories: { name: 'Getränke' } });

  await screenshot(app, 'mcp-02-list-after-add');
  const ticked = await call<{ ticked: Item[] }>(client, 'tick_items', { items: ['Brot', 'äpfel'] });
  expect(ticked.ticked.map((i) => i.name).sort()).toEqual(['Brot', 'Äpfel']);
  await within(3_000, (timeout) => expect(itemRow(app, 'Brot'), 'an MCP tick disappears live in the app').toHaveCount(0, { timeout }));

  const listed = await call<{ items: Item[] }>(client, 'list_items', {});
  expect(listed.items.map((i) => i.name)).toEqual(['Hafermilch']);
  await screenshot(app, 'mcp-03-list-after-tick');

  // The grant shows up in the app's settings and can be disconnected there.
  await openMore(app, 'Zugänge');
  await expect(app.getByText('Claude (E2E)').first()).toBeVisible();
  await expect(
    app.getByRole('group', { name: mcpUrl.href }),
    'a build for another project than production shows that project\'s function URL',
  ).toBeVisible();
  await screenshot(app, 'mcp-04-settings-connected-app');

  // Disconnecting cuts the client off at once, although its access token has not expired.
  expect(claims.exp * 1000 - Date.now(), 'the access token is still far from expiry').toBeGreaterThan(30 * 60_000);
  await call(client, 'list_items', {});
  await app.getByRole('button', { name: 'Claude (E2E) trennen' }).click();
  await app.getByRole('button', { name: 'Trennen', exact: true }).click();
  await expect(app.getByText('Noch keine App verbunden.')).toBeVisible();
  await screenshot(app, 'mcp-07-settings-after-disconnect');
  const afterDisconnect = await toolsList(accessToken);
  expect(afterDisconnect.status, 'the next call after disconnecting gets 401').toBe(401);
  expect(afterDisconnect.headers.get('www-authenticate')).toContain('error="invalid_token"');
  await expect(client.callTool({ name: 'list_items', arguments: {} }), 'the connected SDK client is cut off too')
    .rejects.toThrow();
  const refreshed = await fetch(`${issuer}/oauth/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: provider.saved!.refresh_token!,
      client_id: provider.client!.client_id,
    }),
  });
  expect(refreshed.ok, 'the refresh token is revoked as well').toBe(false);
});

test('a category or store corrected over MCP is learned and used on the next MCP add', async ({ browser }) => {
  const page = await (await browser.newContext()).newPage();
  await signUpWithHousehold(page, newEmail('learn'));
  const client = await connectWithToken(await createTokenInSettings(page, 'Lernen'));

  const first = await call<{ added: Item[] }>(client, 'add_items', { items: [{ name: 'Hafermilch' }] });
  expect(first.added.map((i) => [i.category, i.store])).toEqual([['Kühlregal', null]]);
  await call(client, 'move_item', { item: 'Hafermilch', category: 'Getränke', store: 'Lidl' });
  await call(client, 'tick_items', { items: ['Hafermilch'] });

  const again = await call<{ added: Item[]; alreadyOnList: Item[] }>(client, 'add_items', {
    items: [{ name: 'hafermilch' }, { name: '2 Gurken' }, { name: 'Gurke' }],
  });
  expect(again.added.map((i) => [i.name, i.quantity, i.category, i.store])).toEqual([
    ['hafermilch', null, 'Getränke', 'Lidl'],
    ['Gurken', '2', 'Obst & Gemüse', null],
  ]);
  expect(again.alreadyOnList.map((i) => i.name), '"Gurke" is "2 Gurken"').toEqual(['Gurken']);

  const named = await call<{ added: Item[] }>(client, 'add_items', {
    items: [{ name: 'Zahnpasta', category: 'Getränke', quantity: '3' }],
  });
  expect(named.added.map((i) => [i.category, i.quantity])).toEqual([['Getränke', '3']]);
  await call(client, 'tick_items', { items: ['Zahnpasta'] });
  const remembered = await call<{ added: Item[] }>(client, 'add_items', { items: [{ name: 'Zahnpasta' }] });
  expect(remembered.added[0].category, 'an explicit category is remembered like a correction').toBe('Getränke');
});

test('denying consent sends access_denied back to the client', async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await signUpWithHousehold(page, newEmail('deny'));
  const provider = new TestOAuthProvider('Unbekannter Client');
  await expect(new Client({ name: 'e2e', version: '1' })
    .connect(new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider, fetch: timedFetch })))
    .rejects.toThrow(UnauthorizedError);
  await openAuthorization(page, provider.authorizationUrl!, baseURL!);
  await page.getByRole('button', { name: 'Ablehnen' }).click();
  const params = await callbackParams(page);
  expect(params.get('error')).toBe('access_denied');
  expect(params.get('code')).toBeNull();
});

test('a signed-out user signs in on the way to the consent page and lands back on it', async ({ browser, baseURL }) => {
  const setup = await browser.newContext();
  const email = newEmail('consent-login');
  await signUpWithHousehold(await setup.newPage(), email);
  await setup.close();

  const page = await (await browser.newContext()).newPage();
  const provider = new TestOAuthProvider('ChatGPT (E2E)');
  await expect(new Client({ name: 'e2e', version: '1' })
    .connect(new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider, fetch: timedFetch })))
    .rejects.toThrow(UnauthorizedError);
  await openAuthorization(page, provider.authorizationUrl!, baseURL!);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden' }).last().click();
  await expect(page.getByText('ChatGPT (E2E)').first()).toBeVisible();
  await page.getByRole('button', { name: 'Erlauben' }).click();
  expect((await callbackParams(page)).get('code')).toBeTruthy();
});

async function createTokenInSettings(page: Page, name: string): Promise<string> {
  await openMore(page, 'Zugänge');
  await page.getByRole('button', { name: 'Token erstellen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), name);
  await page.getByRole('button', { name: 'Erstellen' }).click();
  const shown = page.getByText(/^fgp_[A-Za-z0-9_-]{43}$/);
  await expect(shown).toBeVisible();
  return (await shown.textContent())!;
}

test('personal access token: create in settings, use over MCP in both protocol eras, revoke -> 401', async ({ browser }) => {
  const page = await (await browser.newContext()).newPage();
  await signUpWithHousehold(page, newEmail('pat'));
  const token = await createTokenInSettings(page, 'Siri');
  await screenshot(page, 'mcp-05-pat-created');
  await page.getByRole('button', { name: 'Fertig' }).click();
  await expect(page.getByText(/fgp_/), 'the token is shown only once').toHaveCount(0);

  const legacy = await connectWithToken(token, 'legacy');
  await call(legacy, 'add_items', { items: [{ name: 'Klopapier' }] });
  const modern = await connectWithToken(token, 'modern');
  const listed = await call<{ items: Item[] }>(modern, 'list_items', {});
  expect(listed.items.map((i) => i.name)).toEqual(['Klopapier']);
  const stores = await call<{ name: string }[]>(modern, 'list_stores');
  expect(stores.map((s) => s.name)).toEqual(['dm', 'Lidl', 'Edeka']);
  const categories = await call<{ name: string }[]>(modern, 'list_categories');
  expect(categories[0].name).toBe('Obst & Gemüse');

  await openTab(page, 'Liste');
  await expect(itemRow(page, 'Klopapier')).toBeVisible();
  await openMore(page, 'Zugänge');
  await expect(page.getByRole('group', { name: /^Siri …\S{4} · Erstellt am .* · Zuletzt benutzt / })).toBeVisible();
  await page.getByRole('button', { name: 'Siri widerrufen' }).click();
  await page.getByRole('button', { name: 'Widerrufen' }).click();
  await expect(page.getByRole('button', { name: 'Siri widerrufen' })).toHaveCount(0);
  await screenshot(page, 'mcp-06-pat-revoked');

  const revoked = await toolsList(token);
  expect(revoked.status, 'the first call after revoking gets 401').toBe(401);
  expect(revoked.headers.get('www-authenticate')).toContain('error="invalid_token"');
  await expect(connectWithToken(token)).rejects.toThrow();
});

test('a store the household added, renamed or deleted is what MCP knows by name', async ({ browser }) => {
  const page = await (await browser.newContext()).newPage();
  const email = newEmail('own-store');
  await signUpWithHousehold(page, email);
  const db = await apiAs(email);
  const { data: household } = await db.from('household_members').select('household_id').single();
  const { data: rewe, error } = await db.rpc('add_store', { p_household: household!.household_id, p_name: 'Rewe' });
  expect(error).toBeNull();
  const client = await connectWithToken(await createTokenInSettings(page, 'Läden'));

  const stores = await call<{ name: string }[]>(client, 'list_stores');
  expect(stores.map((s) => s.name)).toEqual(['dm', 'Lidl', 'Edeka', 'Rewe']);
  const added = await call<{ added: Item[] }>(client, 'add_items', { items: [{ name: 'Milch', store: 'rewe' }] });
  expect(added.added.map((i) => i.store)).toEqual(['Rewe']);
  const inRewe = await call<{ items: Item[] }>(client, 'list_items', { store: 'REWE' });
  expect(inRewe.items.map((i) => i.name)).toEqual(['Milch']);

  await db.rpc('rename_store', { p_store: rewe, p_name: 'Rewe Markt' });
  const moved = await call<Item>(client, 'move_item', { item: 'Milch', store: 'rewe markt' });
  expect(moved.store).toBe('Rewe Markt');

  await db.rpc('delete_store', { p_store: rewe });
  const after = await call<{ items: Item[] }>(client, 'list_items', {});
  expect(after.items.map((i) => [i.name, i.store])).toEqual([['Milch', null]]);
  expect(await callExpectingError(client, 'add_items', { items: [{ name: 'Brot', store: 'Rewe Markt' }] }))
    .toContain('Laden „Rewe Markt“ nicht gefunden. Vorhanden: dm, Lidl, Edeka.');
});

test('another household\'s credentials can neither see nor change this household\'s list', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const peterEmail = newEmail('peter');
  await signUpWithHousehold(peter, peterEmail);
  await addItem(peter, 'Milch');
  const peterDb = await apiAs(peterEmail);
  const { data: milk } = await peterDb.from('items').select('id').eq('name', 'Milch').single();

  const mallory = await (await browser.newContext()).newPage();
  await signUpWithHousehold(mallory, newEmail('mallory'));
  const client = await connectWithToken(await createTokenInSettings(mallory, 'Fremd'));

  expect((await call<{ items: Item[] }>(client, 'list_items', {})).items).toEqual([]);
  const tick = await call<{ ticked: Item[]; notFound: unknown[] }>(client, 'tick_items', { items: [milk!.id] });
  expect(tick.ticked).toEqual([]);
  expect(tick.notFound).toHaveLength(1);
  expect(await callExpectingError(client, 'move_item', { item: milk!.id, category: 'Getränke' }))
    .toContain('nicht gefunden');

  await expect(itemRow(peter, 'Milch'), 'the other household\'s item is untouched').toBeVisible();
  const { data } = await peterDb.from('items').select('status, categories(name)').eq('id', milk!.id).single();
  expect(data).toEqual({ status: 'active', categories: { name: 'Kühlregal' } });
});

test('app session tokens and forged tokens are refused by the MCP endpoint', async () => {
  const email = newEmail('session');
  const response = await fetch(`${supabaseUrl}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const { access_token: sessionToken } = await response.json();
  await fetch(`${supabaseUrl}/rest/v1/rpc/create_household`, {
    method: 'POST',
    headers: { apikey: publishableKey, authorization: `Bearer ${sessionToken}`, 'content-type': 'application/json' },
    body: '{}',
  });
  for (const token of [sessionToken, `${sessionToken.slice(0, -4)}AAAA`, 'fgp_made-up']) {
    const res = await fetch(mcpUrl, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: '{}',
    });
    expect(res.status).toBe(401);
  }
});
