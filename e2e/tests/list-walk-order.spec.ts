import type { SupabaseClient } from '@supabase/supabase-js';
import { expect, type Page, test } from './fixtures';
import { outline, sectionHeadings, sectionItems, setStore, storeOf } from './catalog';
import {
  apiAs, boxOf, chainStores, createInviteCode, editSheet, firstOf, itemRow, joinWithCode, must, newEmail, reveal, screenshot, signUp,
  signUpWithHousehold, storeDivider, putBack, tick,
} from './helpers';

type Seed = { name: string; store?: string; category: string; brand?: string; properties?: string; quantity?: string; key: number };

/** Puts [items] on the signed-in user's list over the API, with their walk order, and reloads. */
async function seed(page: Page, email: string, items: Seed[]): Promise<SupabaseClient> {
  const api = await apiAs(email);
  const { data: stores } = await api.from('stores').select('id, name, household_id');
  const { data: categories } = await api.from('categories').select('id, name');
  const id = (rows: { id: string; name: string }[] | null, name: string) => must(rows?.find((r) => r.name === name), name).id;
  const { error } = await api.from('items').insert(items.map((i) => ({
    household_id: firstOf(stores, 'store').household_id,
    name: i.name,
    store_id: i.store ? id(stores, i.store) : null,
    category_id: id(categories, i.category),
    brand: i.brand ?? null,
    properties: i.properties ?? null,
    quantity: i.quantity ?? null,
    sort_key: i.key,
  })));
  if (error) throw error;
  await page.reload();
  await expect(itemRow(page, must(items.at(-1), 'seeded item').name)).toBeVisible();
  return api;
}

const stores = async (page: Page) => (await outline(page)).map((s) => s.store);

const lidl: Seed[] = [
  { name: 'Äpfel', store: 'Lidl', category: 'Obst & Gemüse', quantity: '1 kg', properties: 'Elstar', key: 1024 },
  { name: 'Bananen', store: 'Lidl', category: 'Obst & Gemüse', quantity: '6', properties: 'Bio', key: 2048 },
  { name: 'Gurke', store: 'Lidl', category: 'Obst & Gemüse', key: 3072 },
  { name: 'Milch', store: 'Lidl', category: 'Kühlregal', brand: 'Milbona', properties: '1,5 %', quantity: '2 l', key: 1024 },
  { name: 'Joghurt', store: 'Lidl', category: 'Kühlregal', key: 2048 },
  { name: 'Zahnpasta', store: 'dm', category: '👶 Drogerie', brand: 'elmex', key: 1024 },
  { name: 'Brot', category: 'Brot & Backwaren', key: 1024 },
];

async function householdOf(api: SupabaseClient): Promise<string> {
  const { data } = await api.from('stores').select('household_id').limit(1).single();
  return must(data, 'store').household_id as string;
}

