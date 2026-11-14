#!/usr/bin/env node
// Films the raw app screens of every shot (sets.mjs) from the Snacklist release web build of this
// checkout's verify-snacklist instance, one browser, into out/raw/<locale>/<set>/<shot>.png, and
// per set a meta.json with what compose needs in capture pixels: the rows the caption points at
// (`lift`), where a card may no longer be cut (`chrome`: the floating add bar, the tab bar, or the
// end of what the shot is about) and, for sync, the confirmation band out of Jonas's phone.
//
//   node capture.mjs --locales de-DE,en-US --stores play,appstore [--assistants neutral]
//
// Each shot that changes data gets a fresh `fg seed` run; the others share one per locale. Every
// run goes into out/runs.txt and teardown.mjs removes them. The page clock is fake from the first
// script on and starts at its run's seeding moment, so the app sees the same ages every run; each
// frame is taken on a paused clock at a named moment (job 65, job 214): caret off, the honey rows
// N ms after they arrive. Items arrive the real way: Anna's adds through the API as her app
// would, the voice sentence through the local voice function and the assistant's items through
// the local mcp function, each with Jonas's personal access token.
//
// The api shot comes from a second build against the production project's URL
// (STORE_SHOTS_API_WEB, store-screenshots.sh), so its Zugänge screen shows the production hosts.
// Every browser context routes requests and websockets for that host to the local stack, and the
// run fails if one of them went anywhere else.
import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { addField, addSheet, apiAs, chromium, instance, itemRow, labels, openTab, repo, signIn, typeInto } from '../../.claude/skills/verify-snacklist/helpers/lib.mjs';
import { captionsFor } from './captions.mjs';
import { LOCALES, SETS, plan } from './sets.mjs';

export const OUT = process.env.STORE_SHOTS_OUT ?? join(import.meta.dirname, 'out');

/** What each locale's scenes type, add and look for: app input and seeded data, not captions. */
const INPUT = {
  de: {
    stores: { market: 'Wochenmarkt', bakery: 'Bäckerei', super: 'Supermarkt' },
    annaAdds: ['Erdbeeren', 'Trauben'],
    jonasTypes: 'Kaffee',
    typed: '3 Jogh',
    // The rows the voice function makes of the sticker's sentence (the English parser keeps a
    // word's case, so the sticker capitalizes the items).
    spoken: ['Bananen', 'Butter', 'Haferflocken'],
    suggestion: /Joghurt/,
    lists: [['Wocheneinkauf'], ['Baumarkt', 'Schrauben', 'Wandfarbe', 'Pinsel'], ['Geburtstag', 'Luftballons', 'Kerzen']],
  },
  en: {
    stores: { market: 'Farmers market', bakery: 'Bakery', super: 'Supermarket' },
    annaAdds: ['Strawberries', 'Grapes'],
    jonasTypes: 'Coffee',
    typed: '2 Coff',
    spoken: ['Bananas', 'Butter', 'Oats'],
    suggestion: /Coffee/,
    lists: [['Weekly shop'], ['Hardware', 'Screws', 'Wall paint', 'Brush'], ['Birthday', 'Balloons', 'Candles']],
  },
};

const inst = instance();

/** What the production-URL build shows, from app/lib/app/environment.dart (meta.shown). */
const SHOWN = (() => {
  const env = readFileSync(join(repo, 'app/lib/app/environment.dart'), 'utf8');
  const supabase = /_productionUrl = '([^']+)'/.exec(env)?.[1];
  const mcp = /supabaseUrl == _productionUrl\s*\?\s*'([^']+)'/.exec(env)?.[1];
  if (!supabase || !mcp) throw new Error('environment.dart: no production URL or MCP address');
  return { supabase, mcp, api: `${supabase}/functions/v1/api/v1` };
})();
const fg = (args) => execFileSync(join(repo, 'scripts/fg'), args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });

/** A fresh run of the scenario: its members (credentials in memory only) and its seeding moment. */
function seed(scenario) {
  const doc = JSON.parse(fg(['seed', scenario]));
  if (!doc.ok) throw new Error(`fg seed ${scenario}: ${JSON.stringify(doc.error)}`);
  mkdirSync(OUT, { recursive: true });
  appendFileSync(join(OUT, 'runs.txt'), `${doc.run}\n`);
  const manifest = JSON.parse(readFileSync(join(process.env.FG_STATE_DIR, 'runs', `${doc.run}.json`), 'utf8'));
  const members = Object.fromEntries(Object.entries(manifest.users).map(([h, u]) => [h, { ...u, householdId: manifest.households[u.household]?.id }]));
  const household = Object.values(manifest.households)[0].name;
  return { id: doc.run, members, household, seededAt: Math.floor(Date.parse(manifest.createdAt) / 1000) * 1000 };
}

