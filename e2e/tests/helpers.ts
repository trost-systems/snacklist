import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { type BrowserContext, expect, type Locator, type Page } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { Buffer } from 'node:buffer';
import process from 'node:process';
import WebSocket from 'ws';
import { fakeOidcPort, localSecretKey, stack } from '../stack';

export const { url: supabaseUrl, key: publishableKey, mailpit } = stack;
export const functionsUrl = `${supabaseUrl}/functions/v1`;

/**
 * An Edge Function's JSON answer. Anything else fails with the status, the runtime's x-served-by
 * and the body text instead of a bare SyntaxError: the local edge runtime can drop a function's
 * answer and send its own empty 503 (DECISIONS, job 124).
 */
export async function functionJson(res: Response): Promise<ReturnType<typeof JSON.parse>> {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    const servedBy = res.headers.get('x-served-by');
    const body = text === '' ? 'an empty body' : JSON.stringify(text.slice(0, 500));
    throw new Error(
      `${res.url} answered ${res.status}${servedBy ? ` (x-served-by: ${servedBy})` : ''} with ${body}, not JSON`,
    );
  }
}

export const password = 'test-password-123';

/** [value], or fails the test with [what] when it is null or undefined. */
export function must<T>(value: T | null | undefined, what: string): T {
  if (value === null || value === undefined) throw new Error(`no ${what}`);
  return value;
}

/** The first of [rows]; fails the test with [what] when there is none. */
export function firstOf<T>(rows: readonly T[] | null, what: string): T {
  const row = rows?.[0];
  if (row === undefined) throw new Error(`no ${what}`);
  return row;
}

export function newEmail(tag: string): string {
  return `${tag}-${randomUUID().slice(0, 8)}@example.test`;
}

/** A supabase-js client signed in as the given user, for API-level checks. */
export async function apiAs(email: string): Promise<SupabaseClient> {
  const client = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false },
    // Node 20 has no global WebSocket.
    realtime: { transport: WebSocket as never },
  });
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return client;
}

export const addField = (page: Page): Locator => page.getByRole('textbox', { name: 'Was brauchst du?' });
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * A list row, a checkbox (unchecked while open, checked while it leaves); its accessible name is
 * the item name, a space, then the quantity. A row under "Zuletzt verwendet" is a button ending in
 * "Wieder auf die Liste" and is not one (`usedRow`).
 */
export const itemRow = (page: Page, name: string): Locator =>
  page.getByRole('checkbox', { name: new RegExp(`^(?!.* ${usedAction}$)${escape(name)}( |$)`) });

const usedAction = 'Wieder auf die Liste';

/**
 * A ticked item's row under "Zuletzt verwendet" (job 29b): the list's own row, faded, named like
 * it plus "Wieder auf die Liste". A tap puts the item back on the list.
 */
export const usedRow = (page: Page, name: string): Locator =>
  page.getByRole('button', { name: new RegExp(`^${escape(name)}( .*)? ${usedAction}$`) });

/**
 * Puts a ticked item back with a tap on it under "Zuletzt verwendet", the tick's undo since the
 * tick has no snackbar (job 29b); opens the section first if it is closed.
 */
export async function putBack(page: Page, name: string): Promise<void> {
  const section = page.getByRole('button', { name: 'Zuletzt verwendet' });
  await reveal(page, section);
  if (await usedRow(page, name).count() === 0) await section.click();
  await reveal(page, usedRow(page, name));
  await usedRow(page, name).click();
  await expect(itemRow(page, name)).toBeVisible();
}

/**
 * A snackbar with an action (undo): Flutter puts its text in the aria-label of a group, so
 * getByText finds only the screen-reader announcement, an off-screen copy the engine clears
 * after a few hundred milliseconds.
 */
export const actionSnackBar = (page: Page, text: string): Locator => page.getByRole('group', { name: text, exact: true });

/**
 * Where the list's first row starts, below the floating bar (`_Header.extent` in
 * app/lib/list/list_screen.dart): the same in every sync state, and the web has no top inset. Rows
 * scroll on under the bar; one above this line may be hidden behind it.
 */
/**
 * The list's sync indicator (job 161), card or pill: one button whose name starts with the state.
 * On web its text is the button's name, not page text, so getByText would never find it.
 */
export const offlineIndicator = (page: Page): Locator => page.getByRole('button', { name: /^Offline:/ });
export const failingIndicator = (page: Page): Locator => page.getByRole('button', { name: /^Sync gestört:/ });

export const listBarHeight = 68;

/** The list's visible band: from the bar above it to the top of the add bar, 12 px above its field. */
export async function listArea(page: Page): Promise<{ top: number; bottom: number }> {
  const field = await boxOf(addField(page));
  return { top: listBarHeight, bottom: field.y - 12 };
}

