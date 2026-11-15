/**
 * What each video films, per language. A shot gets its members' apps signed in and recording;
 * it acts only through real input and returns what it measured.
 */

import { type Client, find, gone, type Session, sleep } from './driver.ts';

type Lang = 'de' | 'en';
type Clients = Record<string, Client>;

/** The client of [name]; take.ts signs in every one of a shot's `members` before filming. */
function member(c: Clients, name: string): Client {
  const client = c[name];
  if (client === undefined) throw new Error(`no client ${name}: list it in the shot's members`);
  return client;
}

export interface Shot {
  scenario: Record<Lang, string>;
  members: string[];
  /** The sentence each member's microphone hears (empty: it hears nothing). */
  dictation?: Record<Lang, string>;
  prepare?(s: Session, c: Clients, lang: Lang): Promise<void>;
  film(s: Session, c: Clients, lang: Lang): Promise<Record<string, unknown> | void>;
}

const items = {
  addTick: { de: ['Honig', 'Marmelade'], en: ['Honey', 'Jam'] },
  sync: { de: 'Eier', en: 'Eggs' },
  mcp: { de: ['Honig', 'Marmelade'], en: ['Honey', 'Jam'] },
  // The app listens in German in either language (lib/list/dictation.dart), so the English take
  // hears the German sentence too.
  voice: {
    said: 'Pizza, Orangensaft und zwei Packungen Fischstäbchen',
    rows: ['Orangensaft', 'Pizza', 'Fischstäbchen'],
    added: { de: 'Hinzugefügt', en: 'Added' },
  },
} as const;

/** A value take.ts sets from the local stack before any shot runs. */
function takeEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`${name} is not set; run shots through take.ts`);
  return value;
}

/**
 * Sam's MCP client for the take: signs in over the auth API and creates a personal access token
 * through the same RPC the app's Zugänge screen uses. The token lives only in memory; the
 * fixture teardown deletes it with the user. Calls go to the local stack's mcp function.
 */
