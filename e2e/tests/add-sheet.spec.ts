import { expect, test, type Locator, type Page } from './fixtures';
import {
  addField, addSheet, adminClient, apiAs, boxOf, chainStores, holdFrames, itemRow, must, newEmail, nextFrames, screenshot, signUpWithHousehold, typeInto,
} from './helpers';
import { watchBuild, withoutWasmGC } from './web-build';

/** The open add sheet: the node whose rect is the sheet's content. */
const sheet = (page: Page) => addSheet(page);
const SOURCES = 'Wie getippt|Schon mal gekauft|Andere Packung|Andere Sorte|Andere Größe|Andere Marke|Aus dem Katalog|Wieder fällig';
/** The sheet's rows, first to last: "<qty> <name>, <source>, <brand>, <details…>, <store>". */
const rows = (page: Page) => sheet(page).getByRole('button', { name: new RegExp(`, (${SOURCES})(,|$)`) });
const listTab = (page: Page) => page.getByRole('tab', { name: 'Liste' });

type Box = { x: number; y: number; width: number; height: number };

/** Bought before: the history behind the measured cases (2, 4, 6 and 8 rows). */
async function seedHistory(email: string): Promise<string> {
  const api = await apiAs(email);
  const { data: household } = await api.from('households').select('id').single();
  if (household === null) throw new Error('no household');
  for (const row of [
    { name: 'Windeln', brand: 'Pampers', properties: 'Größe 4, Big Pack' },
    { name: 'Windeln', brand: 'Pampers', properties: 'Größe 3, sensitiv' },
    { name: 'Windeln', brand: 'Huggies', properties: 'Größe 3' },
    { name: 'Windeln', brand: 'Babylove', properties: 'Größe 5' },
    { name: 'Butter', brand: null, properties: 'gesalzen' },
  ]) {
    const { error } = await api.from('items').insert({ household_id: household.id, status: 'bought', ...row });
    if (error) throw error;
  }
  return household.id as string;
}

/** The sheet's rect once it has held still for a few frames (Flutter animates on its canvas). */
async function settled(page: Page): Promise<Box> {
  let last = '';
  for (let i = 0; i < 60; i++) {
    await nextFrames(page);
    const box = JSON.stringify(await sheet(page).boundingBox());
    if (box === last && box !== 'null') return JSON.parse(box) as Box;
    last = box;
    await page.waitForTimeout(50);
  }
  throw new Error('the sheet kept moving');
}

async function lastRowBottom(list: Locator): Promise<number> {
  const boxes = await list.evaluateAll((els) => els.map((e) => e.getBoundingClientRect().bottom));
  return Math.max(...boxes);
}

async function dbItem(email: string, name: string) {
  const api = await apiAs(email);
  const { data } = await api.from('items')
    .select('name, brand, properties, quantity, status, store:stores(name)')
    .eq('name', name).eq('status', 'active');
  return data ?? [];
}