/**
 * [target]'s box, or null when it is not in the page (a lazy list has not built it) or not visible.
 * Asked by count first, which waits for the page to answer: a short boundingBox timeout also runs
 * out while the page is busy (a slow CI host, a rebuild after a realtime change), and a row on
 * screen then looked missing, so the list was wheeled away from it blindly.
 */
export async function boxIfBuilt(target: Locator): Promise<{ x: number; y: number; width: number; height: number } | null> {
  if ((await target.count()) === 0) return null;
  return target.boundingBox({ timeout: 5_000 }).catch(() => null);
}

/**
 * Scrolls the list with the mouse wheel until [target] is fully on screen, at least [margin] px
 * inside the list's top and bottom edges. The list builds rows lazily, so a row far off screen is
 * not in the page at all until the list scrolls near it; it is looked for downwards first, then
 * upwards. A row on screen that the list cannot move further in (at its start or end) is as far in
 * as it gets.
 */
export async function reveal(page: Page, target: Locator, margin = 0): Promise<void> {
  const { top, bottom } = await listArea(page);
  await page.mouse.move(must(page.viewportSize(), 'viewport').width / 2, (top + bottom) / 2);
  let lastY: number | undefined;
  for (let i = 0; i < 40; i++) {
    const box = await boxIfBuilt(target);
    const onScreen = box && box.y >= top && box.y + box.height <= bottom;
    if (onScreen && box.y >= top + margin && box.y + box.height <= bottom - margin) return;
    if (onScreen && box.y === lastY) return;
    lastY = box?.y;
    const down = box ? box.y + box.height > bottom - margin : i < 20;
    const step = onScreen ? margin + box.height : 250;
    await page.mouse.wheel(0, down ? step : -step);
    await page.waitForTimeout(150);
  }
  throw new Error(`could not scroll ${target} into view`);
}

/**
 * Ticks an item off: a tap on its row (design H has no check box). The row strikes through and
 * closes for 440 ms before the tick commits, so this waits for the row to go (the tick has no
 * snackbar since job 29b): an add of the same name before then finds the item still on the list.
 */
export async function tick(page: Page, name: string): Promise<void> {
  await reveal(page, itemRow(page, name));
  const rows = await itemRow(page, name).count();
  await itemRow(page, name).click();
  await expect(itemRow(page, name)).toHaveCount(rows - 1);
}

/** A store's divider by its name; its accessible name is "<store>, <n> Artikel". */
export const storeDivider = (page: Page, store: string): Locator =>
  page.getByRole('button', { name: new RegExp(`^${escape(store)}, \\d+ Artikel`) });

/** The edit sheet (job 15): a group whose rect is exactly the sheet's content. */
export const editSheet = (page: Page): Locator => page.getByRole('group', { name: 'Bearbeiten', exact: true });

/** A field of the edit sheet by its label: Bezeichnung, Marke, Menge, Eigenschaften. */
export const editField = (page: Page, label: string): Locator => editSheet(page).getByRole('textbox', { name: label });

/**
 * Flutter web fills a text field's <input> only while it is being edited, so a prefilled value is
 * read after focusing the field.
 */
export async function expectFieldValue(field: Locator, value: string): Promise<void> {
  const page = field.page();
  await expect(async () => {
    await field.click();
    await expect(field).toBeFocused();
    await nextFrames(page);
    await expect(field).toHaveValue(value, { timeout: 2_000 });
  }).toPass({ timeout: 20_000 });
}

/**
 * Passes once `check` does, within `ms` of the time the test runner ran. A live-sync budget
 * measures the app; a host pause inside it stops the runner, Chromium and the stack alike, and a
 * wall-clock deadline would fail on it however fast the app is. Each round is short and counts at
 * most one second, so a pause costs a second of the budget, not all of it.
 */
export async function within(ms: number, check: (timeout: number) => Promise<unknown>): Promise<void> {
  for (let ran = 0; ;) {
    const start = Date.now();
    try {
      await check(250);
      return;
    } catch (error) {
      ran += Math.min(Date.now() - start, 1_000);
      if (ran >= ms) throw error;
    }
  }
}

/** Opens an item's edit sheet with a right click, the web's long-press, scrolling to it first. */
export async function openEdit(page: Page, name: string): Promise<void> {
  await reveal(page, itemRow(page, name));
  await itemRow(page, name).click({ button: 'right' });
  await expect(editSheet(page)).toBeVisible();
}

/** Folds out the store or category chip and picks an option by its name. */
export async function pickInSheet(page: Page, chip: 'Laden' | 'Kategorie', option: string): Promise<void> {
  await editSheet(page).getByRole('button', { name: new RegExp(`^${chip}: `) }).click();
  await editSheet(page).getByRole('button', { name: option, exact: true }).click();
}

