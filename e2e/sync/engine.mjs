// @ts-check
// fg sync's web driver: runs a parsed sync script (cli/sync_dsl.ts) in N
// isolated browser contexts of one Chromium, each signed in as a household
// member. It captures by itself: a frame of every client after each step and
// whenever any client's screen changes, per-client videos, and a side-by-side
// composite of each frame and of the videos. Usage: node engine.mjs <config.json>
// (written by `fg sync`, mode 600: it holds the seeded passwords). Writes
// <outDir>/result.json; exits 0 when every expectation held, 1 otherwise.
import { chromium } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import process from 'node:process';

const config = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const { baseURL, outDir, viewport, supabaseUrl } = config;
const log = (/** @type {string} */ m) => process.stderr.write(`[sync] ${m}\n`);
const t0 = Date.now();
mkdirSync(`${outDir}/frames/clients`, { recursive: true });
mkdirSync(`${outDir}/videos`, { recursive: true });

/**
 * In the page: watch Flutter's semantics DOM and report the visible state
 * (list rows, checkboxes, chips, text) whenever it changes. The report is the
 * time the frame that changed it was written, so "visible at" has the
 * resolution of one rendered frame.
 */
function observer() {
  let last = '';
  let queued = false;
  const snapshot = () => {
    queued = false;
    const labels = [];
    for (const el of document.querySelectorAll('flt-semantics')) {
      const role = el.getAttribute('role');
      if (role === 'textbox') continue;
      const label = el.getAttribute('aria-label');
      const text = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('').trim();
      const value = label || text;
      if (value) labels.push(`${role ?? ''}|${value}`);
    }
    const digest = labels.join('\u0001');
    if (digest === last) return;
    last = digest;
    globalThis.__fgSnapshot?.({ at: Date.now(), labels });
  };
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    // After this frame's semantics updates are all written.
    queueMicrotask(snapshot);
  }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true, attributeFilter: ['aria-label', 'role'] });
}

/** A label's visible text with its lines joined by spaces, as Playwright's accessible name reads it ("Bananen 6 Von Mia hinzugefügt"). */
const textOf = (/** @type {string} */ label) => label.split('|').slice(1).join('|').replace(/\s+/g, ' ').trim();
/** A list row: a checkbox to assistive tech since job 57 (checked while it leaves). */
const isRow = (/** @type {string} */ label) => label.startsWith('checkbox|');
/**
 * Whether a snapshot satisfies a condition. see/gone match a list row: its
 * text is the given text or starts with it and a space ("Bananen", "Bananen 6").
 * text matches any visible text containing it.
 */
function holds(/** @type {string[]} */ labels, /** @type {{check: string, text: string}} */ c) {
  const want = c.text.replace(/\s+/g, ' ').trim();
  if (c.check === 'text') return labels.some((l) => textOf(l).includes(want));
  const present = labels.some((l) => isRow(l) && (textOf(l) === want || textOf(l).startsWith(`${want} `)));
  return c.check === 'see' ? present : !present;
}

const browser = await chromium.launch({ args: ['--host-resolver-rules=MAP host.docker.internal 127.0.0.1'] });
// fg sync stops the driver with SIGTERM: close the browser first, so no Chromium outlives it.
for (const [sig, code] of [['SIGTERM', 143], ['SIGINT', 130], ['SIGHUP', 129]]) {
  process.on(sig, () => {
    log(`${sig}: closing the browser`);
    browser.close().catch(() => {}).finally(() => process.exit(/** @type {number} */ (code)));
    setTimeout(() => process.exit(/** @type {number} */ (code)), 5000).unref();
  });
}
/** @type {any[]} */
const clients = [];
/** @type {any[]} */
const frames = [];
/** @type {any[]} */
const steps = [];
let ready = false;
let capturing = null;
let pendingCause = null;
// FG_SYNC_NO_CHANGE_FRAMES=1 turns change frames off, to measure what capturing costs the latency.
const MAX_CHANGE_FRAMES = process.env.FG_SYNC_NO_CHANGE_FRAMES ? 0 : config.maxChangeFrames ?? 300;
let changeFrames = 0;