test('the sheet hugs its suggestions, grows with them up to the top and keeps the input still', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const email = newEmail('sheet');
  await signUpWithHousehold(page, email, { stores: chainStores });
  await seedHistory(email);
  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect(listTab(page)).toBeVisible();
  const closed = await boxOf(addField(page));
  await screenshot(page, 'add-01-closed');

  for (const [query, count] of [['Spülmittel Pril', 2], ['Mi', 4], ['Butter', 6]] as const) {
    await typeInto(addField(page), query);
    await expect(rows(page)).toHaveCount(count);
    const box = await settled(page);
    const input = await boxOf(addField(page));
    expect(Math.abs(input.y - closed.y), `${query}: the input stays put`).toBeLessThanOrEqual(2);
    const band = input.y - (await lastRowBottom(rows(page)));
    expect(band, `${query}: no dead band between the last row and the input`).toBeLessThanOrEqual(24);
    expect(box.y, `${query}: below the top, so it does not scroll yet`).toBeGreaterThan(28 + 2);
    await expect(listTab(page), `${query}: the tabs are away while the sheet is open`).toBeHidden();
    if (count === 2) {
      expect(844 - box.y, 'two rows: at most half the screen, bar and tabs included').toBeLessThanOrEqual(844 / 2);
    }
    await screenshot(page, `add-${count}-${query.replace(/\W+/g, '-')}`);
  }

  await typeInto(addField(page), 'Windeln Pampers Größe 3');
  await expect(rows(page)).toHaveCount(8);
  await expect(rows(page).first()).toHaveAccessibleName('Windeln, Wie getippt, Pampers, Größe 3, dm');
  const eight = await settled(page);
  expect(Math.abs((await boxOf(addField(page))).y - closed.y), 'eight rows: the input stays put').toBeLessThanOrEqual(2);
  expect(closed.y - (await lastRowBottom(rows(page))), 'eight rows: no dead band').toBeLessThanOrEqual(24);
  await screenshot(page, 'add-8-Windeln-Pampers-Groesse-3');

  // The app's rows are one line shorter than the prototype's, so eight fit on 844 px; on a
  // 667 px phone (iPhone SE) the same eight reach the top and only then scroll.
  await page.setViewportSize({ width: 390, height: 667 });
  const full = await settled(page);
  expect(full.y, 'on a short screen the sheet reaches the top gap').toBeLessThanOrEqual(28 + 2);
  expect(full.height, 'and is shorter than its content on 844 px').toBeLessThan(eight.height);
  await screenshot(page, 'add-8-full-667');
  // Without the title row (job 78) the eight overflow by less than a row, so the first stays
  // partly in view, its box clipped at the top: the last row is the one that visibly moves up.
  const lastBefore = await boxOf(rows(page).last());
  await page.mouse.move(195, full.y + full.height - 80);
  await page.mouse.wheel(0, 400);
  await expect.poll(async () => (await rows(page).last().boundingBox())?.y ?? 10_000, { message: 'only now the rows scroll' })
    .toBeLessThan(lastBefore.y - 20);
  await page.setViewportSize({ width: 390, height: 844 });
  await settled(page);

  await sheet(page).getByRole('button', { name: 'Schließen' }).click();
  await expect(sheet(page)).toHaveCount(0);
  await expect(listTab(page), 'the tabs come back after closing').toBeVisible();
  await expect(addField(page), 'closing clears what was typed: the field shows its hint again').toBeVisible();
  expect(Math.abs((await boxOf(addField(page))).y - closed.y), 'closed again: the input is where it was').toBeLessThanOrEqual(2);
});

test('with reduced motion the sheet changes size without animating', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 390, height: 844 });
  await signUpWithHousehold(page, newEmail('sheet-still'));
  await typeInto(addField(page), 'Butter');
  await settled(page);
  const before = await boxOf(sheet(page));
  // From the settled rows to two: the frame that shows the two rows already has the new size.
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.insertText('Spülmittel Pril');
  await expect(rows(page)).toHaveCount(2);
  const a = await boxOf(sheet(page));
  await nextFrames(page);
  const b = await boxOf(sheet(page));
  expect(a.height, 'it did change size').not.toBe(before.height);
  expect(b, 'two frames later it is where it was: no animation').toEqual(a);
  await page.keyboard.press('Escape');
  await nextFrames(page);
  await expect(sheet(page), 'and closes at once').toHaveCount(0);
});