/** Presses Fertig and waits for the sheet to close. */
export async function saveEdit(page: Page): Promise<void> {
  await editSheet(page).getByRole('button', { name: 'Fertig' }).click();
  await expect(editSheet(page)).toHaveCount(0);
}

type Point = { x: number; y: number };
type Box = Point & { width: number; height: number };

/** [target]'s bounding box; fails the test when it is not on the page. */
export async function boxOf(target: Locator): Promise<Box> {
  return must(await target.boundingBox(), `bounding box of ${target}`);
}

/**
 * One finger on a phone's browser (job 29c): it lands on the first point, waits [hold] ms, slides
 * through the others in [steps] moves each, and lifts after [pause] ms more. Chromium gets real
 * touch events over CDP. WebKit has no touch driver in Playwright, so it gets the pointer events
 * Safari sends for a finger (`pointerType: 'touch'`), which is what Flutter web listens to:
 * pointerdown on the view, then pointermove and pointerup reaching its global target.
 * [onMove] runs while the finger is still down, after the last move.
 */
export async function finger(
  page: Page,
  points: Point[],
  { hold = 0, steps = 10, pause = 50, onMove }: { hold?: number; steps?: number; pause?: number; onMove?: () => Promise<void> } = {},
): Promise<void> {
  const [start, ...rest] = points;
  if (start === undefined) throw new Error('finger needs a point to land on');
  const path: Point[] = [start];
  let from = start;
  for (const to of rest) {
    for (let s = 1; s <= steps; s++) path.push({ x: from.x + ((to.x - from.x) * s) / steps, y: from.y + ((to.y - from.y) * s) / steps });
    from = to;
  }
  const last = path.at(-1) ?? start;
  if (page.context().browser()?.browserType().name() === 'chromium') {
    const cdp = await page.context().newCDPSession(page);
    const touch = (type: 'touchStart' | 'touchMove' | 'touchEnd', at?: Point) =>
      cdp.send('Input.dispatchTouchEvent', { type, touchPoints: at ? [{ x: at.x, y: at.y, id: 1 }] : [] });
    await touch('touchStart', start);
    await page.waitForTimeout(hold);
    for (const at of path.slice(1)) {
      await touch('touchMove', at);
      await page.waitForTimeout(16);
    }
    await onMove?.();
    await page.waitForTimeout(pause);
    await touch('touchEnd');
    await cdp.detach();
    return;
  }
  const send = (type: string, at: Point) => page.evaluate(([type, x, y]) => {
    const w = window as unknown as { fingerTarget?: Element };
    // A finger's events go to the element it landed on. Once that element leaves the page (the
    // engine rebuilds a row's semantics node when the item lifts), the browser hit-tests again.
    const target = type === 'pointerdown' || !w.fingerTarget?.isConnected ? document.elementFromPoint(x, y) ?? document.body : w.fingerTarget;
    w.fingerTarget = target;
    target.dispatchEvent(new PointerEvent(type, {
      pointerId: 29, pointerType: 'touch', isPrimary: true, bubbles: true, cancelable: true, composed: true,
      clientX: x, clientY: y, button: type === 'pointermove' ? -1 : 0, buttons: type === 'pointerup' ? 0 : 1,
      width: 20, height: 20, pressure: type === 'pointerup' ? 0 : 0.5,
    }));
  }, [type, at.x, at.y] as const);
  await send('pointerdown', start);
  await page.waitForTimeout(hold);
  for (const at of path.slice(1)) {
    await send('pointermove', at);
    await page.waitForTimeout(16);
  }
  await onMove?.();
  await page.waitForTimeout(pause);
  await send('pointerup', last);
}

/** A finger held still on the middle of [target] for 700 ms, then lifted. */
export async function fingerHold(page: Page, target: Locator): Promise<void> {
  const b = await boxOf(target);
  await finger(page, [{ x: b.x + b.width / 2, y: b.y + b.height / 2 }], { hold: 700 });
}

/** A finger swipe to the left across most of [target]'s width, along its middle. */
export async function swipeLeft(page: Page, target: Locator, options: { pause?: number; onMove?: () => Promise<void> } = {}): Promise<void> {
  const b = await boxOf(target);
  const y = b.y + b.height / 2;
  await finger(page, [{ x: b.x + b.width - 30, y }, { x: b.x + 30, y }], options);
}

/** Resolves once the page has drawn two more frames, so Flutter has drawn the frame it had scheduled. */
export async function nextFrames(page: Page): Promise<void> {
  await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
}

/**
 * Holds Flutter's frames back until the returned release runs, and tells how many it held. A key
 * typed while they are held lands before the frame that hands the field's DOM input to the app.
 */
