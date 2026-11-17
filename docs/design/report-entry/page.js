import { Phone, blankForm } from './phone.js';
import { copy } from './copy.js';

const params = new URLSearchParams(location.search);
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: params.get('ts') === '200' ? 200 : 100,
  fb4: params.get('fb4') === 'off' ? 'off' : 'on',
};
const fb4 = S.fb4 === 'on';

const W = {
  en: {
    title: 'Report content entry (RC1–RC3)', back: 'Prototype overview',
    note: 'Three ways into the in-app “Report content” form next to feedback (DSA Art. 16; Legal N-226 to N-229). The phones are live: tap through them. The form and the confirmation are the same in every option; only the way in differs. Demo data only (the fictional Brandt family); nothing is sent.',
    light: 'Light', dark: 'Dark', text: 'Text', largest: 'largest (200 %)', fb4on: 'FB4 hub on', fb4off: 'FB4 off (live today)',
    fb4Note: 'FB4’s “Feedback & ideas” hub is still off for every user (flag feedback-fb4); without it More’s row is “Send feedback” and opens the feedback sheet. N-226 wants the report entry with every feedback flag on or off, so each option has both states: switch above.',
    legalTitle: 'What every option keeps (Legal, Addendum B)',
    legal: [
      'N-226: “Report content” is a first-level choice with its own form, visible without scrolling next to feedback, never a category in the feedback form. The More row says reporting is there (“Feedback & reports”, or “Feedback & ideas” with “Also: report content”). It shows with every feedback flag.',
      'N-227: reports are not feedback. They never appear under Your notes, never reach the household, and get no status, reply or +1 flow.',
      'N-228: what it is about (required, six kinds), where it is (required, picked in the app and confirmed), why it is illegal (required, 20 to 5,000 characters), name and e-mail (recommended, prefilled from the account, hidden by default for child abuse material), good-faith checkbox (required), optional screenshot.',
      'N-229: a reference number on screen right away. The e-mail confirmation goes out only if an e-mail was given.',
    ],
    frames: { more: 'More', hub: 'Feedback & ideas (today)', sheet: 'Send feedback (today)', entry: 'Entry choice', form: 'Report form', done: 'Confirmation' },
    formTitle: 'The report form (the same in RC1–RC3)',
    formNote: 'Legal’s B.4 fields and help texts word for word, with two cuts: the screenshot label drops “in the app”, and the help under “Where is the content?” keeps only the app’s sentence, shown once something is picked. Opened from More, nothing is preselected, so “Where is the content?” opens a picker over the household’s items, lists, household name and photos, with a search and “Somewhere else” for free text.',
    formFrames: { filled: 'Filled in', picker: 'Where: the picker', csam: 'Child abuse material: anonymous by default', errors: 'Send with fields missing', else: 'Where: somewhere else', over: 'Over 5,000 characters', bottom: 'Good faith and Send' },
    pick: 'Pick', runner: 'Runner-up', jump: 'Recommendation and measured table',
  },
  de: {
    title: 'Einstieg „Inhalt melden“ (RC1–RC3)', back: 'Prototypen-Übersicht',
    note: 'Drei Wege in das Formular „Inhalt melden“ in der App, neben Feedback (DSA Art. 16; Legal N-226 bis N-229). Die Telefone sind echt: tipp dich durch. Formular und Bestätigung sind in jeder Option gleich, nur der Weg hinein ist anders. Nur Demodaten (die erfundene Familie Brandt); nichts wird gesendet.',
    light: 'Hell', dark: 'Dunkel', text: 'Text', largest: 'größte (200 %)', fb4on: 'FB4-Übersicht an', fb4off: 'FB4 aus (heute live)',
    fb4Note: 'FB4s Übersicht „Feedback & Ideen“ ist für alle noch aus (Flag feedback-fb4); ohne sie heißt die Zeile in Mehr „Feedback senden“ und öffnet das Feedback-Blatt. N-226 verlangt den Meldeweg bei jedem Feedback-Flag, an oder aus, darum hat jede Option beide Zustände: Schalter oben.',
    legalTitle: 'Was jede Option einhält (Legal, Nachtrag B)',
    legal: [
      'N-226: „Inhalt melden“ ist eine Wahl auf erster Ebene mit eigenem Formular, ohne Scrollen sichtbar neben Feedback, nie eine Kategorie im Feedback-Formular. Die Zeile in Mehr sagt, dass man dort melden kann („Feedback & Meldungen“ oder „Feedback & Ideen“ mit „Auch: Inhalte melden“). Sie erscheint bei jedem Feedback-Flag.',
      'N-227: Meldungen sind kein Feedback. Sie stehen nie unter Deine Notizen, erreichen nie den Haushalt und haben keinen Status-, Antwort- oder +1-Ablauf.',
      'N-228: Worum es geht (Pflicht, sechs Arten), wo es ist (Pflicht, in der App ausgewählt und bestätigt), warum es rechtswidrig ist (Pflicht, 20 bis 5.000 Zeichen), Name und E-Mail (empfohlen, aus dem Konto vorausgefüllt, bei Darstellungen von Kindesmissbrauch zunächst verborgen), Gutglaubens-Häkchen (Pflicht), Screenshot optional.',
      'N-229: sofort eine Nummer auf dem Bildschirm. Die Bestätigung per E-Mail geht nur raus, wenn eine E-Mail-Adresse angegeben wurde.',
    ],
    frames: { more: 'Mehr', hub: 'Feedback & Ideen (heute)', sheet: 'Feedback senden (heute)', entry: 'Wahl des Wegs', form: 'Meldeformular', done: 'Bestätigung' },
    formTitle: 'Das Meldeformular (gleich in RC1–RC3)',
    formNote: 'Felder und Hilfetexte aus Legals B.4, Wort für Wort, mit zwei Kürzungen: Die Screenshot-Zeile verliert „in der App“, und die Hilfe unter „Wo ist der Inhalt?“ behält nur den Satz für die App, sichtbar, sobald etwas gewählt ist. Aus Mehr geöffnet ist nichts vorausgewählt, darum öffnet „Wo ist der Inhalt?“ eine Auswahl über Einträge, Listen, Haushaltsname und Fotos des Haushalts, mit Suche und „Woanders“ für freien Text.',
    formFrames: { filled: 'Ausgefüllt', picker: 'Wo: die Auswahl', csam: 'Kindesmissbrauch: zunächst anonym', errors: 'Senden mit fehlenden Feldern', else: 'Wo: woanders', over: 'Über 5.000 Zeichen', bottom: 'Gutglauben und Senden' },
    pick: 'Wahl', runner: 'Zweite Wahl', jump: 'Empfehlung und Messtabelle',
  },
}[S.lang];