let frameCount = 0;
async function capture(/** @type {string} */ kind, /** @type {string} */ cause, /** @type {number | null} */ step) {
  // Taken before any await: a change capture may overlap a step capture.
  const id = String(++frameCount).padStart(4, '0');
  const at = Date.now();
  const files = {};
  await Promise.all(clients.map(async (c) => {
    const file = `frames/clients/${id}-${c.label}.png`;
    try {
      await c.page.screenshot({ path: `${outDir}/${file}`, animations: 'allow', timeout: 5000 });
      files[c.label] = file;
    } catch (e) {
      files[c.label] = null;
      log(`frame ${id}: ${c.label} screenshot failed: ${e.message.split('\n')[0]}`);
    }
  }));
  const frame = { id, kind, at, ms: at - t0, cause, step, files, composite: `frames/${id}-${kind}.png` };
  frames.push(frame);
  frames.sort((a, b) => a.id.localeCompare(b.id));
  return frame;
}

/** A change in any client captures every client at once; changes during a capture fold into one more capture. */
function onChange(/** @type {string} */ cause) {
  if (!ready || changeFrames >= MAX_CHANGE_FRAMES) return;
  if (capturing) {
    pendingCause = pendingCause ? `${pendingCause}; ${cause}` : cause;
    return;
  }
  changeFrames++;
  capturing = capture('change', cause, steps.length ? steps.length - 1 : null).finally(() => {
    capturing = null;
    if (pendingCause) {
      const next = pendingCause;
      pendingCause = null;
      onChange(next);
    }
  });
}

function diff(/** @type {string[]} */ before, /** @type {string[]} */ after) {
  const b = new Set(before);
  const a = new Set(after);
  const short = (/** @type {string} */ l) => l.split('|').slice(1).join('|').split('\n').slice(0, 2).join(' ');
  const plus = after.filter((l) => !b.has(l) && isRow(l)).map((l) => `+${short(l)}`);
  const minus = before.filter((l) => !a.has(l) && isRow(l)).map((l) => `-${short(l)}`);
  const other = plus.length + minus.length ? [] : ['screen changed'];
  return [...plus, ...minus, ...other].slice(0, 6).join(' ');
}

// Clients ---------------------------------------------------------------------

for (const spec of config.clients) {
  const context = await browser.newContext({
    viewport,
    locale: spec.locale === 'en' ? 'en-US' : 'de-DE',
    timezoneId: 'Europe/Berlin',
    recordVideo: { dir: `${outDir}/videos/raw`, size: viewport },
  });
  const c = { ...spec, context, page: null, snapshots: [], writes: [], offline: false, onlineAt: 0, sockets: new Set(), videoStart: 0 };
  // Every realtime socket runs through the driver, so "offline" can cut the open one, not just new requests.
  // FG_SYNC_DIRECT_WS=1 skips the relay to measure what it adds (offline then cuts only new connections).
  if (!process.env.FG_SYNC_DIRECT_WS) await context.routeWebSocket(new RegExp(`^wss?://${new URL(supabaseUrl).host}/realtime/`), (ws) => {
    if (c.offline) return ws.close({ code: 1006, reason: 'fg sync: offline' });
    ws.connectToServer();
    c.sockets.add(ws);
    ws.onClose(() => c.sockets.delete(ws));
  });
  await context.exposeBinding('__fgSnapshot', (_source, snap) => {
    const before = c.snapshots.at(-1)?.labels ?? [];
    c.snapshots.push(snap);
    onChange(`${c.label}: ${diff(before, snap.labels)}`);
  });
  await context.addInitScript(observer);
  c.videoStart = Date.now();
  c.page = await context.newPage();
  c.page.on('response', (/** @type {any} */ res) => {
    const req = res.request();
    // Item writes only (an add is the put_item RPC, a tick set_item_status): the app also POSTs
    // RPCs (suggest_items) that are no ack of an action.
    const path = new URL(req.url()).pathname;
    const write = path === '/rest/v1/items' || path === '/rest/v1/rpc/put_item' || path === '/rest/v1/rpc/set_item_status';
    if (req.method() !== 'GET' && write && req.url().startsWith(supabaseUrl)) {
      c.writes.push({ at: Date.now(), method: req.method(), path: path.replace('/rest/v1/', ''), status: res.status() });
    }
  });
  c.page.on('pageerror', (/** @type {Error} */ e) => log(`${c.label}: page error ${e.message}`));
  clients.push(c);
}