export async function holdFrames(page: Page): Promise<() => Promise<number>> {
  await page.evaluate(() => {
    const w = window as unknown as { __release: () => number };
    const raf = globalThis.requestAnimationFrame.bind(globalThis);
    const held: FrameRequestCallback[] = [];
    globalThis.requestAnimationFrame = (callback) => (held.push(callback), 0);
    w.__release = () => {
      globalThis.requestAnimationFrame = raf;
      return held.splice(0).map((callback) => raf(callback)).length;
    };
  });
  return () => page.evaluate(() => (window as unknown as { __release: () => number }).__release());
}

/**
 * Flutter swaps in its own editor on focus, so focus first, then insert.
 * insertText (not type) because synthetic key events drop umlauts.
 *
 * The DOM focus only asks the app to focus the field; the engine starts
 * listening to the <input> with the next frame's semantics update. Text
 * inserted before that frame is in the DOM but not in the app, and the frame
 * puts the app's value back. That frame comes late under load: the password
 * typed right after a failed sign-in was sent as the old one (job 12b). So
 * wait for the frame before typing, and check the value after the next one.
 */
export async function typeInto(field: Locator, text: string): Promise<void> {
  const page = field.page();
  await expect(async () => {
    await field.click();
    await expect(field).toBeFocused();
    await nextFrames(page);
    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.insertText(text);
    await nextFrames(page);
    await expect(field).toHaveValue(text, { timeout: 2_000 });
  }).toPass({ timeout: 20_000 });
}

/**
 * Opens the email form on the login screen. Builds with Google or Apple keep it behind
 * „Weiter mit E-Mail“ / "Continue with email" (job 70); builds without them show it right away.
 */
export async function openEmailSignIn(page: Page, { button = 'Weiter mit E-Mail', field = 'E-Mail' } = {}): Promise<void> {
  const more = page.getByRole('button', { name: button });
  const email = page.getByRole('textbox', { name: field });
  await expect(more.or(email)).toBeVisible({ timeout: 15_000 });
  if (await more.isVisible()) await more.click();
  await expect(email).toBeVisible();
}

/**
 * Signs up in a fresh browser context, then answers the analytics consent that follows the first
 * sign-in on an install (job 19): declined unless [consent] says otherwise. Ends on onboarding
 * (or its join form for an invite link).
 */
export async function signUp(
  page: Page,
  email: string,
  path = '/',
  { consent = 'decline' }: { consent?: ConsentChoice } = {},
): Promise<void> {
  await page.goto(path);
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();
  await answerConsent(page, consent);
}

/** One finger swipe up the middle of the screen, as touch pointer events (WebKit has no swipe API). */
export async function touchSwipeUp(page: Page): Promise<void> {
  const { width, height } = page.viewportSize() ?? { width: 390, height: 660 };
  await page.evaluate(({ width, height }) => {
    const x = width / 2;
    const from = height * 0.7;
    const target = document.elementFromPoint(x, from) ?? document.body;
    const fire = (type: string, y: number) => target.dispatchEvent(new PointerEvent(type, {
      bubbles: true, composed: true, cancelable: true, pointerId: 7, pointerType: 'touch', isPrimary: true,
      clientX: x, clientY: y, button: 0, buttons: type === 'pointerup' ? 0 : 1, pressure: type === 'pointerup' ? 0 : 0.5,
    }));
    fire('pointerdown', from);
    for (let i = 1; i <= 10; i++) fire('pointermove', from - i * height * 0.04);
    fire('pointerup', from - height * 0.4);
  }, { width, height });
}

export type ConsentChoice = 'accept' | 'decline';

/** The analytics consent screen (job 19), asked once per install right after sign-in. */
export const consentScreen = (page: Page): Locator => page.getByRole('button', { name: 'Erlauben', exact: true });

/**
 * Answers the analytics consent, which a fresh browser context sees after its first sign-in, and
 * waits until the app moved on. Every first sign-in goes through here: the order sign-in,
 * consent, onboarding or list is part of every spec.
 */
export async function answerConsent(page: Page, choice: ConsentChoice = 'decline'): Promise<void> {
  await expect(page).toHaveURL(/\/analytics-consent(\?|$)/);
  const answer = page.getByRole('button', { name: choice === 'accept' ? 'Erlauben' : 'Nicht erlauben', exact: true });
  await expect(page.getByRole('heading', { name: 'Nutzungsdaten' })).toBeVisible();
  // A phone (job 33b): the consent text is longer than an iPhone screen. Scroll as a finger does
  // (no mouse wheel on a phone), then tap the answer.
  if (await page.evaluate(() => matchMedia('(pointer: coarse)').matches)) {
    await expect(async () => {
      if (!(await answer.isVisible())) await touchSwipeUp(page);
      await expect(answer).toBeInViewport({ timeout: 500 });
    }).toPass();
    await answer.tap();
    await expect(page).not.toHaveURL(/\/analytics-consent/);
    return;
  }
  // On a short screen the answers sit below the text: wheel down to them. Only then: the mouse
  // left over the page would hover whatever comes next.
  if (!(await answer.isVisible())) {
    const size = page.viewportSize() ?? { width: 400, height: 800 };
    await page.mouse.move(size.width / 2, size.height / 2);
    await expect(async () => {
      if (!(await answer.isVisible())) await page.mouse.wheel(0, 400);
      await expect(answer).toBeVisible({ timeout: 500 });
    }).toPass();
  }
  await answer.click();
  await expect(page).not.toHaveURL(/\/analytics-consent/);
}