export const optionText = {
  en: {
    today: ['Today (main)', 'FB4’s “Feedback & ideas” row and hub. There is no report entry in the app; reporting works only by e-mail.'],
    RC1: ['RC1 Chooser sheet', 'The More row becomes “Feedback & reports”. A tap opens a small sheet with two equal choices: “Feedback & ideas” (the hub as today) and “Report content” (the form). One more tap to reach the hub than today. Without FB4 the first choice is “Send feedback” and opens the feedback sheet.'],
    RC2: ['RC2 Two buttons in the hub', 'The row keeps “Feedback & ideas” and gets the subtitle “Also: report content”. The hub opens as today, with “Report content” as a second button right under “Write to Snacklist Support”, above Your notes. Peter’s NR1 shape and Legal’s wording. Without FB4 the row is “Send feedback” with the same subtitle, and the button sits at the top of the feedback sheet.'],
    RC3: ['RC3 Its own More row', '“Report content” is also a row of its own in More, right under “Feedback & ideas” in the same group, and the hub keeps RC2’s second button (N-226 wants it next to “Write to Snacklist Support”). Reporting is one tap from More, at the cost of a row everyone sees. Without FB4 the row sits under “Send feedback” and the button at the top of the feedback sheet.'],
  },
  de: {
    today: ['Heute (main)', 'FB4s Zeile „Feedback & Ideen“ und die Übersicht. In der App gibt es keinen Meldeweg; melden geht nur per E-Mail.'],
    RC1: ['RC1 Auswahlblatt', 'Die Zeile in Mehr heißt „Feedback & Meldungen“. Ein Tipp öffnet ein kleines Blatt mit zwei gleichrangigen Wegen: „Feedback & Ideen“ (die Übersicht wie heute) und „Inhalt melden“ (das Formular). Ein Tipp mehr bis zur Übersicht als heute. Ohne FB4 heißt die erste Wahl „Feedback senden“ und öffnet das Feedback-Blatt.'],
    RC2: ['RC2 Zwei Knöpfe in der Übersicht', 'Die Zeile behält „Feedback & Ideen“ und bekommt die Unterzeile „Auch: Inhalte melden“. Die Übersicht öffnet wie heute, mit „Inhalt melden“ als zweitem Knopf direkt unter „An Snacklist Support schreiben“, über Deine Notizen. Peters NR1 und Legals Wortlaut. Ohne FB4 heißt die Zeile „Feedback senden“ mit derselben Unterzeile, und der Knopf steht oben im Feedback-Blatt.'],
    RC3: ['RC3 Eigene Zeile in Mehr', '„Inhalt melden“ ist zusätzlich eine eigene Zeile in Mehr, direkt unter „Feedback & Ideen“ in derselben Gruppe, und die Übersicht behält RC2s zweiten Knopf (N-226 will ihn neben „An Snacklist Support schreiben“). Melden ist einen Tipp entfernt, um den Preis einer Zeile, die alle sehen. Ohne FB4 steht die Zeile unter „Feedback senden“ und der Knopf oben im Feedback-Blatt.'],
  },
}[S.lang];