const shared = new Map();
function sharedRun(key, scenario, setup) {
  if (!shared.has(key)) shared.set(key, (async () => {
    const run = seed(scenario);
    await setup?.(run);
    return run;
  })());
  return shared.get(key);
}

// The invite run: the first list renamed and two more with a few items, so the household page
// shows several lists with their open counts.
async function withLists(run, lang) {
  const api = await apiAs(inst, run.members.anna);
  const household = run.members.anna.householdId;
  const { data: first, error } = await api.from('lists').select('id').eq('household_id', household).single();
  if (error) throw error;
  const [[mainName], ...more] = INPUT[lang].lists;
  await must(api.rpc('rename_list', { p_list: first.id, p_name: mainName }));
  for (const [name, ...items] of more) {
    const list = await must(api.rpc('create_list', { p_household: household, p_name: name, p_id: crypto.randomUUID() }));
    for (const item of items) await must(api.from('items').insert({ household_id: household, list_id: list.id, name: item, status: 'active' }));
  }
}

async function must(query) {
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data;
}

/** Jonas's personal access token, made through the RPC the app's „Zugänge“ screen uses. */
async function accessToken(member) {
  const rows = await must((await apiAs(inst, member)).rpc('create_personal_access_token', { p_name: 'Store screenshots' }));
  const token = Object.values(rows[0]).find((v) => String(v).startsWith('fgp_'));
  if (!token) throw new Error('no personal access token');
  return token;
}

const functions = (name) => `${inst.apiUrl}/functions/v1/${name}`;

/** As the Siri Shortcut sends it; English goes with lang en, as the English Siri client sends it. */
async function say(member, text, lang) {
  const res = await fetch(functions('voice'), {
    method: 'POST',
    headers: { authorization: `Bearer ${await accessToken(member)}`, 'content-type': 'application/json' },
    body: JSON.stringify(lang === 'de' ? { text } : { text, lang }),
  });
  if (!res.ok) throw new Error(`voice: ${res.status} ${await res.text()}`);
}

async function assistantAdds(member, names) {
  const res = await fetch(functions('mcp'), {
    method: 'POST',
    headers: { authorization: `Bearer ${await accessToken(member)}`, 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'add_items', arguments: { items: names.map((name) => ({ name })) } } }),
  });
  const text = await res.text();
  if (!res.ok || /"isError":true|"error":/.test(text)) throw new Error(`mcp add_items: ${res.status} ${text}`);
}

const browser = await chromium.launch();
const errors = [];

const PROD = new URL(SHOWN.supabase);
const LOCAL = new URL(inst.apiUrl);
const toLocal = (href, protocol) => Object.assign(new URL(href), { protocol, host: LOCAL.host }).href;
/** Requests and websockets the pages opened to the production host, and those the routes took. */
const production = { seen: [], routed: new Set(), sockets: 0 };

/** Sends everything for the production host to the local stack: requests and the realtime socket. */
async function routeProduction(context) {
  context.on('request', (r) => {
    if (new URL(r.url()).host === PROD.host) production.seen.push(r);
  });
  await context.route((u) => u.host === PROD.host, async (route) => {
    production.routed.add(route.request());
    await route.fulfill({ response: await route.fetch({ url: toLocal(route.request().url(), LOCAL.protocol) }) });
  });
  await context.routeWebSocket((u) => u.host === PROD.host, (ws) => {
    production.sockets++;
    const server = new WebSocket(toLocal(ws.url(), LOCAL.protocol === 'https:' ? 'wss:' : 'ws:'));
    const queue = [];
    server.onopen = () => {
      for (const m of queue.splice(0)) server.send(m);
    };
    server.onmessage = (e) => ws.send(e.data);
    server.onclose = () => ws.close().catch(() => {});
    ws.onMessage((m) => (server.readyState === WebSocket.OPEN ? server.send(m) : queue.push(m)));
    ws.onClose(() => server.close());
  });
}