/** What the app sent to PostHog, as the stand-in collector received it. */
export interface Captured {
  event: string;
  uuid: string;
  properties: Record<string, unknown>;
}

/**
 * Answers the e2e build's PostHog host (app/config/e2e.json, a .invalid host) in [context] the way
 * PostHog does for posthog-js (job 44): events (`/e/`, `/batch/`, one or a list, JSON or
 * `data=<base64>`), and flags (`/flags/`) as [flags] says, all off by default; remote config is
 * refused as the app's CSP refuses it in production. It keeps every
 * request: nothing leaves the machine. Any request to a real PostHog host fails the spec through
 * [Collector.leaks].
 */
export async function fakeCollector(
  context: BrowserContext,
  { flags = {} }: { flags?: Record<string, boolean> } = {},
): Promise<Collector> {
  const collector = {
    requests: [] as string[],
    events: [] as Captured[],
    leaks: [] as string[],
    bodies: [] as string[],
  };
  await context.route('https://posthog.invalid/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    collector.requests.push(`${request.method()} ${path}`);
    if (path.startsWith('/array/')) {
      // posthog-js' remote config: in production it comes from eu-assets.i.posthog.com, which the
      // app's CSP (vercel.json) does not allow, so it never loads; the same here.
      await route.abort('blockedbyclient');
      return;
    }
    let body = '{"status":1}';
    if (request.method() === 'POST') {
      const raw = request.postData() ?? '';
      collector.bodies.push(raw);
      if (path.startsWith('/flags')) {
        body = JSON.stringify({
          flags: Object.fromEntries(Object.entries(flags).map(([key, enabled]) => [key, { key, enabled }])),
          featureFlags: flags,
          errorsWhileComputingFlags: false,
        });
      } else {
        collector.events.push(...decodeEvents(raw));
      }
    }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST, GET, OPTIONS',
        'access-control-allow-headers': 'content-type',
      },
      body,
    });
  });
  await context.route(/^https:\/\/([a-z0-9-]+\.)*posthog\.com\//, async (route) => {
    collector.leaks.push(route.request().url());
    await route.abort();
  });
  return collector;
}

/** The events in one capture request body: JSON or `data=<base64 JSON>`, one event or a list. */
function decodeEvents(raw: string): Captured[] {
  const text = raw.startsWith('data=')
    ? Buffer.from(decodeURIComponent(raw.slice(5)), 'base64').toString('utf8')
    : raw;
  const parsed = JSON.parse(text) as Captured | Captured[] | { batch: Captured[] };
  if (Array.isArray(parsed)) return parsed;
  if ('batch' in parsed) return parsed.batch;
  return [parsed];
}

export type Collector = { requests: string[]; events: Captured[]; leaks: string[]; bodies: string[] };

/** The names of what [collector] received, in order. */
export const eventNames = (collector: Collector): string[] => collector.events.map((e) => e.event);

/** Signs up, creates a household with [stores] (none by default, see [createHousehold]) and goes on to the list. */
export async function signUpWithHousehold(page: Page, email: string, { stores }: { stores?: string[] } = {}): Promise<void> {
  await signUp(page, email);
  await createHousehold(page, { stores });
  await skipInvite(page);
}

/** Onboarding's store offer (app/lib/household/popular_stores.dart). */
export const popularStores = ['EDEKA', 'REWE', 'Lidl', 'Aldi Süd', 'Aldi Nord', 'Kaufland', 'Netto', 'Penny', 'dm', 'Rossmann', 'Baumarkt'];

/**
 * The chains with a researched walking order, for specs that test chain behaviour (layouts, dm's
 * hidden categories, brand defaults such as Pampers -> dm).
 */
export const chainStores = ['dm', 'Lidl', 'EDEKA'];

/**
 * Onboarding (job 22) from Step 1: "Haushalt erstellen", then Step 2a with [name] (the prefilled
 * "Unser Haushalt" by default) and [stores], picked in order; a name not on the offer is typed as
 * an own store. The default is none, as in the app, where nothing is preselected: "Überspringen".
 * Specs that only need some store type generic ones (Supermarkt, Drogerie); [chainStores] are for
 * chain behaviour. Ends on Step 3, inviting the partner.
 */