async function mcpClient(c: Client) {
  const api = takeEnv('CAPTURE_API_URL');
  const key = takeEnv('CAPTURE_PUBLISHABLE_KEY');
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

/** Seconds from `since` until `client` shows (or, with gone, stops showing) `text`; `part` matches inside a longer text. */
async function until(s: Session, c: Client, text: string, since: number, isGone = false, part = false) {
  const target = part ? { contains: text } : { text };
  if (isGone) await gone(c, target, 20_000);
  else await find(c, target, 20_000);
  const ms = performance.timeOrigin + performance.now() - since;
  s.mark(c.name, `${isGone ? 'gone' : 'shown'} ${text} after ${Math.round(ms)} ms (Marionette poll)`);
  return Math.round(ms);
}

const now = () => performance.timeOrigin + performance.now();

export const shots: Record<string, Shot> = {
  'add-tick': {
    scenario: { de: 'demo-haushalt', en: 'demo-household-en' },
    members: ['anna'],
    async film(s, c, lang) {
      const anna = member(c, 'anna');
      const [first, second] = items.addTick[lang];
      await sleep(1500);
      s.mark('anna', 'open');
      await s.tap(anna, { key: 'add-item-field' }, { dx: 262 });
      await find(anna, { key: 'add-sheet-close' });
      await sleep(450);
      await s.type(anna, first, 110);
      await sleep(500);
      await s.key(anna, 'Return');
      await sleep(900);
      await s.type(anna, second, 110);
      await sleep(500);
      await s.key(anna, 'Return');
      await sleep(1000);
      s.mark('anna', 'close');
      await s.tap(anna, { key: 'add-sheet-close' });
      await gone(anna, { key: 'add-sheet-close' });
      await sleep(1300);
      s.mark('anna', 'tick');
      await s.tap(anna, { text: first }, { dx: 210 });
      await sleep(900);
      await s.tap(anna, { text: second }, { dx: 210 });
      await sleep(8000);
      s.mark('anna', 'end');
    },
  },
  'household-sync': {
    scenario: { de: 'demo-haushalt', en: 'demo-household-en' },
    members: ['anna', 'jonas'],
    async film(s, c, lang) {
      const anna = member(c, 'anna');
      const jonas = member(c, 'jonas');
      const item = items.sync[lang];
      await sleep(1500);
      await s.tap(anna, { key: 'add-item-field' }, { dx: 262 });
      await find(anna, { key: 'add-sheet-close' });
      await sleep(450);
      await s.type(anna, item, 120);
      await sleep(450);
      await s.key(anna, 'Return');
      const added = now();
      const toJonas = await until(s, jonas, item, added);
      // Jonas's row stays honey for about 2.5 s: the sheet closes and the view reaches the top of
      // Anna's list while it is still fresh (the poster).
      await sleep(300);
      // Anna closes the sheet with its close button, which stays in every crop (a tap on the list
      // above the sheet would be off camera).
      s.mark('anna', 'close');
      await s.tap(anna, { key: 'add-sheet-close' });
      await gone(anna, { key: 'add-sheet-close' });
      await sleep(1600);
      await s.tap(jonas, { text: item }, { dx: 118 });
      const ticked = now();
      const goneAnna = await until(s, anna, item, ticked, true);
      await sleep(3000);
      s.mark('anna', 'end');
      return { addToJonasMs: toJonas, tickToAnnaMs: goneAnna };
    },
  },
  'voice-add': {
    scenario: { de: 'demo-familie', en: 'demo-family-en' },
    members: ['mia'],
    dictation: { de: items.voice.said, en: items.voice.said },
    async prepare(s, c, lang) {
      const mia = member(c, 'mia');
      // The drinks and the frozen section sit right above the add field, where the new rows land.
      await s.scrollUntil(mia, { text: lang === 'de' ? 'Schokolade' : 'Cookies' }, 210);
      // One item bought before filming: "Zuletzt verwendet" is there from the first frame, so the
      // three ticks at the end don't add it and the loop's last frame matches its first.
      const bought = lang === 'de' ? 'Zahnpasta' : 'Toothpaste';
      await s.tap(mia, { text: bought }, { dx: 150 });
      await gone(mia, { text: bought });
      await sleep(1500);
    },
    async film(s, c, lang) {
      const mia = member(c, 'mia');
      // Located once: a lookup between the taps would delay the stop by a second or more.
      const b = await find(mia, { key: 'dictation-button' });
      const button = { x: b.x + b.width / 2, y: b.y + b.height / 2 };
      await sleep(1500);
      s.mark('mia', 'mic');
      await s.tap(mia, button);
      const tapped = now();
      // The sentence takes about 2.4 s (scripted_speech.dart); then she taps the red stop button
      // instead of waiting out the recognizer's 3 s pause.
      await sleep(3300);
      s.mark('mia', 'stop');
      await s.tap(mia, button);
      // The app's own message after the add; until then the field holds the words.
      const shown = await until(s, mia, items.voice.added[lang], tapped, false, true);
      const rows = await Promise.all(items.voice.rows.map((n) => find(mia, { contains: n })));
      const newRows = { top: Math.min(...rows.map((r) => r.y)), bottom: Math.max(...rows.map((r) => r.y + r.height)) };
      await sleep(2400);
      s.mark('mia', 'tick');
      // Bottom up, so no row moves under the finger before its tap.
      for (const row of [...rows].sort((a, b) => b.y - a.y)) {
        await s.tap(mia, { x: row.x + 150, y: row.y + row.height / 2 });
        await sleep(550);
      }
      await sleep(2000);
      s.mark('mia', 'end');
      return { addedMessageMs: shown, newRows, said: items.voice.said, added: items.voice.added[lang] };
    },
  },
  'mcp-chat': {
    scenario: { de: 'solo-long-list', en: 'solo-long-list' },
    members: ['sam'],
    async prepare(s, c) {
      const sam = member(c, 'sam');
      // Sam looks at the pantry rows without a store, where new pantry items land; scrolled only
      // so far that they land just above the add field, so the compact crop holds both.
      await s.scrollUntil(sam, { text: 'Ketchup' }, 520);
    },
    async film(s, c, lang) {
      const sam = member(c, 'sam');
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