const byLabel = (/** @type {string} */ l) => clients.find((c) => c.label === l);
const addField = (/** @type {any} */ page) => page.getByRole('textbox', { name: 'Was brauchst du?' });
/** The add sheet (design H): it opens on typing and covers the list until it is closed. */
const addSheet = (/** @type {any} */ page) => page.locator('[flt-semantics-identifier="add-sheet"]');
/**
 * Design H has no store views: shopping at a store folds every other store section and unfolds
 * that one and "Ohne Laden", whose items can be bought anywhere, as the old store view showed them
 * ("Alle" unfolds them all). Folds stay on the device, like the app's own.
 */
async function shopAt(/** @type {import('@playwright/test').Page} */ page, /** @type {string} */ store) {
  // The dividers come with the first sync after sign-in.
  await page.getByRole('button', { name: /^.+, \d+ Artikel/ }).first().waitFor({ timeout: 20_000 });
  for (const divider of await page.getByRole('button', { name: /^.+, \d+ Artikel/ }).all()) {
    // e.g. '- button "Lidl, 3 Artikel" [expanded]'; an empty store has nothing to unfold.
    const [, name = '', count = '0'] = /"(.+), (\d+) Artikel/.exec(await divider.ariaSnapshot()) ?? [];
    const open = /\[expanded\]/.test(await divider.ariaSnapshot());
    if (count !== '0' && open !== (store === 'Alle' || name === store || name === 'Ohne Laden')) await divider.click();
  }
}