async function open(run, handle, set, lang, web = inst.webUrl) {
  const [width, height] = SETS[set].viewport;
  const context = await browser.newContext({
    baseURL: web,
    viewport: { width, height },
    deviceScaleFactor: SETS[set].dpr,
    locale: lang === 'en' ? 'en-US' : 'de-DE',
    timezoneId: 'Europe/Berlin',
    colorScheme: 'light',
    reducedMotion: 'no-preference',
    serviceWorkers: 'block',
  });
  await routeProduction(context);
  const page = await context.newPage();
  page.on('websocket', (ws) => {
    if (new URL(ws.url()).host === PROD.host) errors.push(`${set} ${handle}: a websocket to ${PROD.host} was not routed`);
  });
  page.on('pageerror', (e) => errors.push(`${set} ${handle}: ${e.message}`));
  await page.clock.install({ time: run.seededAt });
  await signIn(page, labels(lang), run.members[handle]);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1200);
  await park(page);
  return Object.assign(page, { clockStart: run.seededAt });
}

// Fake requestAnimationFrame fires every 16 ms from the install time: stop on that grid.
async function pause(page) {
  const now = await page.evaluate(() => Date.now());
  await page.clock.pauseAt(page.clockStart + Math.ceil((now + 1000 - page.clockStart) / 16) * 16);
}
const step = (page, ms) => page.clock.runFor(ms);
// The resting pointer: a hover near the right edge shows the web build's scrollbar, which no
// phone has, so it waits in the bottom-left corner, beside the tab bar.
const park = (page) => page.mouse.move(2, page.viewportSize().height - 2);
async function stepUntil(page, locator, settle) {
  const end = Date.now() + 30_000;
  while (!(await locator.isVisible().catch(() => false))) {
    if (Date.now() > end) throw new Error(`${locator} did not show`);
    await step(page, 16);
    await new Promise((r) => setTimeout(r, 15));
  }
  await step(page, settle);
}
// A key restarts the caret's 500 ms blink, so 750 ms later it is off.
async function caretOff(page) {
  await page.keyboard.press('End');
  await step(page, 750);
}

async function box(locator) {
  const b = await locator.boundingBox();
  if (!b) throw new Error(`${locator} has no box`);
  return b;
}

/** Capture-pixel bands of CSS boxes. */
function pixels(page, boxes) {
  const dpr = page.dpr;
  return {
    y: [Math.floor(Math.min(...boxes.map((b) => b.y)) * dpr), Math.ceil(Math.max(...boxes.map((b) => b.y + b.height)) * dpr)],
    x: [Math.floor(Math.min(...boxes.map((b) => b.x)) * dpr), Math.ceil(Math.max(...boxes.map((b) => b.x + b.width)) * dpr)],
  };
}
/** The capture-pixel centre line of each row that must show in honey (compose checks it). */
const centres = (page, boxes) => boxes.map((b) => Math.round((b.y + b.height / 2) * page.dpr));

async function chromeTop(page, L, withAddBar = true) {
  const tops = [(await box(page.getByRole('tablist').last())).y];
  if (withAddBar && (await addField(page, L).isVisible().catch(() => false))) tops.push((await box(addField(page, L))).y);
  return Math.floor(Math.min(...tops) * page.dpr) - 24;
}

/** The category's label in the UI language (the household's categories are stored in German). */
function categoryLabel(name, lang) {
  if (lang === 'de') return name;
  const arb = (l) => JSON.parse(readFileSync(join(repo, `app/l10n/app_${l}.arb`), 'utf8'));
  const de = arb('de');
  const key = Object.keys(de).find((k) => /^category[A-Z]/.test(k) && de[k] === name);
  return key ? arb('en')[key] : name;
}

async function storeId(api, name) {
  return (await must(api.from('stores').select('id').eq('name', name).single())).id;
}

