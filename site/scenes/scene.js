// Fills every [data-t] element from the page's STRINGS table for ?lang=de|en (default de).
// A missing string is a console error, which film-all.mjs treats as a failed film.
const lang = new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'de';
document.documentElement.lang = lang;
for (const el of document.querySelectorAll('[data-t]')) {
  const text = globalThis.STRINGS?.[lang]?.[el.dataset.t];
  if (text === undefined) console.error(`missing string ${lang}.${el.dataset.t}`);
  else el.innerHTML = text;
}