export async function createHousehold(
  page: Page,
  { name, stores = [] }: { name?: string; stores?: string[] | undefined } = {},
): Promise<void> {
  await expect(page).toHaveURL(/\/welcome(\?|$)/);
  await page.getByRole('button', { name: /^Haushalt erstellen/ }).click();
  await expect(page).toHaveURL(/\/welcome\/create(\?|$)/);
  // The prefilled name is not in the DOM until the field is edited, so it is not checked here.
  const field = page.getByRole('textbox', { name: 'Name des Haushalts' });
  await expect(field).toBeVisible();
  if (name !== undefined) await typeInto(field, name);
  for (const store of stores) {
    if (popularStores.includes(store)) {
      await page.getByRole('checkbox', { name: store, exact: true }).or(page.getByRole('button', { name: store, exact: true }))
        .click();
    } else {
      await page.getByRole('button', { name: 'Eigenen Laden hinzufügen' }).click();
      await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), store);
      await page.keyboard.press('Enter');
      await expect(page.getByRole('textbox', { name: 'Name des Ladens' })).toHaveCount(0);
    }
  }
  if (stores.length === 0) await page.getByRole('button', { name: 'Überspringen', exact: true }).click();
  else await page.getByRole('button', { name: 'Haushalt erstellen', exact: true }).click();
  await expect(page).toHaveURL(/\/welcome\/invite$/);
}