/** The frame of each shot: opens what it needs, ends on a paused clock, returns its meta. */
const SCENES = {
  // Jonas's list 0.8 s after Anna added two items at the market: honey under „2 neu von Anna“.
  list: { fresh: true, async frame({ run, open, L, input }) {
    const page = await open('jonas');
    await pause(page);
    const anna = run.members.anna;
    const api = await apiAs(inst, anna);
    const market = await storeId(api, input.stores.market);
    // One insert each, so the rows have their own created_at and keep their order every run.
    for (const name of input.annaAdds) await must(api.from('items').insert({ household_id: anna.householdId, name, store_id: market, status: 'active' }));
    const strip = page.getByText(L('newItemsFrom', { count: input.annaAdds.length, name: anna.name }));
    await stepUntil(page, strip, 800);
    await caretOff(page);
    const rows = await Promise.all(input.annaAdds.map((n) => box(itemRow(page, n))));
    // The card keeps the strip with the rows it announces.
    return { page, lift: pixels(page, [await box(strip), ...rows]), honey: centres(page, rows), chrome: await chromeTop(page, L) };
  } },

  // Jonas adds coffee from his add sheet, which confirms the store it remembered; Anna's list
  // shows it in honey. The frame is Anna's phone, with Jonas's confirmation lifted out of his.
  sync: { fresh: true, async frame({ run, open, L, input }) {
    const page = await open('anna');
    const jonas = await open('jonas');
    await pause(page);
    await typeInto(addField(jonas, L), input.jonasTypes);
    await jonas.keyboard.press('Enter');
    const sheet = addSheet(jonas, L);
    const confirm = sheet.getByText(L('addedTo', { name: input.jonasTypes, store: input.stores.super }));
    await confirm.waitFor();
    await pause(jonas);
    await caretOff(jonas);
    const text = await box(confirm);
    const undo = await box(jonas.getByRole('button', { name: L('undo'), exact: true }));
    const sheetBox = await box(sheet);
    const top = Math.min(text.y, undo.y) - 6;
    const bottom = Math.max(text.y + text.height, undo.y + undo.height) + 6;
    const sender = { file: 'sync-sender.png', ...pixels(jonas, [{ x: sheetBox.x + 8, y: top, width: sheetBox.width - 16, height: bottom - top }]) };
    await jonas.screenshot({ path: join(page.dir, sender.file) });
    await jonas.context().close();
    await stepUntil(page, page.getByText(L('newItemsFrom', { count: 1, name: run.members.jonas.name })), 300);
    await step(page, 300);
    await caretOff(page);
    const row = await box(itemRow(page, input.jonasTypes));
    return { page, lift: pixels(page, [row]), honey: centres(page, [row]), chrome: await chromeTop(page, L), sender };
  } },

  // „3 Jogh“ typed into the add sheet; the household's past trips suggest „Joghurt · 3“.
  add: { async frame({ open, L, input }) {
    const page = await open('anna');
    await typeInto(addField(page, L), input.typed);
    const sheet = addSheet(page, L);
    await sheet.getByRole('button', { name: input.suggestion }).first().waitFor();
    await page.waitForTimeout(400);
    await pause(page);
    await page.keyboard.press('End');
    await step(page, 300);
    return { page, lift: pixels(page, [await box(sheet)]), chrome: Math.floor(page.viewportSize().height * page.dpr) };
  } },

  // Anpassen → Supermarkt: its categories in walking order, Kühlregal held mid-drag.
  order: { async frame({ open, L, input, lang }) {
    const page = await open('anna');
    const cold = categoryLabel('Kühlregal', lang);
    await page.getByRole('button', { name: L('listEdit') }).click();
    await page.getByRole('button', { name: input.stores.super, exact: true }).click();
    const handle = page.getByText(L('dragCategory', { name: cold }));
    await handle.waitFor();
    await page.waitForTimeout(600);
    const h = await box(handle);
    const [hx, hy] = [h.x + h.width / 2, h.y + h.height / 2];
    await page.mouse.move(hx, hy);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) {
      await page.mouse.move(hx, hy + i * 4.5);
      await page.waitForTimeout(30);
    }
    await page.waitForTimeout(500);
    await pause(page);
    await step(page, 400);
    return { page, lift: pixels(page, [await box(page.getByRole('button', { name: cold, exact: true }))]), chrome: await chromeTop(page, L) };
  } },

  // Anna's list 1.4 s after Jonas said the sentence on the sticker: the voice function splits
  // it, the rows arrive in honey under „3 neu von Jonas“.
  voice: { fresh: true, async frame({ run, open, L, words, lang, input }) {
    const page = await open('anna');
    await foldAbove(page, input);
    await pause(page);
    const said = words.voice.sticker.said;
    await say(run.members.jonas, said, lang);
    return arrived(page, L, run, input.spoken);
  } },

  // Anna's list after Jonas's AI assistant added the sticker's items through the mcp function.
  assist: { fresh: true, async frame({ run, open, L, words, input }) {
    const page = await open('anna');
    await foldAbove(page, input);
    await pause(page);
    const { items } = words.assist.sticker;
    await assistantAdds(run.members.jonas, items);
    return arrived(page, L, run, items);
  } },

  // Zugänge in the production-URL build with the API section on (FLAGS_ON=public-api), no key
  // made: the card is the access tokens and the API, on to the connected apps where it fits; the sticker is
  // the MCP-Server heading and address, cut above the app's hint (it names AI brands).
  api: { fresh: true, web: 'api', async frame({ open, L }) {
    const page = await open('anna');
    await openTab(page, L, 'tabMore');
    await page.getByRole('button', { name: L('accessTitle'), exact: true }).click();
    const apiHeading = page.getByRole('heading', { name: L('apiHeader'), exact: true });
    await apiHeading.waitFor();
    await page.waitForTimeout(800);
    await park(page);
    await pause(page);
    await step(page, 500);
    const mcpHeading = await box(page.getByRole('heading', { name: L('mcpServer'), exact: true }));
    const mcp = page.getByRole('group', { name: new RegExp(`^${SHOWN.mcp.replace(/\./g, '\\.')}`) });
    const mcpTile = await box(mcp);
    const copy = await box(mcp.getByRole('button', { name: L('copy'), exact: true }));
    const create = await box(page.getByRole('button', { name: L('createApiKey'), exact: true }));
    // Where compose looks for the heading and the address (its first lines of text): left of the
    // copy button, from just above the heading to the tile's end.
    const sticker = pixels(page, [{ x: 0, y: mcpHeading.y - 8, width: copy.x - 8, height: mcpTile.y + mcpTile.height - mcpHeading.y + 8 }]);
    return {
      page,
      lift: pixels(page, [await box(apiHeading), create]),
      // The card starts in the MCP-Server tile's bottom padding, below its words (the cut keeps
      // up to 64 px of plain background above the next heading), and may run on to the tab bar.
      floor: Math.ceil((mcpTile.y + mcpTile.height - 8) * page.dpr),
      chrome: await chromeTop(page, L, false),
      sticker,
      texts: await semanticsTexts(page),
      shown: SHOWN,
    };
  } },

  // The household page: members, „Leute einladen“ and three lists. No code, no link.
  invite: { lists: true, async frame({ open, L, run }) {
    const page = await open('anna');
    await openTab(page, L, 'tabMore');
    await page.getByRole('button', { name: new RegExp(`^${run.household}`) }).first().click();
    await page.getByText(L('listsTitle'), { exact: true }).waitFor();
    await page.waitForTimeout(800);
    await park(page);
    await pause(page);
    await step(page, 500);
    const members = await box(page.getByText(L('householdMembersTitle'), { exact: true }));
    const newList = await box(page.getByRole('button', { name: L('listNew'), exact: true }).last());
    // The card may run on into the join requests, and ends before the voice default (it names
    // Siri and Alexa) or the currency, whichever shows first.
    const ends = [];
    for (const key of ['voiceDefaultTitle', 'currencyTitle']) {
      const title = page.getByText(L(key), { exact: true });
      if (await title.isVisible()) ends.push(Math.floor((await box(title)).y * page.dpr) - 8);
    }
    const chrome = Math.min(...ends, await chromeTop(page, L, false));
    return { page, lift: pixels(page, [members, newList]), chrome };
  } },
};

