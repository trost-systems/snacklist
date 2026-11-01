/**
 * What each video films, per language. A shot gets its members' apps signed in and recording;
 * it acts only through real input and returns what it measured.
 */

import { type Client, find, gone, type Session, sleep } from './driver.ts';

type Lang = 'de' | 'en';
type Clients = Record<string, Client>;

export interface Shot {
  scenario: Record<Lang, string>;
  members: string[];
  prepare?(s: Session, c: Clients, lang: Lang): Promise<void>;
  film(s: Session, c: Clients, lang: Lang): Promise<Record<string, unknown> | void>;
}

const items = {
  addTick: { de: ['Honig', 'Marmelade'], en: ['Honey', 'Jam'] },
  sync: { de: 'Eier', en: 'Eggs' },
  mcp: { de: ['Honig', 'Marmelade'], en: ['Honey', 'Jam'] },
};

/**
 * Sam's MCP client for the take: signs in over the auth API and creates a personal access token
 * through the same RPC the app's Zugänge screen uses. The token lives only in memory; the
 * fixture teardown deletes it with the user. Calls go to the local stack's mcp function.
 */
async function mcpClient(c: Client) {
  const api = Deno.env.get('CAPTURE_API_URL')!;
  const key = Deno.env.get('CAPTURE_PUBLISHABLE_KEY')!;
  const auth = await (await fetch(`${api}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: key, 'content-type': 'application/json' },
    body: JSON.stringify({ email: c.email, password: c.password }),
  })).json();
  const rows = await (await fetch(`${api}/rest/v1/rpc/create_personal_access_token`, {
    method: 'POST',
    headers: { apikey: key, authorization: `Bearer ${auth.access_token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ p_name: 'Demo video' }),
  })).json();
  const token = Object.values(rows[0] as Record<string, string>).find((v) => String(v).startsWith('fgp_'));
  if (!token) throw new Error('no personal access token for the take');
  let id = 0;
  return async (tool: string, args: unknown) => {
    const res = await fetch(`${api}/functions/v1/mcp`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: ++id, method: 'tools/call', params: { name: tool, arguments: args } }),
    });
    const text = await res.text();
    const json = res.headers.get('content-type')?.includes('event-stream')
      ? JSON.parse(text.split('\n').filter((l) => l.startsWith('data:')).map((l) => l.slice(5)).join(''))
      : JSON.parse(text);
    if (!res.ok || json.error || json.result?.isError) throw new Error(`mcp ${tool}: ${res.status} ${text}`);
    return json.result;
  };
}

/** Seconds from `since` until `client` shows (or, with gone, stops showing) `text`. */
async function until(s: Session, c: Client, text: string, since: number, isGone = false) {
  if (isGone) await gone(c, { text }, 20_000);
  else await find(c, { text }, 20_000);
  const ms = performance.timeOrigin + performance.now() - since;
  s.mark(c.name, `${isGone ? 'gone' : 'shown'} ${text} after ${Math.round(ms)} ms (Marionette poll)`);
  return Math.round(ms);
}

const now = () => performance.timeOrigin + performance.now();

export const shots: Record<string, Shot> = {
  'add-tick': {
    scenario: { de: 'demo-familie', en: 'demo-family-en' },
    members: ['mia'],
    async film(s, { mia }, lang) {
      const [first, second] = items.addTick[lang];
      await sleep(1500);
      s.mark('mia', 'open');
      await s.tap(mia, { key: 'add-item-field' }, { dx: 262 });
      await find(mia, { key: 'add-sheet-close' });
      await sleep(450);
      await s.type(mia, first, 110);
      await sleep(500);
      await s.key(mia, 'Return');
      await sleep(900);
      await s.type(mia, second, 110);
      await sleep(500);
      await s.key(mia, 'Return');
      await sleep(1000);
      s.mark('mia', 'close');
      await s.tap(mia, { key: 'add-sheet-close' });
      await gone(mia, { key: 'add-sheet-close' });
      await sleep(1300);
      s.mark('mia', 'tick');
      await s.tap(mia, { text: first }, { dx: 210 });
      await sleep(900);
      await s.tap(mia, { text: second }, { dx: 210 });
      await sleep(8000);
      s.mark('mia', 'end');
    },
  },
  'household-sync': {
    scenario: { de: 'demo-familie', en: 'demo-family-en' },
    members: ['mia', 'noah', 'ida'],
    async prepare(s, { noah, ida }, lang) {
      // Noah and Ida look at the chilled section, where the new item lands under Butter.
      for (const c of [noah, ida]) await s.scrollUntil(c, { text: 'Butter' }, 52);
    },
    async film(s, { mia, noah, ida }, lang) {
      const item = items.sync[lang];
      await sleep(1500);
      await s.tap(mia, { key: 'add-item-field' }, { dx: 262 });
      await find(mia, { key: 'add-sheet-close' });
      await sleep(450);
      await s.type(mia, item, 120);
      await sleep(450);
      await s.key(mia, 'Return');
      const added = now();
      const [toNoah, toIda] = await Promise.all([until(s, noah, item, added), until(s, ida, item, added)]);
      await sleep(1200);
      // Mia closes the sheet the way a phone user does, by tapping the list above it.
      await s.tap(mia, { x: 200, y: 470 });
      await gone(mia, { key: 'add-sheet-close' });
      await sleep(1600);
      await s.tap(noah, { text: item }, { dx: 118 });
      const ticked = now();
      const [goneMia, goneIda] = await Promise.all([until(s, mia, item, ticked, true), until(s, ida, item, ticked, true)]);
      await sleep(3000);
      s.mark('mia', 'end');
      return { addToNoahMs: toNoah, addToIdaMs: toIda, tickToMiaMs: goneMia, tickToIdaMs: goneIda };
    },
  },
  'mcp-chat': {
    scenario: { de: 'solo-long-list', en: 'solo-long-list' },
    members: ['sam'],
    async prepare(s, { sam }) {
      // Sam looks at the pantry rows without a store, where new pantry items land.
      await s.scrollUntil(sam, { text: 'Ketchup' }, 300);
    },
    async film(s, { sam }, lang) {
      const call = await mcpClient(sam);
      const names = items.mcp[lang];
      await sleep(3200);
      s.mark('sam', 'mcp add_items sent');
      let t0 = now();
      const added = await call('add_items', { items: names.map((name) => ({ name })) });
      s.mark('sam', `mcp add_items answered after ${Math.round(now() - t0)} ms`);
      const shown = await until(s, sam, names[1], t0);
      const rows = await Promise.all(names.map((n) => find(sam, { text: n })));
      const newRows = { top: Math.min(...rows.map((r) => r.y)), bottom: Math.max(...rows.map((r) => r.y + r.height)) };
      await sleep(2600);
      s.mark('sam', 'voice start');
      await sleep(1700);
      s.mark('sam', 'mcp tick_items sent');
      t0 = now();
      const ticked = await call('tick_items', { items: names });
      s.mark('sam', `mcp tick_items answered after ${Math.round(now() - t0)} ms`);
      const gone = await until(s, sam, names[1], t0, true);
      await sleep(2600);
      s.mark('sam', 'end');
      return { added, ticked, addToAppMs: shown, tickToAppMs: gone, newRows };
    },
  },
};
