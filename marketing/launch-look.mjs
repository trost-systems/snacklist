// What every web capture checks on screen besides the compiled flags (capture-flags.mjs): the
// launch build shows no Verlauf tab and no price chip (marketing/CAPTURE_FLAGS_OFF).
export async function launchLook(page, L, where) {
  if (!(await page.getByRole('tab', { name: L('tabList') }).count())) throw new Error(`${where}: no ${L('tabList')} tab to compare with`);
  const history = await page.getByRole('tab', { name: L('tabHistory') }).count();
  const prices = await page.getByRole('button', { name: new RegExp(`^${L('priceChipEmpty', { name: '' })}`) }).count();
  if (history || prices) throw new Error(`${where}: not the launch build (${history} Verlauf tab, ${prices} price chips)`);
}