/** Onboarding Step 3's "Später" (or "Weiter zur Liste" once invited): on to the list, its add field focused. */
export async function skipInvite(page: Page): Promise<void> {
  await page.getByRole('button', { name: /^(Später|Weiter zur Liste)$/ }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(addField(page)).toBeFocused();
}

/**
 * The household name the join screen shows for a good code. Its card is one text node on the web:
 * "Einladung in den Haushalt Familie Trost".
 */
export const invitePreview = (page: Page, household: string): Locator =>
  page.getByText(new RegExp(`Einladung in den Haushalt\\s*${escape(household)}$`));

/**
 * Joins with a typed [code] (job 22): from Step 1 ("Einladung annehmen") or the join screen, type,
 * "Weiter", see the household's name, "Haushalt beitreten". Ends on the list.
 */
export async function joinWithCode(page: Page, code: string, household?: string): Promise<void> {
  if (/\/welcome(\?|$)/.test(new URL(page.url()).pathname)) {
    await page.getByRole('button', { name: /^Einladung annehmen/ }).click();
  }
  await expect(page).toHaveURL(/\/join(\?|\/|$)/);
  await typeInto(page.getByRole('textbox', { name: 'Einladungscode' }), code);
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await confirmJoin(page, household);
}

/** On the join screen with a previewed code: "Haushalt beitreten", then the list. */
export async function confirmJoin(page: Page, household?: string): Promise<void> {
  const join = page.getByRole('button', { name: 'Haushalt beitreten', exact: true });
  await expect(join).toBeVisible();
  if (household) await expect(invitePreview(page, household)).toBeVisible();
  await join.click();
  await expect(page).toHaveURL(/\/$/);
  await expect(addField(page)).toBeVisible();
}

/** The household chip top left of the list (job 169b), named after the household it shows. */
export const householdChip = (page: Page, household: string): Locator =>
  page.getByRole('button', { name: new RegExp(`^${escape(household)}(\\s|$)`) });

/** The switcher sheet's row of [household]: "Familie Trost 2 Mitglieder · 1 offen". */
export const householdRow = (page: Page, household: string): Locator =>
  page.getByRole('button', { name: new RegExp(`^${escape(household)}\\s+\\d+ Mitglied`) });

/** Opens the switcher sheet ("Deine Haushalte") from the chip of the [shown] household. */
export async function openHouseholds(page: Page, shown: string): Promise<void> {
  await householdChip(page, shown).click();
  await expect(page.getByRole('heading', { name: 'Deine Haushalte' })).toBeVisible();
}

/** Shows [to] on this device through the switcher, from the [shown] household's list. */
export async function switchHousehold(page: Page, shown: string, to: string): Promise<void> {
  await openHouseholds(page, shown);
  await householdRow(page, to).click();
  await expect(page.getByRole('heading', { name: 'Deine Haushalte' })).toHaveCount(0);
  await expect(householdChip(page, to)).toBeVisible();
}

/** The add sheet (job 17): a group whose rect is the sheet's content, open while adding. */
export const addSheet = (page: Page): Locator => page.getByRole('group', { name: 'Hinzufügen', exact: true });

/**
 * The sheet's line about the last add, as shown: "✓ Hinzugefügt: Milch → Lidl" (with Rückgängig)
 * or "Butter steht schon auf der Liste". Any such line by default.
 */
export const addedNote = (page: Page, line: string | RegExp = /^✓ Hinzugefügt: | steht schon auf der Liste$/): Locator =>
  addSheet(page).getByText(line, { exact: true });

/**
 * Types [text] and presses Enter, which takes the sheet's first suggestion (the server's reading
 * of the text), and waits for the sheet to say so. The sheet stays open for the next item, the
 * field focused, and the list behind the scrim out of reach: see [addItem].
 */
export async function enterItem(page: Page, text: string): Promise<void> {
  // Text inserted during the tap that opens the sheet lands in the DOM input but not in the app
  // (seen in job 17), so the sheet opens first.
  await addField(page).click();
  await expect(addSheet(page)).toBeVisible();
  await typeInto(addField(page), text);
  // The row for what was typed shows once the app has the text.
  await expect(addSheet(page).getByRole('button', { name: /, Wie getippt(,|$)/ })).toBeVisible();
  await page.keyboard.press('Enter');
  // First: a duplicate hint (job 32b, "Möhren steht schon auf der Liste") may follow the line.
  await expect(addedNote(page).first()).toBeVisible();
}

/**
 * Closes the add sheet with Escape in the field, which hands the list back. Not the Schließen
 * button: after it, the next tap on the field shows a cursor but drops what is typed (job 17,
 * reported to the lead).
 */
export async function closeSheet(page: Page): Promise<void> {
  await expect(addField(page)).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(addSheet(page)).toHaveCount(0);
}

/** Adds one item with Enter and closes the sheet, so the list is in reach again. */
export async function addItem(page: Page, text: string): Promise<void> {
  await enterItem(page, text);
  await closeSheet(page);
}

/** Switches tabs: a bottom bar on phones, a rail ("Mehr Tab 2 von 2") from 840 px. */
export async function openTab(page: Page, tab: 'Liste' | 'Mehr'): Promise<void> {
  await page.getByRole('tab', { name: tab, exact: true }).or(page.getByRole('button', { name: `${tab} Tab ` })).click();
}

/**
 * Wheels More's lazy list until [target] is fully on screen above the tab bar. The list keeps its
 * scroll position between visits, and an entry far off screen is not built at all, so a click alone
 * can wait forever.
 */
export async function wheelTo(page: Page, target: Locator): Promise<void> {
  const size = must(page.viewportSize(), 'viewport');
  // From 840 px there is no tab bar (a rail): don't wait for one.
  const tabs = await page.getByRole('tab', { name: /^(Liste|List)$/ }).boundingBox({ timeout: 200 }).catch(() => null);
  const bottom = tabs ? tabs.y : size.height;
  // From 840 px More's list is the 360 px pane on the left.
  await page.mouse.move(size.width >= 840 ? 180 : size.width / 2, size.height / 3);
  for (let i = 0; i < 40; i++) {
    const box = await boxIfBuilt(target);
    if (box && box.y >= 0 && box.y + box.height <= bottom) return;
    const down = box ? box.y + box.height > bottom : i < 20;
    await page.mouse.wheel(0, down ? 250 : -250);
    await page.waitForTimeout(150);
  }
  throw new Error(`could not scroll ${target} into view`);
}

/** Opens an entry of the More tab by its title ("Partner einladen", "Zugänge", "Abmelden" …). */
export async function openMore(page: Page, entry: string): Promise<void> {
  await openTab(page, 'Mehr');
  // The tab comes back to the page it was left on; a second tap goes to its first page, More's list.
  await expect(page).toHaveURL(/\/more\b/);
  if (new URL(page.url()).pathname !== '/more') await openTab(page, 'Mehr');
  await expect(page).toHaveURL(/\/more$/);
  const target = page.getByRole('button', { name: new RegExp(`^${escape(entry)}( |$)`) });
  await wheelTo(page, target);
  await target.click();
}

/**
 * The Hummlist Premium page by its link (`/more/lifetime`), the way the integration settings open
 * it: More lists it only once Premium may be offered or the household has it (job 64), and the
 * switch `premium_offer` is off on the e2e stack.
 */
export async function openPremium(page: Page): Promise<void> {
  await page.goto('/more/lifetime');
  await expect(page).toHaveURL(/\/more\/lifetime$/);
  await expect(page.getByText('Hummlist Premium', { exact: true }).first()).toBeVisible({ timeout: 15_000 });
}

const inviteCode = /^Code [A-HJ-NP-Z2-9]{8}$/;

/** Invite cards' code labels ("Code ABCD2345"), or the one for [code]. */
export const inviteCodeLabel = (page: Page, code?: string): Locator => {
  const name = code === undefined ? inviteCode : `Code ${code}`;
  return page.getByRole('group', { name }).or(page.getByText(name, { exact: true }));
};

/** The codes the invite cards on screen show, top to bottom. */
export async function shownInviteCodes(page: Page): Promise<string[]> {
  const codes: string[] = [];
  for (const label of await inviteCodeLabel(page).all()) {
    const text = (await label.getAttribute('aria-label')) ?? (await label.textContent()) ?? '';
    const code = text.trim().split(/\s+/)[1];
    if (code && !codes.includes(code)) codes.push(code);
  }
  return codes;
}

/**
 * Makes a new invite under More, Partner einladen (Einladungen, job 22), reads its code, then returns
 * to the list.
 */
export async function createInviteCode(page: Page): Promise<string> {
  await openMore(page, 'Partner einladen');
  await expect(page).toHaveURL(/\/more\/invites$/);
  await expect(page.getByText('Keine offenen Einladungen.').or(inviteCodeLabel(page).first())).toBeVisible();
  const before = await shownInviteCodes(page);
  await page.getByRole('button', { name: 'Neue Einladung' }).click();
  let created: string | undefined;
  await expect.poll(async () => (created = (await shownInviteCodes(page)).find((c) => !before.includes(c))))
    .toBeTruthy();
  await openTab(page, 'Liste');
  return must(created, 'new invite code');
}

export async function screenshot(page: Page, name: string): Promise<void> {
  const dir = process.env.SCREENSHOT_DIR;
  if (!dir) return;
  mkdirSync(dir, { recursive: true });
  // Flutter animates on its canvas, out of reach of Playwright's animation
  // controls, so wait until two frames agree (a chip that was just tapped
  // fades for ~200 ms).
  let previous = await page.screenshot();
  for (let attempt = 0; attempt < 20; attempt++) {
    await page.waitForTimeout(100);
    const current = await page.screenshot();
    if (current.equals(previous)) break;
    previous = current;
  }
  writeFileSync(`${dir}/${name}.png`, previous);
}

/** The newest sign-in link Mailpit holds for `email`. */
export async function latestLinkFor(email: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const res = await fetch(`${mailpit}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
    const { messages } = await res.json() as { messages: { ID: string }[] };
    const [newest] = messages;
    if (newest !== undefined) {
      const message = await (await fetch(`${mailpit}/api/v1/message/${newest.ID}`)).json() as { Text: string };
      const link = message.Text.match(/https?:\/\/\S+\/auth\/v1\/verify\S+/)?.[0];
      if (link) return link;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`no magic link mail for ${email}`);
}

/** The local stack's service client, for setup no user may do (backdated history). */
export function adminClient(): SupabaseClient {
  return createClient(supabaseUrl, localSecretKey(), {
    auth: { persistSession: false },
    realtime: { transport: WebSocket as never },
  });
}

/** A supabase-js client with no session. */
export function anonClient(): SupabaseClient {
  return createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false },
    realtime: { transport: WebSocket as never },
  });
}

export async function fakeIdToken(claims: {
  email: string; nonce?: string; aud?: string; emailVerified?: boolean; name?: string;
}): Promise<string> {
  const res = await fetch(`http://127.0.0.1:${fakeOidcPort}/mint`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(claims),
  });
  return ((await res.json()) as { id_token: string }).id_token;
}