const t = copy[S.lang];
const filled = () => ({ ...blankForm(), kind: 'insult', where: { kind: 'item', label: t.items[0][1] }, reason: t.sample, good: true });
const doneState = (stack) => ({ screen: 'done', stack, form: filled(), ref: 'R-7K2M4Q' });

// Each option's storyboard: [frame key, starting state]. Every phone stays live from there.
export const boards = {
  today: fb4 ? [['more', { scrollTo: 'feedback' }], ['hub', { screen: 'hub', stack: ['more'] }]] : [['more', { scrollTo: 'feedback' }], ['sheet', { scrollTo: 'feedback', sheet: 'compose' }]],
  RC1: [['more', { scrollTo: 'feedback' }], ['entry', { scrollTo: 'feedback', sheet: 'chooser' }], ['form', { screen: 'form', stack: ['more'] }], ['done', doneState(['more', 'form'])]],
  RC2: fb4
    ? [['more', { scrollTo: 'feedback' }], ['entry', { screen: 'hub', stack: ['more'] }], ['form', { screen: 'form', stack: ['more', 'hub'] }], ['done', doneState(['more', 'hub', 'form'])]]
    : [['more', { scrollTo: 'feedback' }], ['entry', { scrollTo: 'feedback', sheet: 'compose' }], ['form', { screen: 'form', stack: ['more'] }], ['done', doneState(['more', 'form'])]],
  RC3: [['more', { scrollTo: 'feedback' }], ['entry', { scrollTo: 'feedback', press: 'report' }], ['form', { screen: 'form', stack: ['more'] }], ['done', doneState(['more', 'form'])]],
  form: [
    ['filled', { screen: 'form', stack: ['more'], form: filled() }],
    ['picker', { screen: 'form', stack: ['more'], sheet: 'where' }],
    ['csam', { screen: 'form', stack: ['more'], form: { ...blankForm(), kind: 'csam', contactShown: false }, scrollToField: 'contact' }],
    ['errors', { screen: 'form', stack: ['more'], form: { ...blankForm(), tried: true }, scrollToField: 'kind' }],
    ['over', { screen: 'form', stack: ['more'], form: { ...filled(), reason: `${t.sample} `.repeat(60).slice(0, 5012), tried: true }, scrollToField: 'reason' }],
    ['else', { screen: 'form', stack: ['more'], form: { ...blankForm(), kind: 'insult', where: { kind: 'else' } }, scrollToField: 'where' }],
    ['bottom', { screen: 'form', stack: ['more'], form: filled(), scrollBottom: true }],
  ],
};

async function themeCss() {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
}