test('stores and categories are dividers that scroll away, stores fold for good, the explainer goes for good', async ({ page }) => {
  const email = newEmail('walk-dividers');
  await signUpWithHousehold(page, email, { stores: chainStores });
  const hint = 'Tippen hakt ab · Halten bearbeitet';
  await expect(page.getByText(hint)).toBeVisible();
  await seed(page, email, lidl);
  await expect(storeDivider(page, 'Lidl')).toHaveAccessibleName(/^Lidl, 5 Artikel/);
  await expect(storeDivider(page, 'dm')).toHaveAccessibleName(/^dm, 1 Artikel/);
  await expect(storeDivider(page, 'EDEKA'), 'a store without items does not show').toHaveCount(0);
  await expect(page.getByRole('button', { name: /, 0 Artikel/ }), 'no "0 Artikel" anywhere').toHaveCount(0);
  await expect.poll(() => sectionItems(page, 'Lidl')).toEqual(['Äpfel Elstar 1 kg', 'Bananen Bio 6', 'Gurke', 'Milch Milbona · 1,5 % 2 l', 'Joghurt']);
  await expect.poll(() => sectionHeadings(page, 'Lidl')).toEqual(['Obst & Gemüse', 'Kühlregal']);
  await page.mouse.move(0, 899);
  await screenshot(page, 'walk-01-list');

  const store = storeDivider(page, 'Lidl');
  const heading = page.getByRole('heading', { name: 'Kühlregal', exact: true });
  const row = itemRow(page, 'Joghurt');
  const y = async () => [(await boxOf(store)).y, (await boxOf(heading)).y, (await boxOf(row)).y] as const;
  const before = await y();
  await page.mouse.move(240, 600);
  await page.mouse.wheel(0, 80);
  await page.waitForTimeout(300);
  const after = await y();
  const moved = ([0, 1, 2] as const).map((i) => Math.round(before[i] - after[i]));
  expect(moved[0], 'the list scrolled').toBeGreaterThan(20);
  expect(moved, 'store divider, category divider and row move by the same delta: nothing sticks').toEqual([moved[0], moved[0], moved[0]]);
  await page.mouse.wheel(0, -80);

  await page.getByRole('button', { name: 'Verstanden' }).click();
  await expect(page.getByText(hint)).toHaveCount(0);

  await store.click();
  await expect(storeDivider(page, 'Lidl')).toHaveAccessibleName(/^Lidl, 5 Artikel/);
  await expect(itemRow(page, 'Äpfel'), 'a folded store shows only its divider').toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Obst & Gemüse', exact: true })).toHaveCount(0);
  await page.mouse.move(0, 899);
  await screenshot(page, 'walk-02-folded');
  await page.reload();
  await expect(itemRow(page, 'Zahnpasta')).toBeVisible();
  await expect(itemRow(page, 'Äpfel'), 'still folded after a reload').toHaveCount(0);
  await expect(page.getByText(hint), 'dismissed for good')
    .toHaveCount(0);

  await setStore(page, 'Brot', 'Lidl');
  await expect(storeDivider(page, 'Lidl'), 'a folded store takes a moved item').toHaveAccessibleName(/^Lidl, 6 Artikel/);
  await expect(itemRow(page, 'Brot')).toHaveCount(0);
  await storeDivider(page, 'Lidl').click();
  await expect.poll(() => storeOf(page, 'Brot')).toBe('Lidl');
  await expect.poll(() => sectionHeadings(page, 'Lidl'), { message: 'Brot keeps its category, in Lidl\'s order' })
    .toEqual(['Brot & Backwaren', 'Obst & Gemüse', 'Kühlregal']);
  await expect(storeDivider(page, 'Ohne Laden'), 'its last item moved out, the section without a store hides').toHaveCount(0);

  await setStore(page, 'Zahnpasta', 'EDEKA');
  await expect(storeDivider(page, 'EDEKA'), 'an empty store shows once an item moves in').toHaveAccessibleName(/^EDEKA, 1 Artikel/);
  await expect(storeDivider(page, 'dm'), 'its last item moved out, dm hides').toHaveCount(0);
  await expect(storeDivider(page, 'Ohne Laden'), 'still empty, hidden').toHaveCount(0);
  await expect.poll(() => storeOf(page, 'Zahnpasta')).toBe('EDEKA');
  await page.mouse.move(240, 400);
  await page.mouse.wheel(0, -2000);
  await expect(storeDivider(page, 'Lidl')).toBeInViewport();
  await page.mouse.move(0, 899);
  await screenshot(page, 'walk-08-after-move-into-empty-store');
});