/**
 * Sends the app's next Google or Apple redirect to the fake provider as
 * `email`, or has the user cancel there. Only the provider name changes, so
 * the app's PKCE flow and Supabase's callback, code exchange and account
 * linking all run for real. Supabase passes extra authorize parameters on to
 * the provider, which reads the account from login_hint.
 */
export async function viaFakeProvider(page: Page, email: string, { cancel = false } = {}): Promise<void> {
  await page.route((url) => url.href.startsWith(`${supabaseUrl}/auth/v1/authorize?`), async (route) => {
    const url = new URL(route.request().url());
    url.searchParams.set('provider', 'keycloak');
    url.searchParams.set('login_hint', email);
    if (cancel) url.searchParams.set('deny', '1');
    await route.fulfill({ status: 302, headers: { location: url.href } });
  });
}

/** Cuts the page off from Supabase (HTTP and realtime); the app itself still loads. */
export async function cutOff(page: Page): Promise<{ restore: () => Promise<void> }> {
  let offline = true;
  const http = `${supabaseUrl}/**`;
  await page.route(http, (route) => route.abort());
  await page.routeWebSocket(new RegExp(`^ws://${new URL(supabaseUrl).host}/`), (ws) => {
    if (offline) ws.close();
    else ws.connectToServer();
  });
  return {
    restore: async () => {
      offline = false;
      await page.unroute(http);
    },
  };
}