// The recommendation is RECOMMENDATION.md (or .de.md): one source for the page and the PR.
function md(src) {
  const inline = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>');
  const out = [];
  const lines = src.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (/^# |^<!--/.test(l)) continue;
    if (/^## /.test(l)) out.push(`<h2>${inline(l.slice(3))}</h2>`);
    else if (/^### /.test(l)) out.push(`<h3>${inline(l.slice(4))}</h3>`);
    else if (/^\|/.test(l)) {
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(lines[i++]);
      i--;
      const cells = (r) => r.slice(1, -1).split('|').map((c) => c.trim());
      out.push(`<div class="table-wrap"><table><tr>${cells(rows[0]).map((c) => `<th>${inline(c)}</th>`).join('')}</tr>${rows.slice(2).map((r) => `<tr>${cells(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</table></div>`);
    } else if (/^\d+\. |^- /.test(l)) {
      const ordered = /^\d/.test(l);
      const items = [];
      while (i < lines.length && /^\d+\. |^- /.test(lines[i])) items.push(lines[i++].replace(/^\d+\. |^- /, ''));
      i--;
      out.push(`<${ordered ? 'ol' : 'ul'}>${items.map((x) => `<li>${inline(x)}</li>`).join('')}</${ordered ? 'ol' : 'ul'}>`);
    } else if (l.trim()) out.push(`<p>${inline(l)}</p>`);
  }
  return out.join('\n');
}

const btn = (k, v, label) => `<button data-set="${k}=${v}" aria-pressed="${String(S[k]) === String(v)}">${label}</button>`;

async function main() {
  await themeCss();
  document.documentElement.className = `th-${S.theme}`;
  document.documentElement.lang = S.lang;
  document.title = W.title;
  const rec = await (await fetch(S.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md')).text();
  const pickId = rec.match(/<!-- pick: (\w+) -->/)?.[1];
  const runnerId = rec.match(/<!-- runner-up: (\w+) -->/)?.[1];
  const overview = document.body.dataset.overview;
  const tag = (id) => (id === pickId ? `<span class="tag pick">${W.pick}</span>` : id === runnerId ? `<span class="tag runner">${W.runner}</span>` : '');
  const app = document.getElementById('app');
  const section = (id) => `<section class="option" id="${id}" data-option="${id}"><h2>${optionText[id][0]}${tag(id)}</h2><p>${optionText[id][1]}</p><div class="frames">${boards[id].map(([f], i) => `<figure class="cell"><figcaption>${W.frames[f]}</figcaption><div class="phone" data-frame="${id}:${f}" data-i="${i}"></div></figure>`).join('')}</div></section>`;
  app.innerHTML = `<header class="page-head">
      <div class="title-row"><h1>${W.title}</h1>${overview ? `<a class="back-link" href="${overview}${S.lang === 'de' ? '?lang=de' : ''}">← ${W.back}</a>` : ''}</div>
      <p class="note">${W.note}</p>
      <div class="controls">${btn('lang', 'en', 'English')}${btn('lang', 'de', 'Deutsch')}<span class="sep"></span>${btn('theme', 'light', W.light)}${btn('theme', 'dark', W.dark)}<span class="sep"></span>${btn('ts', 100, `${W.text} 100 %`)}${btn('ts', 200, `${W.text} ${W.largest}`)}<span class="sep"></span>${btn('fb4', 'on', W.fb4on)}${btn('fb4', 'off', W.fb4off)}</div>
      <p class="note">${W.fb4Note}</p>
      <p class="note"><b>${W.pick}: ${optionText[pickId]?.[0] ?? ''}</b> · ${W.runner}: ${optionText[runnerId]?.[0] ?? ''} · <a href="#rec">${W.jump} ↓</a></p>
    </header>
    <div class="view">
      <section class="legal"><h2>${W.legalTitle}</h2><ul>${W.legal.map((x) => `<li>${x}</li>`).join('')}</ul></section>
      ${['RC1', 'RC2', 'RC3', 'today'].map(section).join('')}
      <section class="option" id="form" data-option="form"><h2>${W.formTitle}</h2><p>${W.formNote}</p><div class="frames">${boards.form.map(([f], i) => `<figure class="cell"><figcaption>${W.formFrames[f]}</figcaption><div class="phone" data-frame="form:${f}" data-i="${i}"></div></figure>`).join('')}</div></section>
      <section class="rec" id="rec">${md(rec)}</section>
    </div>`;
  for (const el of app.querySelectorAll('.phone')) {
    const [id] = el.dataset.frame.split(':');
    const state = structuredClone(boards[id][+el.dataset.i][1]);
    if (S.ts === 200) el.classList.add('ts200');
    el.phone = new Phone(el, { option: id === 'form' ? 'RC2' : id, lang: S.lang, fb4, state });
  }
  app.querySelectorAll('[data-set]').forEach((b) => b.addEventListener('click', () => {
    const [k, v] = b.dataset.set.split('=');
    const q = new URLSearchParams(location.search);
    const def = { lang: 'en', theme: 'light', ts: '100', fb4: 'on' }[k];
    if (v === def) q.delete(k); else q.set(k, v);
    location.search = q.toString();
  }));
  fit();
  addEventListener('resize', fit);
  document.body.dataset.ready = '1';
}

// On a phone the 390 px phones shrink to the screen.
function fit() {
  const z = Math.min(1, (innerWidth - 20) / 394);
  document.querySelectorAll('.phone').forEach((p) => { p.style.zoom = z < 1 ? String(z) : ''; });
}

main();