const row = (/** @type {any} */ page, /** @type {string} */ name) =>
  page.getByRole('checkbox', { name: new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(\\s|$)`) });

/**
 * Flutter swaps in its own editor on focus: wait for focus, then select all
 * and insert (synthetic key events drop umlauts), then check the value. Same
 * as e2e/tests/helpers.ts typeInto; text sent before focus lands is lost.
 */
async function typeInto(/** @type {any} */ field, /** @type {string} */ text) {
  const page = field.page();
  for (let attempt = 0;; attempt++) {
    await field.click();
    const focused = await field.evaluate((/** @type {Element} */ el) => el === document.activeElement || el.contains(document.activeElement)).catch(() => false);
    if (focused) {
      await page.keyboard.press('ControlOrMeta+a');
      await page.keyboard.insertText(text);
      await page.waitForTimeout(50);
      if ((await field.inputValue().catch(() => '')) === text) return;
    }
    if (attempt === 20) throw new Error(`could not type into ${await field.getAttribute('aria-label').catch(() => 'a field')}`);
    await page.waitForTimeout(250);
  }
}

async function signIn(/** @type {any} */ c) {
  const page = c.page;
  for (let attempt = 1;; attempt++) {
    // The sign-in itself: signed out, `/` is the guided start's first screen (job 168b).
    await page.goto(new URL('/login', baseURL).toString());
    // Builds with Google or Apple keep the email form behind „Weiter mit E-Mail“.
    const withEmail = page.getByRole('button', { name: 'Weiter mit E-Mail' });
    await withEmail.or(page.getByRole('textbox', { name: 'E-Mail' })).waitFor();
    if (await withEmail.isVisible()) await withEmail.click();
    await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), c.email);
    await typeInto(page.getByRole('textbox', { name: 'Passwort' }), c.password);
    // Enter submits from the password field itself, like fg login; a click first moves focus.
    await page.keyboard.press('Enter');
    const land = () => Promise.race([
      addField(page).waitFor({ timeout: 20_000 }).then(() => 'list'),
      page.getByRole('button', { name: 'Haushalt anlegen' }).waitFor({ timeout: 20_000 }).then(() => 'welcome'),
      // Job 19: a new install is asked about analytics right after sign-in; declined here.
      page.waitForURL(/\/analytics-consent(\?|$)/, { timeout: 20_000 }).then(() => 'consent'),
    ]).catch(() => null);
    let landed = await land();
    if (landed === 'consent') {
      // On a small client the answers sit below the text: wheel down to them.
      const decline = page.getByRole('button', { name: 'Nicht erlauben', exact: true });
      await page.getByRole('heading', { name: 'Nutzungsdaten', exact: true }).waitFor({ timeout: 20_000 });
      if (!(await decline.isVisible())) {
        await page.mouse.move(viewport.width / 2, viewport.height / 2);
        for (let i = 0; i < 10 && !(await decline.isVisible()); i++) {
          await page.mouse.wheel(0, 400);
          await page.waitForTimeout(200);
        }
      }
      await decline.click();
      // The URL still says consent until the app moves on; only then look again.
      await page.waitForURL((url) => !url.pathname.startsWith('/analytics-consent'), { timeout: 20_000 })
        .catch(() => null);
      landed = await land();
      if (landed === 'consent') landed = null;
    }
    if (landed) {
      // A returning user has dismissed the Erste Schritte card; it would push the list down.
      const hint = page.getByRole('button', { name: 'Erste Schritte ausblenden', exact: true });
      if (landed === 'list' && (await hint.waitFor({ timeout: 5_000 }).then(() => true, () => false))) await hint.click();
      if (c.store) await shopAt(page, c.store);
      return landed;
    }
    if (attempt === 3) throw new Error(`${c.label} (${c.ref}) did not reach the list or welcome screen after signing in 3 times`);
    log(`${c.label}: sign-in did not land, retrying (${attempt})`);
  }
}

// Steps -----------------------------------------------------------------------

/** Performs one action; returns the moment the user's input was issued (Enter, the tap, Speichern). */
async function act(/** @type {any} */ c, /** @type {any} */ s) {
  const page = c.page;
  switch (s.action) {
    case 'add': {
      await typeInto(addField(page), s.text);
      const at = await issue(() => page.keyboard.press('Enter'));
      // Enter keeps the sheet open for the next item; close it once it confirms ("✓ Hinzugefügt: …",
      // a group with Rückgängig, or "✓ … steht schon auf der Liste", plain text), so this client's
      // list is on screen (and in the observer's snapshots) again. Escape, as e2e/tests/helpers.ts
      // closeSheet does.
      const note = addSheet(page).getByRole('group', { name: /^✓ / }).or(addSheet(page).getByText(/^✓ /));
      await note.waitFor({ timeout: 10_000 });
      await page.keyboard.press('Escape');
      await addSheet(page).waitFor({ state: 'hidden', timeout: 10_000 });
      return at;
    }
    case 'tick':
      // Design H: a tap on the row ticks it.
      return await issue(() => row(page, s.item).first().click());
    case 'edit': {
      // A right click opens the edit sheet (a tap would tick).
      await row(page, s.item).first().click({ button: 'right' });
      const sheet = page.getByRole('group', { name: 'Bearbeiten', exact: true });
      const field = sheet.getByRole('textbox', { name: s.field === 'name' ? 'Bezeichnung' : 'Menge', exact: true });
      await typeInto(field, s.value);
      return await issue(() => sheet.getByRole('button', { name: 'Fertig' }).click());
    }
    case 'store':
      return await issue(() => shopAt(page, s.store));
    case 'offline':
      c.offline = true;
      await c.context.setOffline(true);
      for (const ws of c.sockets) await ws.close({ code: 1006, reason: 'fg sync: offline' }).catch(() => {});
      return Date.now();
    case 'online':
      c.offline = false;
      await c.context.setOffline(false);
      c.onlineAt = Date.now();
      return c.onlineAt;
    case 'reload':
      await page.reload();
      await addField(page).waitFor({ timeout: 30_000 });
      return Date.now();
  }
  throw new Error(`unknown action ${s.action}`);
}

async function issue(/** @type {() => Promise<unknown>} */ input) {
  const at = Date.now();
  await input();
  return at;
}

/**
 * Waits until the condition holds in the client's change log after `since`.
 * Returns when it first held, or null on timeout. A condition that already
 * held at `since` (an absence that was never there) returns already: true,
 * which is no propagation and has no latency.
 */
async function observe(/** @type {any} */ c, /** @type {any} */ cond, /** @type {number} */ since, /** @type {number} */ deadline) {
  const atSince = c.snapshots.filter((/** @type {any} */ x) => x.at <= since).at(-1);
  if (atSince && holds(atSince.labels, cond) && holds(c.snapshots.at(-1).labels, cond)) {
    const changedSince = c.snapshots.some((/** @type {any} */ x) => x.at > since && !holds(x.labels, cond));
    if (!changedSince) return { at: since, already: true };
  }
  for (;;) {
    const current = c.snapshots.at(-1);
    if (current && holds(current.labels, cond)) {
      const first = c.snapshots.find((/** @type {any} */ x) => x.at > since && holds(x.labels, cond)) ?? current;
      return { at: Math.max(first.at, since), already: false };
    }
    if (Date.now() > deadline) return null;
    await new Promise((r) => setTimeout(r, 10));
  }
}

let ok = true;
let lastAction = null;
try {
  log(`signing in ${clients.map((c) => `${c.label}=${c.ref}`).join(', ')}`);
  const screens = await Promise.all(clients.map(signIn));
  clients.forEach((c, i) => (c.screen = screens[i]));
  // Let realtime subscribe and the first resync land before the first step.
  await Promise.all(clients.map((c) => c.page.waitForTimeout(1500)));
  ready = true;
  await capture('step', 'start: all clients signed in', null);

  for (const s of config.steps) {
    const record = { ...s, index: steps.length, startedAt: Date.now(), ok: true };
    steps.push(record);
    log(`line ${s.line}: ${s.source}`);
    try {
      if (s.kind === 'act') {
        const c = byLabel(s.client);
        const writesBefore = c.writes.length;
        record.offlineAtInput = c.offline;
        record.issuedAt = await act(c, s);
        lastAction = { ...record, client: c, writesBefore };
      } else if (s.kind === 'wait') {
        await new Promise((r) => setTimeout(r, s.ms));
      } else if (s.kind === 'screenshot') {
        // The frame below is the screenshot.
      } else if (s.kind === 'expect') {
        const since = lastAction?.issuedAt ?? record.startedAt;
        const deadline = Date.now() + s.withinMs;
        const results = await Promise.all(s.clients.map(async (/** @type {string} */ l) => {
          const seen = await observe(byLabel(l), s, since, deadline);
          return { client: l, visibleAt: seen?.at ?? null, alreadyHeld: seen?.already ?? false };
        }));
        // The server ack: the acting client's first successful write after its input.
        const ack = lastAction?.client.writes.slice(lastAction.writesBefore).find((/** @type {any} */ w) => w.status < 300 && w.at >= lastAction.issuedAt);
        if (ack && lastAction) lastAction.ack = ack;
        // Delivery after a reconnect is catch-up (resync), not live propagation; reported apart, per
        // observer: the action was made offline or is the reconnect itself, or this observer came back since.
        const catchUpFor = (/** @type {string} */ l) =>
          Boolean(lastAction && (lastAction.offlineAtInput || lastAction.action === 'online' || byLabel(l).onlineAt > lastAction.issuedAt));
        record.action = lastAction ? { line: lastAction.line, client: lastAction.client.label, kind: lastAction.action, issuedAt: lastAction.issuedAt, ack: ack ?? null } : null;
        record.observations = results.map((r) => ({
          ...r,
          fromInputMs: r.visibleAt === null || !lastAction || r.alreadyHeld ? null : r.visibleAt - lastAction.issuedAt,
          fromAckMs: r.visibleAt === null || !ack || r.alreadyHeld ? null : r.visibleAt - ack.at,
          catchUp: catchUpFor(r.client),
        }));
        record.catchUp = record.observations.some((/** @type {any} */ o) => o.catchUp);
        const missing = results.filter((r) => r.visibleAt === null).map((r) => r.client);
        if (missing.length) {
          record.ok = false;
          record.error = `${missing.join(',')} did not ${s.check === 'gone' ? 'lose' : 'show'} "${s.text}" within ${s.withinMs} ms`;
        }
      }
    } catch (e) {
      record.ok = false;
      record.error = /** @type {Error} */ (e).message.split('\n')[0];
    }
    if (capturing) await capturing;
    record.endedAt = Date.now();
    const frame = await capture(record.ok ? 'step' : 'failure', `line ${s.line}: ${s.source}${record.ok ? '' : ` FAILED: ${record.error}`}`, record.index);
    record.frame = frame.id;
    if (!record.ok) {
      ok = false;
      log(`FAILED line ${s.line}: ${record.error}`);
      break;
    }
  }
} catch (e) {
  ok = false;
  steps.push({ index: steps.length, kind: 'setup', source: 'sign in', ok: false, error: /** @type {Error} */ (e).message.split('\n')[0] });
  log(`setup failed: ${/** @type {Error} */ (e).message}`);
  await capture('failure', `setup failed: ${/** @type {Error} */ (e).message.split('\n')[0]}`, null).catch(() => {});
}
ready = false;
if (capturing) await capturing;

// Composites --------------------------------------------------------------------

/** Renders each frame's client screenshots side by side with labels and times, in a page of the same browser. */
async function composite() {
  const page = await browser.newPage({ viewport: { width: clients.length * (viewport.width + 16) + 16, height: viewport.height + 140 } });
  const b64 = (/** @type {string} */ f) => readFileSync(`${outDir}/${f}`).toString('base64');
  const time = (/** @type {number} */ at) => new Date(at).toLocaleTimeString('de-DE', { timeZone: 'Europe/Berlin', hour12: false }) + `.${String(at % 1000).padStart(3, '0')}`;
  const esc = (/** @type {string} */ s) => s.replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[ch] ?? ch);
  for (const f of frames) {
    const color = f.kind === 'failure' ? '#b3261e' : f.kind === 'change' ? '#0b57d0' : '#1e1e1e';
    const cols = clients.map((c) => `
      <div class="col">
        <div class="who"><b>${c.label}</b> ${esc(c.name)} <span>${esc(c.ref)}</span></div>
        ${f.files[c.label] ? `<img src="data:image/png;base64,${b64(f.files[c.label])}">` : '<div class="miss">no screenshot</div>'}
      </div>`).join('');
    await page.setContent(`<html><body style="margin:0;font:14px system-ui,sans-serif;background:#f3f3f3">
      <style>.top{padding:10px 16px;color:#fff;background:${color}} .top b{font-size:16px} .row{display:flex;gap:16px;padding:12px 16px}
      .col{width:${viewport.width}px} .who{padding:4px 0 6px} .who span{color:#777;font-size:12px} img{width:${viewport.width}px;border:1px solid #ccc;display:block}
      .miss{height:${viewport.height}px;background:#ddd}</style>
      <div class="top"><b>#${f.id} ${f.kind}</b> &nbsp; ${time(f.at)} &nbsp; +${f.ms} ms<br>${esc(f.cause)}</div>
      <div class="row">${cols}</div></body></html>`);
    await page.screenshot({ path: `${outDir}/${f.composite}`, fullPage: true });
  }
  await page.close();
}

await Promise.all(clients.map((c) => c.context.close()));
const videos = {};
for (const c of clients) {
  const raw = await c.page.video()?.path();
  if (raw) {
    renameSync(raw, `${outDir}/videos/${c.label}.webm`);
    videos[c.label] = `videos/${c.label}.webm`;
  }
}
rmSync(`${outDir}/videos/raw`, { recursive: true, force: true });
await composite().catch((e) => log(`composite frames failed: ${e.message}`));
await browser.close();

/** One video: the clients side by side, aligned to the same wall clock, labelled, with the run time burnt in. */
function compositeVideo() {
  const start = Math.max(...clients.map((c) => c.videoStart));
  const font = config.fontFile ? `fontfile=${config.fontFile}:` : '';
  const inputs = clients.flatMap((c) => ['-ss', ((start - c.videoStart) / 1000).toFixed(3), '-i', `${outDir}/${videos[c.label]}`]);
  const label = (/** @type {any} */ c, /** @type {number} */ i) =>
    `[${i}:v]setpts=PTS-STARTPTS,drawtext=${font}text='${c.label} ${c.name.replace(/[':\\]/g, '')}':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=6[v${i}]`;
  // hstack takes two or more inputs; one client is just its labelled video.
  const joined = clients.length > 1 ? `${clients.map((_, i) => `[v${i}]`).join('')}hstack=inputs=${clients.length},` : '[v0]';
  const stack = `${joined}drawtext=${font}text='+%{pts\\:hms}':x=w-tw-10:y=h-th-10:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=6[out]`;
  const filter = [...clients.map(label), stack].join(';');
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', ...inputs, '-filter_complex', filter, '-map', '[out]', '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '1500k', `${outDir}/videos/composite.webm`], { stdio: ['ignore', 'ignore', 'inherit'] });
  return 'videos/composite.webm';
}

let compositePath = null;
if (Object.keys(videos).length === clients.length) {
  try {
    compositePath = compositeVideo();
  } catch (e) {
    log(`composite video failed: ${/** @type {Error} */ (e).message.split('\n')[0]}`);
  }
}

const result = {
  ok,
  startedAt: new Date(t0).toISOString(),
  durationMs: Date.now() - t0,
  viewport,
  clients: clients.map((c) => ({ label: c.label, ref: c.ref, name: c.name, screen: c.screen ?? null, store: c.store ?? null, video: videos[c.label] ?? null })),
  steps,
  frames,
  changeFrames,
  changeFramesCapped: changeFrames >= MAX_CHANGE_FRAMES,
  compositeVideo: compositePath,
};
writeFileSync(`${outDir}/result.json`, JSON.stringify(result, null, 2));
log(`${ok ? 'passed' : 'FAILED'}: ${steps.length} steps, ${frames.length} frames in ${result.durationMs} ms`);
process.exit(ok ? 0 : 1);
