// Today's ST3 block in the real app (release web build, verify-snacklist instance): Peter's list of t1116u,
// five groups (dm, Lidl, Edeka, IKEA, no store), in the round's four states. It screenshots the list's end and
// writes every semantics node's box there, which calibrates the round's Today replica (today.json).
//
//   node docs/design/totals/tools/capture-today.mjs <out dir> [--lang en|de] [--dark] [--scale 3.1] [--android] [--tall]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, instance, itemRow, member, openApp, reveal, signIn } from '../../../../.claude/skills/verify-snacklist/helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'en');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
const android = rest.includes('--android');
// --tall: a 3000 px high window, so a block taller than the phone is measured whole.
const tall = rest.includes('--tall');
if (!dir) throw new Error('usage: capture-today.mjs <out dir> [--lang en|de] [--dark] [--scale 3.1] [--android] [--tall]');
mkdirSync(dir, { recursive: true });

const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();

async function storeId(name) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  const found = data.find((s) => s.name === name)?.id;
  if (found) return found;
  const { data: id, error: e } = await api.rpc('add_store', { p_household: household, p_name: name });
  if (e) throw e;
  return id;
}
const ids = {};
for (const s of ['dm', 'Lidl', 'Edeka', 'IKEA']) ids[s] = await storeId(s);
// The household's store order: dm, Lidl, Edeka, IKEA, as in Peter's screenshot.
['dm', 'Lidl', 'Edeka', 'IKEA'].forEach((s, i) => sql(`update public.stores set sort_order = ${i} where id = '${ids[s]}'`));

const de = lang === 'de';
const mine = [
  [de ? 'Zahnpasta' : 'Toothpaste', 'dm', null, 145],
  [de ? 'Milch' : 'Milk', 'Lidl', '2', 119],
  [de ? 'Bananen' : 'Bananas', 'Lidl', '846 g', 179, 'kg'],
  [de ? 'Brot' : 'Bread', 'Edeka', null, 249],
  [de ? 'Butter' : 'Butter', 'Edeka', null, 229],
  [de ? 'Teelichter' : 'Tealights', 'IKEA', null, 399],
  [de ? 'Batterien' : 'Batteries', null, null, 499],
];
// Which items carry a price in each state (b and d: Lidl in full, Edeka's bread; c: all).
const priced = { a: [], b: [1, 2, 3], c: [0, 1, 2, 3, 4, 5, 6], d: [1, 2, 3] };
const names = mine.map(([n]) => `'${n}'`).join(',');
const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
const reset = async () => {
  for (const id of sql(`select id from public.trip_sessions where household_id = '${household}'`).split('\n').filter(Boolean)) {
    await api.rpc('delete_trip_session', { p_id: id });
  }
  sql(`delete from public.items where household_id = '${household}' and name in (${names})`);
};
await reset();
sql(`update public.items set status = 'bought', bought_at = now() - interval '1 day', bought_by = '${mia.id}' where household_id = '${household}' and status = 'active'`);

const viewport = { width: android ? 360 : 390, height: tall ? 3000 : android ? 640 : 844 };
const tag = `${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}${android ? '-android' : ''}${tall ? '-tall' : ''}`;
const out = {};
const { browser, page, L } = await openApp(inst, { lang, dark, viewport });
const toEnd = async () => {
  await page.mouse.move(viewport.width / 2, viewport.height / 3);
  for (let i = 0; i < 4; i += 1) {
    await page.mouse.wheel(0, 20_000);
    await page.waitForTimeout(400);
  }
  await page.mouse.move(1, 1);
  await page.waitForTimeout(800);
};
const nodes = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => {
  const r = n.getBoundingClientRect();
  return { role: n.getAttribute('role'), label: n.getAttribute('aria-label') ?? '', text: n.childElementCount ? '' : n.textContent ?? '', top: r.top, bottom: r.bottom, left: r.left, right: r.right };
}).filter((n) => n.bottom > n.top && (n.label || n.text)));
try {
  await signIn(page, L, mia);
  // After signing in: at large text the analytics question's buttons sit below the fold. Flutter web follows a live change.
  const big = () => page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  for (const state of ['a', 'b', 'c', 'd']) {
    await reset();
    const now = new Date().toISOString();
    for (const [i, [name, store, quantity, cents, per]] of mine.entries()) {
      const p = priced[state].includes(i) ? { price_unit_micros: cents * 10_000, price_basis: 'unit', price_per: per ?? 'piece', price_currency: 'EUR', priced_at: now } : {};
      const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name, store_id: store ? ids[store] : null, quantity, ...p });
      if (error) throw error;
    }
    await page.reload();
    await big();
    await itemRow(page, mine[0][0]).waitFor({ timeout: 20_000 });
    if (state === 'd') {
      // Lidl bought in full and Edeka's bread, on a running trip.
      await reveal(page, itemRow(page, mine[1][0]));
      // On the name, not the middle: at large text the middle is the price chip.
      await itemRow(page, mine[1][0]).click({ position: { x: 70, y: 16 } });
      await page.getByRole('button', { name: L('shopAskYes'), exact: true }).click({ timeout: 8_000 });
      await page.waitForTimeout(1500);
      for (const i of [2, 3]) {
        await reveal(page, itemRow(page, mine[i][0]));
        await itemRow(page, mine[i][0]).click({ position: { x: 70, y: 16 } });
        await page.waitForTimeout(2500);
      }
    }
    await toEnd();
    out[state] = await nodes();
    await page.screenshot({ path: join(dir, `${tag}-${state}.png`) });
    console.log(`${tag} ${state}: captured`);
  }
} finally {
  await browser.close();
  await reset();
}
writeFileSync(join(dir, `${tag}.json`), JSON.stringify(out, null, 1));