test('a tap adds the row with every field; a chip pick applies to the tapped row; Enter takes the first', async ({ page }) => {
  const email = newEmail('sheet-add');
  // dm for the brand default (Pampers -> dm), an own store for the chip pick.
  await signUpWithHousehold(page, email, { stores: ['dm', 'Supermarkt'] });
  await seedHistory(email);
  await page.reload();
  await expect(addField(page)).toBeFocused();

  await typeInto(addField(page), 'Windeln Pampers Größe 3');
  const first = rows(page).first();
  await expect(first).toHaveAccessibleName('Windeln, Wie getippt, Pampers, Größe 3, dm');
  await first.click();
  await expect.poll(() => sheet(page).ariaSnapshot(), { message: 'the note says what was added where' })
    .toContain('✓ Hinzugefügt: Windeln → dm');
  await expect(addField(page), 'focus stays in the input').toBeFocused();
  await expect(addField(page)).toHaveValue('');
  await expect.poll(() => dbItem(email, 'Windeln')).toEqual([
    { name: 'Windeln', brand: 'Pampers', properties: 'Größe 3', quantity: null, status: 'active', store: { name: 'dm' } },
  ]);

  await typeInto(addField(page), 'Windeln Babylove');
  await expect(rows(page).first()).toHaveAccessibleName(/^Windeln, Wie getippt, Babylove/);
  await sheet(page).getByRole('button', { name: /^Laden: / }).click();
  await sheet(page).getByRole('button', { name: 'Supermarkt', exact: true }).click();
  await expect(sheet(page).getByRole('button', { name: 'Laden: Supermarkt' }), 'the chip shows the pick').toBeVisible();
  const alternative = rows(page).nth(1);
  const label = (await alternative.getAttribute('aria-label')) ?? (await alternative.innerText());
  await screenshot(page, 'add-chip-picked');
  await alternative.click();
  await expect.poll(async () => (await dbItem(email, 'Windeln')).length, { message: 'a second Windeln row' }).toBe(2);
  const added = (await dbItem(email, 'Windeln')).find((r) => r.brand !== 'Pampers' || r.properties !== 'Größe 3');
  if (added === undefined) throw new Error('no new Windeln row');
  expect(added.store, `the store pick applies to the tapped row (${label})`).toEqual({ name: 'Supermarkt' });

  await typeInto(addField(page), 'Butter');
  await page.keyboard.press('Enter');
  await expect.poll(() => dbItem(email, 'Butter'), { message: 'Enter adds the first row, as typed' })
    .toEqual([expect.objectContaining({ name: 'Butter', brand: null, properties: null })]);
  await expect(addField(page)).toBeFocused();
  await sheet(page).getByRole('button', { name: 'Rückgängig' }).click();
  await expect.poll(() => dbItem(email, 'Butter'), { message: 'Undo removes it again' }).toEqual([]);

  // Keyboard: Tab goes from the input to the rows (Flutter focus; the rows keep it off the DOM so
  // a tap never takes the input's text connection), and Enter on a row adds that row.
  await typeInto(addField(page), 'Butter');
  await expect(rows(page).nth(1)).toHaveAccessibleName(/^Butter, Schon mal gekauft, gesalzen/);
  await page.keyboard.press('Tab');
  await page.keyboard.press('Tab');
  await page.keyboard.press('Enter');
  await expect.poll(() => dbItem(email, 'Butter'), { message: 'Tab, Tab, Enter adds the second row' })
    .toEqual([expect.objectContaining({ name: 'Butter', properties: 'gesalzen' })]);

  await page.keyboard.press('Escape');
  await expect(sheet(page)).toHaveCount(0);
  await expect(itemRow(page, 'Windeln').first(), 'the added rows are in the list').toBeVisible();
});

test('an Escape between the refocus after a row and its focus report closes the sheet for good', async ({ page }) => {
  await page.addInitScript(() => {
    const w = window as unknown as { escapeAfterNextInputFocus: boolean };
    const focus = HTMLElement.prototype.focus;
    HTMLElement.prototype.focus = function (this: HTMLElement, options?: FocusOptions) {
      if (w.escapeAfterNextInputFocus && this instanceof HTMLInputElement) {
        w.escapeAfterNextInputFocus = false;
        setTimeout(() => {
          for (const type of ['keydown', 'keyup']) {
            this.dispatchEvent(new KeyboardEvent(type, { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true, cancelable: true }));
          }
        });
      }
      focus.call(this, options);
    };
  });
  await signUpWithHousehold(page, newEmail('sheet-escape'));
  for (const query of ['Butter', 'Mi', 'Br']) {
    await typeInto(addField(page), query);
    await expect(rows(page).nth(1)).toBeVisible();
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await page.evaluate(() => { (window as unknown as { escapeAfterNextInputFocus: boolean }).escapeAfterNextInputFocus = true; });
    await page.keyboard.press('Enter');
    await expect.poll(() => page.evaluate(() => (window as unknown as { escapeAfterNextInputFocus: boolean }).escapeAfterNextInputFocus), { message: `${query}: the add refocused the field` })
      .toBe(false);
    await expect(sheet(page), `${query}: Escape closed the sheet`).toHaveCount(0);
    await page.waitForTimeout(300);
    await expect(sheet(page), `${query}: and nothing opened it again`).toHaveCount(0);
  }
});