/**
 * Every text the screen reader gets, with its box in capture pixels: compose checks the words
 * inside the card's window (no AI brand, no key, no local host).
 */
async function semanticsTexts(page) {
  const nodes = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => {
    const r = e.getBoundingClientRect();
    const own = [...e.childNodes].filter((n) => n.nodeType === 3 || (n.nodeType === 1 && !n.tagName.startsWith('FLT-SEMANTICS'))).map((n) => n.textContent).join(' ');
    return { text: [e.getAttribute('aria-label'), own].filter(Boolean).join(' ').trim(), y: [r.top, r.bottom], x: [r.left, r.right] };
  }).filter((n) => n.text));
  if (!nodes.length) throw new Error('no semantics texts on the page');
  return nodes.map((n) => ({ text: n.text, y: n.y.map((v) => Math.round(v * page.dpr)), x: n.x.map((v) => Math.round(v * page.dpr)) }));
}

/**
 * Anna has folded the stores above the Supermarkt, where Jonas's adds land (item→store memory),
 * so the card shows the household's name, the „N neu von Jonas“ strip and every new row at once.
 */
async function foldAbove(page, input) {
  for (const store of [input.stores.market, input.stores.bakery]) {
    await page.getByRole('button', { name: new RegExp(`^${store}, `) }).click();
  }
  await page.waitForTimeout(600);
  await park(page);
}