test('nothing on the list drags: a hold on a row edits, a hold or right click on a divider does nothing, a tap folds', async ({ page }) => {
  const email = newEmail('walk-hold');
  await signUpWithHousehold(page, email, { stores: chainStores });
  await page.getByRole('button', { name: 'Verstanden' }).click();
  await seed(page, email, lidl);
  const before = await outline(page);

  const g = await boxOf(itemRow(page, 'Gurke'));
  await page.mouse.move(g.x + g.width / 2, g.y + g.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(700);
  await expect(editSheet(page), 'the hold edits while the button is still down').toBeVisible();
  await page.mouse.move(g.x + g.width / 2, g.y - 150, { steps: 10 });
  await page.mouse.up();
  await editSheet(page).getByRole('button', { name: 'Abbrechen' }).click();
  await expect(editSheet(page)).toHaveCount(0);
  expect(await outline(page), 'a hold that moves on moves nothing').toEqual(before);

  const url = page.url();
  for (const divider of [storeDivider(page, 'Lidl'), page.getByRole('heading', { name: 'Kühlregal', exact: true })]) {
    const box = await boxOf(divider);
    await page.mouse.move(box.x + 40, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(700);
    await page.mouse.up();
    await page.mouse.click(box.x + 40, box.y + box.height / 2, { button: 'right' });
    await page.waitForTimeout(500);
    expect(page.url(), 'a hold or right click on a divider opens nothing').toBe(url);
    expect(await outline(page), 'a hold or right click neither moves nor folds').toEqual(before);
  }
  await page.mouse.move(0, 899);
  await screenshot(page, 'walk-hold-divider-nothing');
  await storeDivider(page, 'Lidl').click();
  await expect(itemRow(page, 'Gurke'), 'a tap folds the store').toHaveCount(0);
  expect(page.url(), 'the tap only folds').toBe(url);
  await page.mouse.move(0, 899);
  await screenshot(page, 'walk-tap-divider-folds');
});

test('a tap ticks, a tap under Zuletzt verwendet puts it back in place, a hold or right click edits, names wrap, no added-by badge', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const email = newEmail('walk-rows');
  await signUpWithHousehold(peter, email, { stores: chainStores });
  const long = 'Glutenfreie Dinkel-Vollkorn-Toastbrötchen mit Sonnenblumenkernen und extra viel Kruste';
  await seed(peter, email, [...lidl, { name: long, store: 'Lidl', category: 'Brot & Backwaren', key: 1024 }]);

  await tick(peter, 'Bananen');
  await expect(itemRow(peter, 'Bananen')).toHaveCount(0);
  await putBack(peter, 'Bananen');
  await expect.poll(() => sectionItems(peter, 'Lidl'), { message: 'putting it back puts it where it was' })
    .toEqual([long, 'Äpfel Elstar 1 kg', 'Bananen Bio 6', 'Gurke', 'Milch Milbona · 1,5 % 2 l', 'Joghurt']);

  await itemRow(peter, 'Gurke').click({ button: 'right' });
  await expect(editSheet(peter), 'a right click edits').toBeVisible();
  await editSheet(peter).getByRole('button', { name: 'Abbrechen' }).click();
  await expect(editSheet(peter)).toHaveCount(0);
  const g = await boxOf(itemRow(peter, 'Gurke'));
  await peter.mouse.move(g.x + g.width / 2, g.y + g.height / 2);
  await peter.mouse.down();
  await peter.waitForTimeout(700);
  await peter.mouse.up();
  await expect(editSheet(peter), 'a hold that stays put edits').toBeVisible();
  await editSheet(peter).getByRole('button', { name: 'Abbrechen' }).click();

  const longRow = await boxOf(itemRow(peter, long));
  const short = await boxOf(itemRow(peter, 'Gurke'));
  // A one-line row is the 48 px minimum (job 57); two 21 px lines and the padding make it taller.
  expect(longRow.height, 'a long name wraps: the row grows').toBeGreaterThan(short.height + 4);
  await expect(itemRow(peter, long)).toHaveAccessibleName(new RegExp(`^${long}`));

  const leaEmail = newEmail('walk-rows-lea');
  const lea = await (await browser.newContext()).newPage();
  const code = await createInviteCode(peter);
  await signUp(lea, leaEmail);
  await joinWithCode(lea, code);
  await expect(itemRow(lea, 'Gurke')).toBeVisible();
  await (await apiAs(leaEmail)).from('items').insert({
    household_id: await householdOf(await apiAs(leaEmail)), name: 'Hafer',
  });
  // The add bar at the bottom leaves the list less room: Hafer lands below the fold.
  await reveal(peter, itemRow(peter, 'Hafer'));
  await expect(itemRow(peter, 'Hafer'), 'the partner\'s add: no initial, but new').toHaveAccessibleName(/^Hafer\sNeu$/);
  await expect(peter.getByText(`1 neu von ${leaEmail.split('@')[0]}`)).toBeVisible();
  await peter.mouse.move(0, 899);
  await screenshot(peter, 'walk-04-rows');
});

test('wide screens put the stores in columns, and an item moves across them', async ({ page }) => {
  const email = newEmail('walk-wide');
  await page.setViewportSize({ width: 1366, height: 1024 });
  await signUpWithHousehold(page, email, { stores: chainStores });
  await page.getByRole('button', { name: 'Verstanden' }).click();
  await seed(page, email, [
    ...lidl,
    { name: 'Hack', store: 'EDEKA', category: 'Fleisch/Wurst/Fisch', quantity: '500 g', key: 1024 },
    { name: 'Schokolade', store: 'EDEKA', category: 'Süßes & Snacks', brand: 'Ritter Sport', key: 1024 },
  ]);
  const columns = async (names: string[]) =>
    new Set(await Promise.all(names.map(async (n) => (await storeDivider(page, n).boundingBox())?.x ?? NaN))).size;
  await expect.poll(() => columns(['dm', 'Lidl', 'EDEKA', 'Ohne Laden']), { message: 'three columns at 1366 px' }).toBe(3);
  expect((await boxOf(itemRow(page, 'Gurke'))).width, 'a readable row width').toBeLessThanOrEqual(560);
  await screenshot(page, 'walk-05-wide-1366');

  expect(await stores(page), 'a screen reader reads column by column').toEqual(['dm', 'Lidl', 'EDEKA', 'Ohne Laden']);
  await setStore(page, 'Brot', 'EDEKA');
  await expect.poll(() => storeOf(page, 'Brot'), { message: 'into another column' }).toBe('EDEKA');

  await page.setViewportSize({ width: 820, height: 1180 });
  await expect.poll(() => columns(['dm', 'Lidl']), { message: 'one column at 820 px' }).toBe(1);
  const row = await boxOf(itemRow(page, 'Gurke'));
  expect(row.width, 'centred at its max width').toBe(640);
  expect(row.x).toBeCloseTo((820 - 640) / 2, 0);
  await screenshot(page, 'walk-06-wide-820');
});
