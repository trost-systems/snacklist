// Today in the real app (release web build, verify-snacklist instance): the round's mock list (EDEKA, IKEA, no store)
// put into the seeded household. It records which category the classifier gives each name (today.json `cats`), the
// order the list shows, how many item rows the first screen shows whole, a screenshot of the top, of IKEA and of the
// edit sheet. The round's Today replica is checked against these numbers.
//
//   node docs/design/order/tools/capture-today.mjs <out dir> [--lang en|de] [--dark] [--scale 3.1] [--android]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, instance, itemRow, member, openApp, reveal, signIn } from '../../../../.claude/skills/verify-snacklist/helpers/lib.mjs';
import { items } from '../model.js';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'en');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
const android = rest.includes('--android');
if (!dir) throw new Error('usage: capture-today.mjs <out dir> [--lang en|de] [--dark] [--scale 3.1] [--android]');
mkdirSync(dir, { recursive: true });

const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();

const storeIds = {};
for (const name of ['EDEKA', 'IKEA']) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  storeIds[name] = data.find((s) => s.name === name)?.id;
  if (!storeIds[name]) {
    const { data: id, error: e } = await api.rpc('add_store', { p_household: household, p_name: name });
    if (e) throw e;
    storeIds[name] = id;
  }
}
// EDEKA first, IKEA second, any other store of the seed after them.
sql(`update public.stores set sort_order = 100 where household_id = '${household}'`);
sql(`update public.stores set sort_order = 0 where id = '${storeIds.EDEKA}'`);
sql(`update public.stores set sort_order = 1 where id = '${storeIds.IKEA}'`);

// The German names: the classifier's dictionary is German, and an English household's items are typed in English, so
// both languages seed their own names and the categories are read back for each.
const name = (i) => i[lang];
const names = items.map((i) => `'${name(i).replace(/'/g, "''")}'`).join(',');
const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
const reset = () => sql(`delete from public.items where household_id = '${household}' and name in (${names})`);
reset();
sql(`update public.items set status = 'bought', bought_at = now() - interval '1 day', bought_by = '${mia.id}' where household_id = '${household}' and status = 'active'`);
for (const i of items) {
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name: name(i), store_id: i.store ? storeIds[i.store === 'edeka' ? 'EDEKA' : 'IKEA'] : null, quantity: i.qty || null });
  if (error) throw error;
  // One by one, so created_at (the order inside a category) is the model's order of adding.
  await new Promise((r) => setTimeout(r, 30));
}
const cats = Object.fromEntries(sql(`select i.name || '|' || coalesce(c.seed_key, c.name) from public.items i join public.categories c on c.id = i.category_id where i.household_id = '${household}' and i.status = 'active' and i.name in (${names})`).split('\n').map((l) => l.split('|')));
const catsById = Object.fromEntries(items.map((i) => [i.id, cats[name(i)] ?? null]));

const viewport = { width: android ? 360 : 390, height: android ? 640 : 844 };
const tag = `${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}${android ? '-android' : ''}`;
const { browser, page, L } = await openApp(inst, { lang, dark, viewport });
const nodes = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => {
  const r = n.getBoundingClientRect();
  const own = [...n.childNodes].filter((c) => c.nodeType === 3).map((c) => c.textContent).join('').trim();
  return { role: n.getAttribute('role') ?? (n.querySelector(':scope > h1, :scope > h2, :scope > h3') ? 'heading' : null), label: n.getAttribute('aria-label') || own || n.querySelector(':scope > h1, :scope > h2, :scope > h3')?.textContent || '', top: r.top, bottom: r.bottom, left: r.left, right: r.right };
}).filter((n) => n.bottom > n.top && n.label));
const out = { lang, scale, android, viewport, cats: catsById };
try {
  await signIn(page, L, mia);
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await page.reload();
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await itemRow(page, name(items[0])).waitFor({ timeout: 20_000 });
  await page.waitForTimeout(1200);
  const top = await nodes();
  const field = await page.getByRole('textbox', { name: L('addFieldHint') }).boundingBox();
  const bar = top.filter((n) => n.role === 'button' && /·/.test(n.label)).map((n) => n.bottom);
  const rows = top.filter((n) => n.role === 'checkbox');
  const barBottom = Math.max(0, ...bar);
  const fieldTop = field.y;
  out.top = top;
  out.barBottom = barBottom;
  out.fieldTop = fieldTop;
  out.visibleRows = rows.filter((n) => n.top >= barBottom - 1 && n.bottom <= fieldTop + 1).map((n) => n.label);
  await page.screenshot({ path: join(dir, `${tag}-top.png`) });
  // The whole order as the list draws it: scroll through and collect the rows' and dividers' names.
  const seen = [];
  for (let k = 0; k < 30; k += 1) {
    for (const n of await nodes()) {
      const key = `${n.role}:${n.label || n.text}`;
      if ((n.role === 'checkbox' || n.role === 'heading' || /^(EDEKA|IKEA|No store|Ohne Laden),/.test(n.label)) && !seen.includes(key)) seen.push(key);
    }
    if (scale === 1 && [3, 6].includes(k)) await page.screenshot({ path: join(dir, `${tag}-scroll-${k}.png`) });
    await page.mouse.move(viewport.width / 2, viewport.height / 2);
    await page.mouse.wheel(0, viewport.height / 3);
    await page.waitForTimeout(250);
  }
  out.order = seen;
  writeFileSync(join(dir, `${tag}.json`), JSON.stringify(out, null, 1));
  // IKEA and the edit sheet: only at 100 %, where the round's frames compare with them.
  if (scale === 1) {
  await page.mouse.move(viewport.width / 2, viewport.height / 3);
  // Back to the top, then down to IKEA's last row so its section fills the screen.
  for (let k = 0; k < 20; k += 1) await page.mouse.wheel(0, -2000);
  await reveal(page, itemRow(page, name(items.find((i) => i.id === 'shelf'))));
  await page.waitForTimeout(500);
  await page.screenshot({ path: join(dir, `${tag}-ikea.png`) });
  // The edit sheet of Eggs: a hold opens it.
  const eggs = itemRow(page, name(items.find((i) => i.id === 'eggs')));
  await page.mouse.move(viewport.width / 2, viewport.height / 3);
  for (let k = 0; k < 20; k += 1) await page.mouse.wheel(0, -2000);
  await page.waitForTimeout(400);
  await reveal(page, eggs);
  const box = await eggs.boundingBox();
  await page.mouse.move(box.x + 70, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(900);
  await page.mouse.up();
  await page.waitForTimeout(900);
  out.sheet = await nodes();
  await page.screenshot({ path: join(dir, `${tag}-sheet.png`) });
  }
  console.log(`${tag}: ${out.visibleRows.length} rows whole on the first screen; categories ${JSON.stringify(catsById)}`);
} finally {
  await browser.close();
  reset();
}
writeFileSync(join(dir, `${tag}.json`), JSON.stringify(out, null, 1));