test('after a chip pick or Undo, typing goes on in the input without a click', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('sheet-focus'), { stores: ['Supermarkt'] });
  await typeInto(addField(page), 'Butter');
  await sheet(page).getByRole('button', { name: /^Laden: / }).click();
  await sheet(page).getByRole('button', { name: 'Supermarkt', exact: true }).click();
  // On web the input gets its focus back 50 ms after a tap (list_screen.dart, _refocusAfterTap).
  await page.waitForTimeout(150);
  await expect(addField(page)).toBeFocused();
  await page.keyboard.insertText(' Kerrygold');
  await expect(rows(page).first(), 'the text was kept and extended').toHaveAccessibleName(/^Butter, Wie getippt, Kerrygold/);
  await page.keyboard.press('Enter');
  await sheet(page).getByRole('button', { name: 'Rückgängig' }).click();
  await expect(sheet(page).getByRole('button', { name: 'Rückgängig' })).toHaveCount(0);
  await page.waitForTimeout(150);
  await expect(addField(page)).toBeFocused();
  await page.keyboard.insertText('Milch');
  await expect(rows(page).first(), 'Undo hands the input back').toHaveAccessibleName(/^Milch, Wie getippt/);
});

test('after Schließen, a tap on the field and typing open the sheet again', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('sheet-close'));
  await typeInto(addField(page), 'Butter');
  await page.keyboard.press('Enter');
  await sheet(page).getByRole('button', { name: 'Schließen' }).click();
  await expect(sheet(page)).toHaveCount(0);
  await addField(page).click();
  await page.keyboard.type('Brot', { delay: 120 });
  await expect(rows(page).first(), 'the app gets the keys, not only the DOM input').toHaveAccessibleName(/^Brot, Wie getippt/);
});

// A click on the web can reach the field as a semantics focus or tap instead of pointer events,
// which never calls TextField.onTap; on CI that was the field with a cursor and no sheet (#112).
test('after a close, a focus or click that skips pointer events opens the sheet', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('sheet-no-pointer'));
  await typeInto(addField(page), 'Butter');
  await page.keyboard.press('Enter');
  await page.keyboard.press('Escape');
  await expect(sheet(page)).toHaveCount(0);
  await addField(page).focus();
  await expect(sheet(page), 'a DOM focus opens it').toBeVisible();
  await page.keyboard.press('Escape');
  await expect(sheet(page)).toHaveCount(0);
  await addField(page).dispatchEvent('click');
  await expect(sheet(page), 'a click event without pointer events opens it').toBeVisible();
});

for (const build of ['wasm', 'js'] as const) {
  test(`after Schließen, a key typed before the next frame still reaches the app (${build})`, async ({ page }) => {
    if (build === 'js') await withoutWasmGC(page);
    const loaded = watchBuild(page);
    await signUpWithHousehold(page, newEmail(`sheet-early-${build}`));
    expect(loaded()).toEqual([build]);
    await typeInto(addField(page), 'Butter');
    await page.keyboard.press('Enter');
    await sheet(page).getByRole('button', { name: 'Schließen' }).click();
    await expect(sheet(page)).toHaveCount(0);
    await nextFrames(page);
    const release = await holdFrames(page);
    await addField(page).click();
    await page.keyboard.type('B');
    expect(await release(), 'the tap asked for a frame, and it was held').toBeGreaterThan(0);
    await page.keyboard.type('rot', { delay: 120 });
    await expect(rows(page).first(), 'the first key is not lost').toHaveAccessibleName(/^Brot, Wie getippt/);
    await screenshot(page, `add-first-key-${build}`);
  });
}

test('with nothing typed, the open sheet offers what is due', async ({ page }) => {
  const email = newEmail('sheet-due');
  await signUpWithHousehold(page, email);
  const household = await seedHistory(email);
  const api = await apiAs(email);
  const { data: item } = await api.from('items').select('id').eq('name', 'Butter').single();
  if (item === null) throw new Error('no Butter item');
  const daysAgo = (days: number) => new Date(Date.now() - days * 86_400_000).toISOString();
  const events = adminClient().from('item_events');
  expect((await events.insert([
    { household_id: household, item_id: item.id, action: 'added', item_name: 'Butter', created_at: daysAgo(15) },
    { household_id: household, item_id: item.id, action: 'bought', item_name: 'Butter', created_at: daysAgo(14) },
    { household_id: household, item_id: item.id, action: 'added', item_name: 'Butter', created_at: daysAgo(8) },
    { household_id: household, item_id: item.id, action: 'bought', item_name: 'Butter', created_at: daysAgo(7) },
  ])).error).toBeNull();
  await page.reload();
  await addField(page).click();
  await expect(sheet(page).getByRole('button', { name: /^Butter, Wieder fällig/ })).toBeVisible();
  await screenshot(page, 'add-due');
  await sheet(page).getByRole('button', { name: /^Butter, Wieder fällig/ }).click();
  await expect.poll(async () => (await dbItem(email, 'Butter')).length).toBe(1);
});

