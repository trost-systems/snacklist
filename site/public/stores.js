// The stores card on the landing page (landing.mjs renders it with the supermarket first): a
// store button moves that store to the top. Rows that stay slide from their old place to the new one
// and rows that join fade in (FLIP), unless the visitor asked for reduced motion. Without this
// file the card shows the supermarket first.
const motionOk = matchMedia('(prefers-reduced-motion: no-preference)');
const timing = { duration: 360, easing: 'cubic-bezier(0.2, 0, 0, 1)' };

for (const card of document.querySelectorAll('[data-stores]')) {
  const list = card.querySelector('.store-route');
  const rows = new Map([...list.children].map((li) => [li.dataset.store, li]));
  const buttons = [...card.querySelectorAll('[data-route]')];
  card.classList.add('is-live');

  const show = (button) => {
    const route = button.dataset.route.split(' ');
    const before = new Map([...rows].filter(([, li]) => !li.hidden).map(([c, li]) => [c, { rect: li.getBoundingClientRect(), opacity: getComputedStyle(li).opacity }]));
    for (const li of rows.values()) for (const animation of li.getAnimations()) animation.cancel();

    for (const b of buttons) b.setAttribute('aria-pressed', String(b === button));
    list.setAttribute('aria-labelledby', button.querySelector('[id]').id);
    for (const [c, li] of rows) li.hidden = !route.includes(c);
    list.append(...route.map((c) => rows.get(c)), ...[...rows.values()].filter((li) => li.hidden));

    if (!motionOk.matches) return;
    route.forEach((c, i) => {
      const li = rows.get(c);
      const from = before.get(c);
      if (from) {
        const to = li.getBoundingClientRect();
        li.animate({ translate: [`${from.rect.left - to.left}px ${from.rect.top - to.top}px`, '0 0'], opacity: [from.opacity, 1] }, timing);
      } else {
        li.animate({ opacity: [0, 1], translate: ['-16px 0', '0 0'] }, { ...timing, delay: 40 * i, fill: 'backwards' });
      }
    });
  };

  for (const button of buttons) {
    button.addEventListener('click', () => {
      if (button.getAttribute('aria-pressed') !== 'true') show(button);
    });
  }
}