/**
 * The rows Jonas's voice or assistant added, about 1.5 s after the strip announced them (the
 * honey clears after 3 s on screen), checked against the database: exactly the sticker's items,
 * all by Jonas.
 */
async function arrived(page, L, run, names) {
  const strip = page.getByText(L('newItemsFrom', { count: names.length, name: run.members.jonas.name }));
  await stepUntil(page, strip, 100);
  const api = await apiAs(inst, run.members.anna);
  const rows = await must(api.from('items').select('name').eq('added_by', run.members.jonas.id).eq('status', 'active').gt('created_at', new Date(run.seededAt).toISOString()));
  if (rows.map((r) => r.name).sort().join() !== [...names].sort().join()) throw new Error(`expected ${names.join(', ')} from Jonas, found ${rows.map((r) => r.name).join(', ')}`);
  await caretOff(page);
  await step(page, 600);
  if (!(await strip.isVisible())) throw new Error('the strip left before the frame');
  const boxes = await Promise.all(names.map((n) => box(itemRow(page, n))));
  return { page, lift: pixels(page, [await box(strip), ...boxes]), honey: centres(page, boxes), chrome: await chromeTop(page, L) };
}

const arg = (name, fallback) => (process.argv.includes(`--${name}`) ? process.argv[process.argv.indexOf(`--${name}`) + 1] : fallback);
const locales = arg('locales', Object.keys(LOCALES).join(',')).split(',');
const stores = arg('stores', 'play,appstore').split(',');
const assistants = arg('assistants', 'neutral');
const sets = arg('sets', Object.keys(SETS).join(',')).split(',');
const only = arg('shots', '').split(',').filter(Boolean);

const metas = new Map();
for (const { locale, set, shot } of plan({ locales, stores }).filter((p) => sets.includes(p.set) && (!only.length || only.includes(p.shot)))) {
  const { lang, scenario } = LOCALES[locale];
  const L = labels(lang);
  const scene = SCENES[shot];
  const run = scene.fresh
    ? seed(scenario)
    : await sharedRun(`${locale} ${scene.lists ? 'lists' : 'plain'}`, scenario, scene.lists && ((r) => withLists(r, lang)));
  const dir = join(OUT, 'raw', locale, set);
  mkdirSync(dir, { recursive: true });
  const pages = [];
  const web = scene.web === 'api' ? process.env.STORE_SHOTS_API_WEB : inst.webUrl;
  if (!web) throw new Error('the api shot needs STORE_SHOTS_API_WEB, the production-URL build store-screenshots.sh serves');
  const openAs = async (handle) => {
    const page = await open(run, handle, set, lang, web);
    pages.push(page);
    return Object.assign(page, { dpr: SETS[set].dpr, dir });
  };
  const started = Date.now();
  try {
    const { page, ...meta } = await scene.frame({ run, open: openAs, L, lang, input: INPUT[lang], words: captionsFor(locale, { assistants, store: SETS[set].store }) });
    await page.screenshot({ path: join(dir, `${shot}.png`) });
    // A run of some shots keeps the others' meta (--sets, --shots while working on a scene).
    if (!metas.has(dir)) metas.set(dir, existsSync(join(dir, 'meta.json')) ? JSON.parse(readFileSync(join(dir, 'meta.json'), 'utf8')) : {});
    metas.get(dir)[shot] = { raw: `${shot}.png`, ...meta };
    writeFileSync(join(dir, 'meta.json'), `${JSON.stringify(metas.get(dir), null, 1)}\n`);
    console.log(`${locale} ${set} ${shot}: ${((Date.now() - started) / 1000).toFixed(1)} s`);
  } finally {
    for (const p of pages) await p.context().close().catch(() => {});
  }
}
await browser.close();
const leaked = production.seen.filter((r) => !production.routed.has(r));
for (const r of leaked) errors.push(`a request to ${PROD.host} was not routed to the local stack: ${r.method()} ${new URL(r.url()).pathname}`);
console.log(`requests for ${PROD.host}: ${production.seen.length}, all answered by the local stack: ${leaked.length === 0}; websockets routed: ${production.sockets}`);
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