// Job 135: the field floats over the list, which scrolls on under it. A near miss beside the hex
// opens the field; it never ticks the row hidden under the field.
test('a tap beside the floating field opens it and leaves the row under it alone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const email = newEmail('sheet-gutter');
  await signUpWithHousehold(page, email);
  const api = await apiAs(email);
  const { data: household } = await api.from('households').select('id').single();
  const names = ['Äpfel', 'Birnen', 'Gurke', 'Tomaten', 'Paprika', 'Zucchini', 'Möhren', 'Kartoffeln', 'Zwiebeln',
    'Knoblauch', 'Salat', 'Spinat', 'Brokkoli', 'Zitronen', 'Avocado', 'Ingwer', 'Butter', 'Joghurt'];
  const { error } = await api.from('items').insert(names.map((name) => ({ household_id: must(household, 'household').id, name })));
  if (error) throw error;
  await page.reload();
  await expect(itemRow(page, 'Äpfel')).toHaveCount(1);
  await expect(sheet(page)).toHaveCount(0);

  const field = await boxOf(addField(page));
  const gutter = { x: 6, y: field.y + field.height / 2 };
  const under = await page.getByRole('checkbox').evaluateAll((els, p) => els
    .filter((e) => { const r = e.getBoundingClientRect(); return r.top <= p.y && r.bottom >= p.y && r.left <= p.x && r.right >= p.x; })
    .map((e) => e.getAttribute('aria-label')), gutter);
  expect(under, 'a row runs on under the field').toHaveLength(1);
  await screenshot(page, 'add-gutter-before');

  await page.mouse.click(gutter.x, gutter.y);
  await expect(sheet(page), 'the near miss opens the field').toBeVisible();
  await expect(addField(page)).toBeFocused();
  await page.keyboard.type('Brot', { delay: 120 });
  await expect(rows(page).first(), 'typing goes on in the field').toHaveAccessibleName(/^Brot, Wie getippt/);
  const { data: active } = await api.from('items').select('name').eq('household_id', must(household, 'household').id).eq('status', 'active');
  expect(must(active, 'active items').map((i) => i.name).sort(), 'no row was ticked').toEqual([...names].sort());
});

test('the mouse wheel over the floating field and the tab pill scrolls the list; a click still opens the field', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const email = newEmail('sheet-wheel');
  await signUpWithHousehold(page, email);
  const api = await apiAs(email);
  const { data: household } = await api.from('households').select('id').single();
  const names = Array.from({ length: 24 }, (_, i) => `Artikel ${String(i).padStart(2, '0')}`);
  const { error } = await api.from('items').insert(names.map((name) => ({ household_id: must(household, 'household').id, name })));
  if (error) throw error;
  await page.reload();
  const first = itemRow(page, 'Artikel 00');
  await expect(first).toHaveCount(1);

  const field = await boxOf(addField(page));
  const pill = await boxOf(listTab(page));
  for (const [where, at] of [
    ['the field', { x: field.x + field.width / 2, y: field.y + field.height / 2 }],
    ['the tab pill', { x: pill.x + pill.width / 2, y: pill.y + pill.height / 2 }],
  ] as const) {
    const before = (await boxOf(first)).y;
    await page.mouse.move(at.x, at.y);
    await page.mouse.wheel(0, 120);
    await expect.poll(async () => before - (await boxOf(first)).y, `the wheel over ${where}`).toBe(120);
    await page.mouse.wheel(0, -120);
    await expect.poll(async () => (await boxOf(first)).y).toBe(before);
  }
  await expect(sheet(page)).toHaveCount(0);
  await addField(page).click();
  await expect(sheet(page)).toBeVisible();
  await expect(addField(page)).toBeFocused();
});
