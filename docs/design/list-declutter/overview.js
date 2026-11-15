import { rounds, linked, roundOf } from './rounds.js';

// Links to the one shared page (`/#/st`, `/#/ST3`, `/#/rec1`) go on to the page that now holds that view.
const forward = () => {
  const view = location.hash.slice(2);
  const home = view && roundOf(view);
  if (home) location.replace(`${home.path}/${location.search}#/${view === 'all' ? 'r1' : view}`);
  return home;
};
const home = forward();
addEventListener('hashchange', forward);

const lang = new URLSearchParams(location.search).get('lang') === 'de' ? 'de' : 'en';
const t = {
  en: { title: 'List screen prototypes', intro: 'One page per round, newest first. Each page shows only that round’s options and its recommendation.', other: 'Deutsch', otherQ: '?lang=de' },
  de: { title: 'Prototypen für den Listen-Bildschirm', intro: 'Eine Seite je Runde, die neueste zuerst. Jede Seite zeigt nur die Varianten und die Empfehlung ihrer Runde.', other: 'English', otherQ: '?lang=en' },
}[lang];
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
document.documentElement.lang = lang;
document.title = t.title;
const app = document.getElementById('app');
if (app && !home)
  app.innerHTML = `<h1>${t.title}</h1><p class="note">${t.intro}</p>
  <ul class="rounds">${[...linked, ...rounds]
    .map((r) => `<li><a href="${r.href ?? `${r.path}/`}${location.search}"><b>${esc(r.title[lang])}</b><span class="date">${r.date[lang]}</span></a><p>${esc(r.blurb[lang])}</p></li>`)
    .join('')}</ul>
  <p class="note"><a href="${t.otherQ}">${t.other}</a></p>`;
