// Today's list at launch in the real app (release web build from verify-snacklist's launch.sh with the launch flags:
// redesign-rd1, hide-categories, add-sheet-compact, open-store-app on; grocery-log, prices-and-trip-total, trip-mode
// off). Puts the round's mock list into the seeded household (REWE, Lidl and dm linked to their chains, REWE with one
// item left), records the semantics boxes and a screenshot, ticks REWE's last item and records the list again: the
// REWE section and its app key are gone. The replica in ../phone.js is calibrated against these numbers.
// Built on job 355's docs/design/list/tools/capture-today.mjs.
//
//   node docs/design/store-card/tools/capture-today.mjs <out dir> [--lang en|de] [--scale 3.1] [--dark]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, instance, itemRow, member, openApp, signIn } from '../../../../.claude/skills/verify-snacklist/helpers/lib.mjs';
import { stores, items } from '../data.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'en');
const scale = Number(arg('--scale', '1'));
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: capture-today.mjs <out dir> [--lang en|de] [--scale 3.1] [--dark]');
mkdirSync(dir, { recursive: true });

const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const real = stores.filter((s) => s.capture);
sql(`delete from public.items where household_id = '${household}'`);
const storeIds = {};
for (const [k, s] of real.entries()) {
  const { data } = await api.from('stores').select('id, name').eq('household_id', household);
  storeIds[s.id] = data?.find((r) => r.name === s.name)?.id;
  if (!storeIds[s.id]) {
    const { data: id, error } = await api.rpc('add_store', { p_household: household, p_name: s.name });
    if (error) throw error;
    storeIds[s.id] = id;
  }
  sql(`update public.stores set sort_order = ${k}, retailer_chain = ${q(s.chain)}, retailer_country = 'DE', retailer_app = ${q(s.app)}, retailer_answered = true where id = '${storeIds[s.id]}'`);
}
sql(`update public.stores set sort_order = 100 + sort_order where household_id = '${household}' and id not in (${Object.values(storeIds).map(q).join(',')})`);

const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
const mine = items.filter((i) => storeIds[i.store]);
for (const i of mine) {
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name: i[lang], store_id: storeIds[i.store], quantity: i.qty ?? null });
  if (error) throw error;
  await new Promise((r) => setTimeout(r, 30));
}
const rewe = mine.filter((i) => i.store === 'rewe');
const last = rewe.at(-1);
for (const [k, i] of rewe.slice(0, -1).entries()) {
  sql(`update public.items set status = 'bought', bought_at = now() - interval '${20 - k} minutes', bought_by = '${mia.id}' where household_id = '${household}' and name = ${q(i[lang])}`);
}

const viewport = { width: 390, height: 844 };
const tag = `${lang}-${Math.round(scale * 100)}${dark ? '-dark' : ''}`;
const { browser, page, L } = await openApp(inst, { lang, viewport, dpr: 2, dark });
const nodes = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => {
  const r = n.getBoundingClientRect();
  const leaf = !n.querySelector('flt-semantics');
  const own = (leaf ? n.textContent : [...n.childNodes].filter((c) => c.nodeType === 3).map((c) => c.textContent).join('')).trim();
  return { role: n.getAttribute('role') ?? null, label: n.getAttribute('aria-label') || own || '', top: r.top, bottom: r.bottom, left: r.left, right: r.right, height: r.height };
}).filter((n) => n.bottom > n.top && n.label && n.top < 844));
const park = () => page.mouse.move(1, viewport.height - 1);

const out = { lang, scale, dark, viewport, last: last[lang] };
try {
  await signIn(page, L, mia);
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await page.reload();
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await itemRow(page, last[lang]).waitFor({ timeout: 20_000 });
  await page.waitForTimeout(1500);
  await park();
  out.withTip = await nodes();
  await page.screenshot({ path: join(dir, `${tag}-1-tip.png`) });
  const tip = out.withTip.find((n) => n.label === L('storeAppTip'));
  if (tip) {
    const x = out.withTip.filter((n) => n.role === 'button' && Math.abs((n.top + n.bottom) / 2 - (tip.top + tip.bottom) / 2) < 20 && n.left > 300)[0];
    if (x) await page.mouse.click((x.left + x.right) / 2, (x.top + x.bottom) / 2);
    else throw new Error('no close X next to the store-app tip');
    await page.waitForTimeout(900);
  }
  await park();
  out.before = await nodes();
  await page.screenshot({ path: join(dir, `${tag}-2-before.png`) });
  const row = itemRow(page, last[lang]).first();
  const box = await row.boundingBox();
  await page.mouse.click(box.x + 60, box.y + box.height / 2);
  await itemRow(page, last[lang]).waitFor({ state: 'detached', timeout: 10_000 });
  await page.waitForTimeout(1500);
  await park();
  out.after = await nodes();
  await page.screenshot({ path: join(dir, `${tag}-3-after.png`) });
  const heads = (ns) => ns.filter((n) => stores.some((s) => n.label.startsWith(s.name))).map((n) => `${Math.round(n.top)} ${n.label}`);
  console.log(`${tag}: before ${JSON.stringify(heads(out.before))} after ${JSON.stringify(heads(out.after))}`);
} finally {
  await browser.close();
}
writeFileSync(join(dir, `${tag}.json`), JSON.stringify(out, null, 1));
