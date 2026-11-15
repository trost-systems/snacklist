// Today and FB1–FB5. Each flow is a small state machine: `screens` render one phone state each, elements with
// `data-go` lead to the next state, and `path[scenario]` is the shortest way from the list to a sent note in
// that situation. The storyboard (`story`) is the five required steps: enter, attach, send (the route card),
// after, Peter, plus `also` frames for entries that don't belong to one scenario (a crash, a survey, a +1).
import { chrome, scenarios, money } from './model.js';
import { L, esc, ic, go, tact, listScreen, moreScreen, moreRow, sheet, messageField, typeChips, contactBox, attPanel, snack, desk, kv, route, statusBar } from './ui.js';

const t = (en, de) => ({ en, de });
const de = (c) => c.lang === 'de';

// A refused write shows today's snackbar in every flow; only FB3 gives it a Report action.
const rejectSnack = (c, action = '') => snack(c, L(c, scenarios.error.snack), action);
const listFor = (c, o = {}) => listScreen(c, { snack: c.scen === 'error' && !o.snack ? rejectSnack(c) : o.snack, ...o });

// Hops every flow on today's stack shares. The mail hop is job 225's digest, as built (docs/FEEDBACK.md).
const hopApp = { what: t('The app sends the note', 'Die App schickt die Notiz'), where: t('HTTPS, signed in', 'HTTPS, angemeldet') };
const hopTable = {
  what: t('public.feedback, one row', 'public.feedback, eine Zeile'),
  where: t('Supabase, Frankfurt (EU)', 'Supabase, Frankfurt (EU)'),
  reader: t('Clients may only insert; Peter reads by hand in the dashboard.', 'Clients dürfen nur einfügen; Peter liest von Hand im Dashboard.'),
};
const hopDigest = {
  what: t('Daily digest mail (job 225, off until Legal GO)', 'Tägliche Sammelmail (Job 225, aus bis Legal-GO)'),
  where: t('Resend (sends from Ireland, keeps mails 30 days in the US; DPF + SCCs, as for sign-in mails) → hello@snacklist.app (Google Workspace)', 'Resend (versendet aus Irland, hält Mails 30 Tage in den USA; DPF + SCC, wie bei Anmelde-Mails) → hello@snacklist.app (Google Workspace)'),
  reader: t('Peter alone reads the mailbox; no bot, connector or routine, and Workspace’s AI features stay off for it.', 'Nur Peter liest das Postfach; kein Bot, Connector oder Ablauf, und die KI-Funktionen von Workspace bleiben dafür aus.'),
};

const tableRow = (c, extra = []) => {
  const over = new Map(extra);
  const base = [
      ['created_at', '2026-11-15 18:44 (Berlin)'],
      ['category', scenarios[c.scen].category],
      ['message', L(c, scenarios[c.scen].message)],
      ['screen', 'list'],
      ['platform · os_version', 'ios · iOS 26.1'],
      ['app_version (build)', '1.4.0 (1325)'],
      ['locale', c.lang],
      ['contact_ok', 'false'],
  ];
  // A flow's own rows replace the base row of the same column, so no column shows twice.
  const rows = [...base.map(([k, v]) => [k, over.get(k) ?? v]), ...extra.filter(([k]) => !base.some(([b]) => b === k))];
  return desk('Supabase · Table Editor · public.feedback', kv(rows), de(c) ? 'Peter, von Hand, Projekt jdwq…' : 'Peter, by hand, project jdwq…');
};

const digest = (c, lines = [], msg = L(c, scenarios[c.scen].message)) =>
  desk(
    'hello@snacklist.app · Snacklist feedback digest 2026-11-16 (3 new)',
    `<pre>18:44  ${scenarios[c.scen].category}
${msg ? `&gt; ${esc(msg)}\n` : ''}ios · 1.4.0 (1325) · Premium: no · Reply allowed: no${lines.length ? `\n${lines.map(esc).join('\n')}` : ''}

09:12  idea
&gt; …</pre>`,
    de(c) ? 'Peters Postfach; englische Labels wie heute im Digest' : 'Peter’s mailbox; English labels as in today’s digest',
  );

const formBody = (c, { att, teach, extraTop = '', contact = true, sendTo = 'sent', chips = true, msg } = {}) =>
  `${teach ?? ''}${extraTop}${messageField(c, msg)}${chips ? typeChips(c) : ''}${contact ? contactBox(c) : ''}${att ?? `<p class="included">${c.T.included}</p>`}<div class="actions">${tact(c.T.send, { to: sendTo, honey: true, testid: 'send' })}</div>`;

// Today's edit sheet (edit_item_sheet.dart): name, quantity, the store and category chips that fold out.
const cats = [
  ['fruit', t('Fruit & veg', 'Obst & Gemüse'), 'categoryProduce'],
  ['bread', t('Bread & bakery', 'Brot & Backwaren'), 'categoryBakery'],
  ['chilled', t('Chilled', 'Kühlregal'), 'categoryChilled'],
  ['pantry', t('Pantry', 'Vorrat & Konserven'), 'categoryPantry'],
  ['sweets', t('Sweets & snacks', 'Süßes & Snacks'), 'categorySweets'],
  ['drinks', t('Drinks', 'Getränke'), 'categoryDrinks'],
];
const editSheet = (c, { open, picked } = {}) =>
  sheet(
    c,
    de(c) ? 'Bearbeiten' : 'Edit',
    `<div class="field"><label>${de(c) ? 'Bezeichnung' : 'Name'}</label><span style="font-size:calc(17px * var(--ts,1))">${de(c) ? 'Hafermilch' : 'Oat milk'}</span></div>
    <div class="chips"><span class="chip"><span>${c.T.noStore}</span></span><button class="chip ${picked ? 'on' : ''}" ${open || picked ? '' : go('editcat')} data-testid="category-chip"><span>${L(c, cats[picked ? 2 : 3][1])} ${ic(open ? 'expand_less' : 'expand_more', 'sm')}</span></button></div>
    ${open ? `<div class="chips" data-testid="categories">${cats.map(([k, n]) => `<button class="chip ${k === 'pantry' ? 'on' : ''}" ${k === 'chilled' ? go('picked') : ''} data-cat="${k}"><span>${L(c, n)}</span></button>`).join('')}</div>` : ''}
    <div class="actions">${tact(c.T.cancel)}${tact(de(c) ? 'Fertig' : 'Done', { to: picked ? 'moved' : undefined, honey: true, testid: 'done' })}</div>`,
  );

// FB2's screenshot: the live list screen as the app draws it for a report, every list text and emoji as a bar.
const shotRow = (c, it) => {
  const reveal = it.id === 'oat' && c.att.reveal;
  return `<div class="mini-row ${it.id === 'oat' && c.att.mark ? 'marked' : ''}" ${it.id === 'oat' ? `data-tog="reveal" role="button" aria-label="${de(c) ? 'Zeile aufdecken' : 'Reveal this row'}"` : ''}>${reveal ? `<span>🥣</span><b>${de(c) ? 'Hafermilch' : 'Oat milk'}</b>` : `<span class="redact" style="width:14px"></span><span class="redact" style="width:${30 + it.en.length * 4}px"></span>`}</div>`;
};
const shotScreen = (c) => {
  const groups = [
    ['Fruit & veg', [{ en: 'Bananas' }, { en: 'Apples' }]],
    ['Chilled', [{ en: 'Milk' }, { en: 'Butter' }]],
    ['Pantry', [{ en: 'Pasta' }, { id: 'oat', en: 'Oat milk' }, { en: 'Rice' }]],
  ];
  return `<div class="shot" data-testid="screenshot"><div class="mini-bar"><span class="redact" style="width:90px"></span><span class="grow"></span><span class="mini-btn">${de(c) ? 'Bearbeiten' : 'Edit'}</span></div>
  <div class="mini-bar"><span class="redact" style="width:56px"></span><span class="grow"></span><span>9</span></div>
  ${groups.map(([cat, items]) => `<div class="mini-cat"><span class="redact" style="width:${cat.length * 5}px"></span></div>${items.map((it) => shotRow(c, it)).join('')}`).join('')}
  <div class="mini-bar"><span class="redact" style="width:70px;opacity:.5"></span><span class="grow"></span><b>${money(c.lang)}</b></div></div>`;
};

export { cats };

export const flows = [
  {
    id: 'today',
    name: t('Today: More → Send feedback', 'Heute: Mehr → Feedback senden'),
    line: t('Main’s form: a note, an optional type and contact box, a fixed “Included” line, then “Thanks!”.', 'Das Formular auf main: Notiz, optionale Art und Kontakt-Häkchen, feste Zeile „Wird mitgeschickt“, dann „Danke!“.'),
    stack: true,
    service: null,
    answer: t('by mail, if ticked', 'per Mail, wenn angehakt'),
    shake: { mode: 'none', text: t('No shake (#281 is on hold, not on main).', 'Kein Schütteln (#281 ist angehalten, nicht auf main).') },
    facts: {
      enter: t('More → Send feedback. The only entry.', 'Mehr → Feedback senden. Der einzige Einstieg.'),
      attach: t('Version, build, platform, OS, language, the screen before More. Fixed; no preview, nothing to remove.', 'Version, Build, Plattform, OS, Sprache, der Bildschirm vor Mehr. Fest; keine Vorschau, nichts abwählbar.'),
      send: t('public.feedback (Supabase, Frankfurt).', 'public.feedback (Supabase, Frankfurt).'),
      after: t('Snackbar “Thanks!”. Nothing later.', 'Snackbar „Danke!“. Danach nichts.'),
      peter: t('Table Editor by hand; the digest mail is built but off.', 'Table Editor von Hand; die Sammelmail ist gebaut, aber aus.'),
    },
    build: { days: 0, text: t('Live on main.', 'Auf main live.') },
    processors: [],
    att: () => [{ key: 'screen', fixed: true }, { key: 'version', fixed: true }, { key: 'device', fixed: true }, { key: 'language', fixed: true }],
    defaults: {},
    path: { bug: ['list', 'more', 'form', 'sent'], error: ['list', 'more', 'form', 'sent'], idea: ['list', 'more', 'form', 'sent'] },
    story: () => [
      { step: 'enter', state: 'more' },
      { step: 'attach', state: 'form' },
      { step: 'send' },
      { step: 'after', state: 'sent' },
      { step: 'peter' },
    ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' } }),
      more: (c) => moreScreen(c, { fbTo: 'form', hot: true }),
      form: (c) => moreScreen(c) + sheet(c, c.T.fbTitle, formBody(c), { closeTo: 'more' }),
      sent: (c) => moreScreen(c, { snack: snack(c, c.T.thanks) }),
    },
    route: (c) => route(c, [hopApp, hopTable], t('The digest (job 225) would mail it to Peter once switched on.', 'Die Sammelmail (Job 225) würde sie Peter schicken, sobald sie an ist.')),
    peter: (c) => tableRow(c),
  },

  {
    id: 'FB1',
    name: t('More + shake, with a preview', 'Mehr + Schütteln, mit Vorschau'),
    line: t('#281 done right: shake on phones opens today’s form about the live screen; every attached field is listed with its value and can be switched off.', '#281 sauber: Schütteln öffnet auf dem Telefon das heutige Formular zum aktuellen Bildschirm; jedes mitgeschickte Feld steht mit Wert da und lässt sich abschalten.'),
    stack: true,
    service: null,
    answer: t('by mail, if ticked', 'per Mail, wenn angehakt'),
    shake: {
      mode: 'on',
      text: t(
        'On by default on iOS and Android, inside the signed-in app only (#281’s detector: 3 swings over 2.7 g within 800 ms; after it fires, 1.5 s before it can fire again; nothing while a sheet or dialog is open, nothing on sign-in or onboarding). Settings → “Shake to send feedback” turns it off. Web and desktop: no-op. It reports the live screen’s name, never a screenshot. More stays and reports the screen before More.',
        'Auf iOS und Android standardmäßig an, nur in der angemeldeten App (Detektor aus #281: 3 Ausschläge über 2,7 g in 800 ms; nach dem Auslösen 1,5 s Pause; nichts bei offenem Blatt oder Dialog, nichts bei Anmeldung oder Einrichtung). Einstellungen → „Schütteln für Feedback“ schaltet es ab. Web und Desktop: nichts. Es meldet den Namen des aktuellen Bildschirms, nie ein Bildschirmfoto. Mehr bleibt und meldet den Bildschirm vor Mehr.',
      ),
    },
    facts: {
      enter: t('Shake anywhere in the app, or More → Send feedback.', 'Überall in der App schütteln, oder Mehr → Feedback senden.'),
      attach: t('“Sent along” lists each field with its value: screen, system, device model, display (theme, text size, online) and Premium with a switch; version and language always. No list content can be attached.', '„Wird mitgeschickt“ zeigt jedes Feld mit Wert: Bildschirm, System, Gerätemodell, Anzeige (Design, Textgröße, online) und Premium mit Schalter; Version und Sprache immer. Listeninhalte gehen nie mit.'),
      send: t('public.feedback with #281’s context columns.', 'public.feedback mit den Kontextspalten aus #281.'),
      after: t('“Thanks! Peter reads every note himself.” The note shows up in “Export my data”.', '„Danke! Peter liest jede Notiz selbst.“ Die Notiz steht in „Meine Daten exportieren“.'),
      peter: t('Daily digest with the context fields, and the Table Editor.', 'Tägliche Sammelmail mit den Kontextfeldern und der Table Editor.'),
    },
    build: { days: 3, text: t('#281 exists (shake, context fields, migration, Legal GO conditions). Add the per-field preview and switches, the Settings toggle; §10 already covers #281’s fields.', '#281 gibt es (Schütteln, Kontextfelder, Migration, Legal-GO-Bedingungen). Dazu: Vorschau je Feld mit Schaltern, Schalter in den Einstellungen; §10 deckt die Felder aus #281 schon ab.') },
    processors: [],
    att: () => [{ key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }, { key: 'model' }, { key: 'language', fixed: true }, { key: 'display' }, { key: 'plan' }],
    defaults: { screen: true, device: true, model: true, display: true, plan: true },
    gestures: { list: { shake: 'form' } },
    path: { bug: ['list', 'form', 'sent'], error: ['list', 'form', 'sent'], idea: ['list', 'form', 'sent'] },
    story: () => [
      { step: 'enter', state: 'list', shake: true },
      { step: 'attach', state: 'form' },
      { step: 'send' },
      { step: 'after', state: 'sent' },
      { step: 'peter' },
      { step: 'also', state: 'settings', caption: t('Shake can be switched off; More → Send feedback opens the same form.', 'Schütteln lässt sich abschalten; Mehr → Feedback senden öffnet dasselbe Formular.') },
    ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' } }),
      more: (c) => moreScreen(c, { fbTo: 'form', hot: true, settingsTo: 'settings' }),
      form: (c) =>
        listFor(c, { snack: '' }) +
        sheet(
          c,
          c.T.fbTitle,
          formBody(c, {
            teach: `<p class="teach">${ic('vibration', 'sm')}<span>${de(c) ? 'Aus Versehen geschüttelt? Schließen, der Entwurf bleibt. Abschalten: Einstellungen → Schütteln für Feedback.' : 'Shook it by accident? Close this; your draft stays. Turn it off in Settings → Shake to send feedback.'}</span></p>`,
            att: attPanel(c, flows[1].att()),
          }),
          { closeTo: 'list' },
        ),
      sent: (c) => listFor(c, { snack: snack(c, de(c) ? 'Danke! Peter liest jede Notiz selbst.' : 'Thanks! Peter reads every note himself.') }),
      settings: (c) =>
        `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.back}">${ic('arrow_back')}</button><h2>${c.T.settings}</h2></div><div class="scroll"><div class="group-card">
        <div class="mrow"><span class="hexface"><span>${ic('vibration')}</span></span><span class="grow"><span>${de(c) ? 'Schütteln für Feedback' : 'Shake to send feedback'}</span><small>${de(c) ? 'Telefon schütteln öffnet das Feedback-Formular zum aktuellen Bildschirm.' : 'Shaking the phone opens the feedback form about the screen you are on.'}</small></span><span class="sw on" role="switch" aria-checked="true"></span></div></div></div>`,
    },
    route: (c) => route(c, [hopApp, { ...hopTable, what: t('public.feedback + context columns (#281)', 'public.feedback + Kontextspalten (#281)') }, hopDigest], t('Switched-off fields are not sent at all (null), not hidden later.', 'Abgeschaltete Felder werden gar nicht gesendet (null), nicht später versteckt.')),
    peter: (c) => digest(c, ['entry: shake · screen: list · iPhone 15 · dark · text 130 % · online']) + tableRow(c, [['entry_point', 'shake'], ['device_model', 'iPhone 15'], ['theme · text_scale', 'dark · 1.3'], ['online', 'true']]),
  },

  {
    id: 'FB2',
    name: t('Shake, then mark it on a screenshot', 'Schütteln, dann im Bildschirmfoto markieren'),
    line: t('Instabug/Shake style on our own stack: a shake asks first; the user picks “with screenshot” and gets the screen as the app draws it with every list text and emoji blacked out, circles the problem, may reveal one row, and sees the recent steps and switches before sending.', 'Wie Instabug/Shake, aber auf unserem Stack: Schütteln fragt erst; wer „mit Bildschirmfoto“ wählt, bekommt den Bildschirm so, wie die App ihn mit geschwärzten Listentexten und Symbolen zeichnet, kreist das Problem ein, kann eine Zeile aufdecken und sieht die letzten Schritte und Schalter vor dem Senden.'),
    stack: true,
    service: null,
    answer: t('by mail, if ticked', 'per Mail, wenn angehakt'),
    shake: {
      mode: 'confirm',
      text: t(
        'On by default on iOS and Android, but a shake first asks “Report a problem with this screen?” (with screenshot, without, not now), so an accidental shake in the shop costs one tap. #281’s detector and quiet rules; off in Settings. The screenshot is the live screen at the moment of the shake. Web: no shake; More → “Report a problem” uses the screen before More.',
        'Auf iOS und Android standardmäßig an, aber ein Schütteln fragt zuerst „Problem mit diesem Bildschirm melden?“ (mit Bildschirmfoto, ohne, nicht jetzt), damit ein versehentliches Schütteln im Laden einen Tipp kostet. Detektor und Ruheregeln aus #281; in den Einstellungen abschaltbar. Das Bildschirmfoto ist der Bildschirm im Moment des Schüttelns. Web: kein Schütteln; Mehr → „Problem melden“ nimmt den Bildschirm vor Mehr.',
      ),
    },
    facts: {
      enter: t('Shake → “Report a problem with this screen?” → With screenshot. Or More → Report a problem.', 'Schütteln → „Problem mit diesem Bildschirm melden?“ → Mit Bildschirmfoto. Oder Mehr → Problem melden.'),
      attach: t('A screenshot the app draws itself with household, store, category and item names and emoji as bars (not pixel masking); highlight and black-out tools; tap a bar to reveal that one row. Then the last 8 steps (fixed names, kept only on the phone until a report), feature switches, system and model, all with switches.', 'Ein Bildschirmfoto, das die App selbst zeichnet, mit Haushalts-, Laden-, Kategorie- und Eintragsnamen und Symbolen als Balken (keine Pixel-Maske); Markieren und Schwärzen; Tipp auf einen Balken deckt genau diese Zeile auf. Dann die letzten 8 Schritte (feste Namen, bis zu einer Meldung nur auf dem Telefon), Funktionsschalter, System und Modell, alles mit Schaltern.'),
      send: t('public.feedback plus the image in a private Storage bucket (Supabase, Frankfurt), deleted with the note.', 'public.feedback plus das Bild in einem privaten Storage-Bucket (Supabase, Frankfurt), gelöscht mit der Notiz.'),
      after: t('“Sent with your screenshot. Thanks!”', '„Mit Bildschirmfoto gesendet. Danke!“'),
      peter: t('Table Editor row with the steps and switches; the image in the Storage viewer; the digest says “screenshot: yes” without the image.', 'Zeile im Table Editor mit Schritten und Schaltern; das Bild im Storage-Viewer; die Sammelmail sagt „Bildschirmfoto: ja“, ohne Bild.'),
    },
    build: { days: 7, text: t('Redacting renderer for the screenshot, editor, private bucket with RLS and retention, on-device step buffer, #281’s device_model column, policy text for images and steps.', 'Schwärzender Renderer fürs Bildschirmfoto, Editor, privater Bucket mit RLS und Aufbewahrung, Schritt-Puffer auf dem Gerät, Spalte device_model aus #281, Datenschutztext für Bilder und Schritte.') },
    processors: [],
    att: (scen) => (scen === 'idea' ? [{ key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }] : [{ key: 'shot' }, { key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }, { key: 'model' }, { key: 'steps' }, { key: 'flags' }]),
    defaults: { shot: true, screen: true, device: true, model: true, steps: true, flags: true, reveal: false, mark: true },
    gestures: { list: { shake: 'ask' } },
    path: { bug: ['list', 'ask', 'shot', 'details', 'sent'], error: ['list', 'ask', 'shot', 'details', 'sent'], idea: ['list', 'more', 'form', 'sent'] },
    story: (scen) =>
      scen === 'idea'
        ? [
            { step: 'enter', state: 'more', caption: t('An idea needs no screenshot: More → Send an idea.', 'Eine Idee braucht kein Bildschirmfoto: Mehr → Idee senden.') },
            { step: 'attach', state: 'form', caption: t('Screen, version and system with switches; no screenshot, steps or switches for an idea.', 'Bildschirm, Version und System mit Schaltern; kein Bildschirmfoto, keine Schritte oder Schalter bei einer Idee.') },
            { step: 'send', caption: t('public.feedback, as today; no image.', 'public.feedback, wie heute; kein Bild.') },
            { step: 'after', state: 'sent', caption: t('“Thanks!”, as today.', '„Danke!“, wie heute.') },
            { step: 'peter', caption: t('The note in the digest and the Table Editor.', 'Die Notiz in Sammelmail und Table Editor.') },
          ]
        : [
            { step: 'enter', state: 'ask', shake: true },
            { step: 'attach', state: 'shot', att: { reveal: scen === 'bug' } },
            { step: 'attach', state: 'details', caption: t('Then the steps, switches and device, each with a switch.', 'Dann Schritte, Schalter und Gerät, jeweils mit Schalter.') },
            { step: 'send' },
            { step: 'after', state: 'sent' },
            { step: 'peter' },
          ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' } }),
      more: (c) =>
        moreScreen(c, {
          fbRows: [
            moreRow(c, { icon: 'bug_report_outlined', label: de(c) ? 'Problem melden' : 'Report a problem', sub: de(c) ? 'Mit Bildschirmfoto des letzten Bildschirms' : 'With a screenshot of the last screen' }),
            moreRow(c, { icon: 'feedback_outlined', label: de(c) ? 'Idee oder Lob senden' : 'Send an idea or praise', to: 'form', hot: true, testid: 'more-feedback' }),
          ],
        }),
      form: (c) => moreScreen(c) + sheet(c, de(c) ? 'Idee senden' : 'Send an idea', formBody(c, { att: attPanel(c, flows[2].att('idea')) }), { closeTo: 'more' }),
      ask: (c) =>
        listFor(c, { snack: '' }) +
        `<div class="scrim"></div><div class="dialog" role="dialog"><h3>${de(c) ? 'Problem mit diesem Bildschirm melden?' : 'Report a problem with this screen?'}</h3><p class="muted">${de(c) ? 'Mit Bildschirmfoto siehst du es vor dem Senden. Namen und Symbole aus der Liste sind geschwärzt.' : 'With a screenshot, you see it before anything is sent. Names and emoji from the list are blacked out.'}</p><div class="actions">${tact(c.T.notNow, { to: 'list' })}${tact(de(c) ? 'Ohne Bild' : 'Without')}${tact(de(c) ? 'Mit Bildschirmfoto' : 'With screenshot', { to: 'shot', honey: true, testid: 'report' })}</div></div>`,
      shot: (c) =>
        `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.close}" ${go('list')}>${ic('close')}</button><h2 class="grow">${de(c) ? 'Was ist falsch?' : 'What’s wrong?'}</h2>${tact(de(c) ? 'Weiter' : 'Next', { to: 'details', honey: true, testid: 'next' })}</div>
        <div class="scroll" style="display:grid;gap:12px;align-content:start;padding-bottom:calc(var(--safe) + 24px)">
          ${shotScreen(c)}
          <div class="tools"><button class="tool ${c.att.mark ? 'on' : ''}" data-tog="mark">${ic('brush', 'sm')}${de(c) ? 'Markieren' : 'Highlight'}</button><button class="tool">${ic('visibility_off_outlined', 'sm')}${de(c) ? 'Schwärzen' : 'Black out'}</button><button class="tool" data-tog="shot">${ic('delete_outline', 'sm')}${de(c) ? 'Ohne Bild' : 'No picture'}</button></div>
          <p class="included">${c.att.reveal ? (de(c) ? 'Eine Zeile ist aufgedeckt: „Hafermilch“ geht mit. Tipp sie an, um sie wieder zu schwärzen.' : 'One row is revealed: “Oat milk” will be sent. Tap it to black it out again.') : de(c) ? 'Alle Namen und Symbole aus der Liste sind geschwärzt. Tipp eine Zeile an, um nur diese aufzudecken.' : 'All names and emoji from the list are blacked out. Tap one row to reveal just that one.'}</p>
        </div>`,
      details: (c) => `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.back}" ${go('shot')}>${ic('arrow_back')}</button><h2 class="grow">${de(c) ? 'Problem melden' : 'Report a problem'}</h2></div>
        <div class="scroll" style="display:grid;gap:12px;align-content:start;padding-bottom:calc(var(--safe) + 16px)">${messageField(c)}${attPanel(c, flows[2].att('bug'))}${contactBox(c)}<div class="actions">${tact(c.T.send, { to: 'sent', honey: true, testid: 'send' })}</div></div>`,
      sent: (c) => (c.scen === 'idea' ? moreScreen(c, { snack: snack(c, c.T.thanks) }) : listFor(c, { snack: snack(c, de(c) ? 'Mit Bildschirmfoto gesendet. Danke!' : 'Sent with your screenshot. Thanks!') })),
    },
    route: (c) =>
      c.scen === 'idea' ? route(c, [hopApp, hopTable, hopDigest]) :
      route(
        c,
        [
          hopApp,
          { ...hopTable, what: t('public.feedback + steps, switches', 'public.feedback + Schritte, Schalter') },
          { what: t('The image, in a private bucket', 'Das Bild, in einem privaten Bucket'), where: t('Supabase Storage, Frankfurt (EU)', 'Supabase Storage, Frankfurt (EU)'), reader: t('No client can read it back; Peter opens it in the dashboard. Deleted with the note (12 months, or with the account).', 'Kein Client kann es lesen; Peter öffnet es im Dashboard. Gelöscht mit der Notiz (12 Monate oder mit dem Konto).') },
          hopDigest,
        ],
        t('The image never goes into the mail. Off-the-shelf alternative: the Shake SDK (AWS Frankfurt), if its AI assistant can be verified off (FB-Q4).', 'Das Bild geht nie in die Mail. Fertige Alternative: das Shake-SDK (AWS Frankfurt), wenn sich sein KI-Assistent nachweislich abschalten lässt (FB-Q4).'),
      ),
    peter: (c) =>
      c.scen === 'idea' ? digest(c) + tableRow(c) :
      tableRow(c, [['steps', 'open_list, add_item, tick, open_item, change_category, …'], ['flags', 'trip-mode:on public-api:off'], ['screenshot', 'feedback-shots/7c1e….png']]) +
      desk('Supabase · Storage · feedback-shots/7c1e….png', `<div style="width:60%">${shotScreen({ ...c, att: { reveal: c.scen === 'bug', mark: true } })}</div>`, de(c) ? 'Nur über den Service-Zugang im Dashboard' : 'Service role only, in the dashboard'),
  },

  {
    id: 'FB3',
    name: t('Report this, where it happens', 'Hier melden, wo es passiert'),
    line: t('“Tell Peter” right where something went wrong: after the user moves an item to another category, on the “Change rejected” snackbar, on the paywall. The report carries that exact thing (the item and where it belongs, or the rejected change) as a chip the user can remove. More keeps a general form.', '„Peter sagen“ genau dort, wo etwas schiefging: nachdem man einen Eintrag in eine andere Kategorie schiebt, an der Snackbar „Änderung abgelehnt“, auf der Bezahlseite. Die Meldung trägt genau das (den Eintrag und wohin er gehört, oder die abgelehnte Änderung) als Chip, den man entfernen kann. Mehr behält ein allgemeines Formular.'),
    stack: true,
    service: null,
    answer: t('by mail, if ticked', 'per Mail, wenn angehakt'),
    shake: {
      mode: 'contextual',
      text: t(
        'Contextual only: for 2 minutes after a “Change rejected” snackbar or while “Sync failing” shows, a shake opens that problem’s report. Being offline does not open the window (shops often have no signal), and at any other time a shake does nothing, so a cart in the shop never opens a form. iOS and Android only; web no-op. No screenshot, only the problem and the screen. More → Send feedback stays for everything else.',
        'Nur im Zusammenhang: 2 Minuten nach einer Snackbar „Änderung abgelehnt“ oder solange „Sync gestört“ zu sehen ist, öffnet ein Schütteln die Meldung zu genau diesem Problem. Offline öffnet das Fenster nicht (im Laden fehlt oft das Netz), und sonst tut Schütteln nichts, ein Einkaufswagen öffnet also nie ein Formular. Nur iOS und Android; Web nichts. Kein Bildschirmfoto, nur das Problem und der Bildschirm. Mehr → Feedback senden bleibt für alles andere.',
      ),
    },
    facts: {
      enter: t('Fix a category as today (long-press → Edit → category → Done), then “Tell Peter” on a new snackbar; “Report” on “Change rejected: …”; “Question about the price?” on the paywall; More for the rest.', 'Kategorie wie heute korrigieren (lange drücken → Bearbeiten → Kategorie → Fertig), dann „Peter sagen“ in einer neuen Snackbar; „Melden“ an „Änderung abgelehnt: …“; „Frage zum Preis?“ auf der Bezahlseite; Mehr für alles andere.'),
      attach: t('The case as a removable chip (“Oat milk: Pantry → Chilled”, or the rejected change and its time; both name the item), then screen, version and system, each visible. A message is optional.', 'Der Fall als entfernbarer Chip („Hafermilch: Vorrat & Konserven → Kühlregal“ oder die abgelehnte Änderung mit Uhrzeit; beide nennen den Eintrag), dann Bildschirm, Version und System, alle sichtbar. Eine Nachricht ist freiwillig.'),
      send: t('public.feedback with two new columns, context_kind and context_ref (the move or the rejection; the item name only if the chip stayed). A kept chip also reaches Peter in the digest mail.', 'public.feedback mit zwei neuen Spalten, context_kind und context_ref (die Verschiebung oder die Ablehnung; der Eintragsname nur, wenn der Chip blieb). Ein behaltener Chip erreicht Peter auch in der Sammelmail.'),
      after: t('The user’s list is already right (they moved it); “Thanks, Peter sees where Oat milk belongs.”', 'Die Liste ist schon richtig (man hat verschoben); „Danke, Peter sieht, wohin Hafermilch gehört.“'),
      peter: t('The digest groups by context (“moved: Oat milk Pantry → Chilled, 3× this week”); the Table Editor filters by context_kind.', 'Die Sammelmail gruppiert nach Kontext („verschoben: Hafermilch Vorrat & Konserven → Kühlregal, 3× diese Woche“); im Table Editor nach context_kind filtern.'),
    },
    build: { days: 5, text: t('A new snackbar after a category change (today Done shows none) and “Report” on the rejection snackbar; carry the op kind and server code into ItemRejected (list_cubit.dart builds it with the item name only and drops them); a small report sheet, 2 columns with checks, relaxing the message check for context reports (today 1–2000 characters), digest grouping, the shake window from #281’s detector, §10 text for context reports.', 'Eine neue Snackbar nach dem Kategoriewechsel (heute zeigt Fertig keine) und „Melden“ an der Ablehnungs-Snackbar; Op-Art und Server-Code in ItemRejected mitführen (list_cubit.dart baut es heute nur mit dem Eintragsnamen und verwirft sie); kleines Meldeblatt, 2 Spalten mit Checks, Lockerung der Nachrichtenprüfung für Kontextmeldungen (heute 1–2000 Zeichen), Gruppierung in der Sammelmail, das Schüttel-Fenster mit dem Detektor aus #281, §10-Text für Kontextmeldungen.') },
    processors: [],
    att: (scen) =>
      scen === 'bug'
        ? [{ key: 'item' }, { key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }]
        : scen === 'error'
          ? [{ key: 'error' }, { key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }]
          : [{ key: 'version', fixed: true }, { key: 'device' }],
    defaults: { item: true, error: true, screen: true, device: true },
    gestures: (scen) => (scen === 'error' ? { list: { shake: 'report' } } : {}),
    path: { bug: ['list', 'edit', 'editcat', 'picked', 'moved', 'report', 'sent'], error: ['list', 'report', 'sent'], idea: ['list', 'more', 'form', 'sent'] },
    tapsNote: t('wrong category: 4 of the 6 taps are today’s own fix; telling Peter adds 2. Its exposure includes the item name by default', 'falsche Kategorie: 4 der 6 Tipps sind die heutige Korrektur; Peter Bescheid sagen kostet 2 mehr. Seine Exposition enthält standardmäßig den Eintragsnamen'),
    story: (scen) =>
      scen === 'bug'
        ? [
            { step: 'enter', state: 'moved', caption: t('The user fixes the category as today (long-press → Edit → Chilled → Done). New: a snackbar then offers “Tell Peter” (today Done shows none; when it shows is FB-Q10).', 'Man korrigiert die Kategorie wie heute (lange drücken → Bearbeiten → Kühlregal → Fertig). Neu: Danach bietet eine Snackbar „Peter sagen“ an (heute zeigt Fertig keine; wann sie kommt, ist FB-Q10).') },
            { step: 'attach', state: 'report' },
            { step: 'send' },
            { step: 'after', state: 'sent' },
            { step: 'peter' },
            { step: 'also', state: 'editcat', caption: t('The fix itself is today’s edit sheet, unchanged; only the snackbar after Done is new.', 'Die Korrektur selbst ist das heutige Bearbeiten-Blatt, unverändert; nur die Snackbar nach Fertig ist neu.') },
          ]
        : scen === 'error'
          ? [
              { step: 'enter', state: 'list', caption: t('“Report” on today’s “Change rejected” snackbar (or a shake within 2 minutes).', '„Melden“ an der heutigen Snackbar „Änderung abgelehnt“ (oder Schütteln innerhalb von 2 Minuten).') },
              { step: 'attach', state: 'report', caption: t('The rejected change as a removable chip (it names the item), then screen, version and system.', 'Die abgelehnte Änderung als entfernbarer Chip (sie nennt den Eintrag), dann Bildschirm, Version und System.') },
              { step: 'send' },
              { step: 'after', state: 'sent', caption: t('“Thanks, Peter gets the rejected change with it.” The change itself is handled as today.', '„Danke, Peter bekommt die abgelehnte Änderung mit.“ Die Änderung selbst läuft wie heute.') },
              { step: 'peter', caption: t('The digest line names the rejection and its time; the Table Editor filters by context_kind = rejected.', 'Die Zeile in der Sammelmail nennt die Ablehnung und ihre Uhrzeit; im Table Editor nach context_kind = rejected filtern.') },
            ]
          : [
              { step: 'enter', state: 'more', caption: t('An idea has no context: More → Send feedback, as today.', 'Eine Idee hat keinen Kontext: Mehr → Feedback senden, wie heute.') },
              { step: 'attach', state: 'form', caption: t('Today’s form with the preview: version and system; no screen when opened from More (job 259’s rule).', 'Das heutige Formular mit Vorschau: Version und System; kein Bildschirm, wenn aus Mehr geöffnet (Regel aus Job 259).') },
              { step: 'send' },
              { step: 'after', state: 'sent', caption: t('“Thanks!”, as today.', '„Danke!“, wie heute.') },
              { step: 'peter', caption: t('The note in the digest and the Table Editor (context_kind = general).', 'Die Notiz in Sammelmail und Table Editor (context_kind = general).') },
              { step: 'also', state: 'paywall', caption: t('The same pattern on the paywall.', 'Dasselbe Muster auf der Bezahlseite.') },
            ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' }, press: 'edit', snack: c.scen === 'error' ? rejectSnack(c, `<button ${go('report')} data-testid="report">${de(c) ? 'Melden' : 'Report'}</button>`) : '' }),
      edit: (c) => listScreen(c, { hot: true }) + editSheet(c),
      editcat: (c) => listScreen(c, { hot: true }) + editSheet(c, { open: true }),
      picked: (c) => listScreen(c, { hot: true }) + editSheet(c, { picked: true }),
      moved: (c) =>
        listScreen(c, {
          moved: true,
          hot: true,
          snack: snack(c, de(c) ? 'Hafermilch ist jetzt im Kühlregal.' : 'Oat milk is now in Chilled.', `<button ${go('report')} data-testid="tell-peter">${de(c) ? 'Peter sagen' : 'Tell Peter'}</button>`),
        }),
      report: (c) =>
        listScreen(c, { moved: c.scen === 'bug', hot: c.scen === 'bug' }) +
        sheet(c, c.scen === 'error' ? (de(c) ? 'Problem melden' : 'Report this problem') : de(c) ? 'Peter sagen, wohin es gehört' : 'Tell Peter where it belongs', reportBody(c), { closeTo: 'list' }),
      sent: (c) =>
        c.scen === 'idea'
          ? moreScreen(c, { snack: snack(c, c.T.thanks) })
          : listScreen(c, {
              moved: c.scen === 'bug',
              snack: snack(c, c.scen === 'error' ? (de(c) ? 'Danke, Peter bekommt die abgelehnte Änderung mit.' : 'Thanks, Peter gets the rejected change with it.') : de(c) ? 'Danke, Peter sieht, wohin Hafermilch gehört.' : 'Thanks, Peter sees where Oat milk belongs.'),
            }),
      more: (c) => moreScreen(c, { fbTo: 'form', hot: true }),
      form: (c) => moreScreen(c) + sheet(c, c.T.fbTitle, formBody(c, { att: attPanel(c, flows[3].att('idea')) }), { closeTo: 'more' }),
      paywall: (c) =>
        `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.close}">${ic('close')}</button><h2 class="grow">Snacklist Premium</h2></div><div class="scroll pad" style="display:grid;gap:12px;align-content:start">
        <p>${de(c) ? 'Mehrere Listen, Preise und Verlauf für den ganzen Haushalt.' : 'More lists, prices and history for the whole household.'}</p>
        <div class="note-card" style="margin:0;width:100%"><b>${de(c) ? 'Jährlich' : 'Yearly'}</b><span class="muted">${de(c) ? 'Preis aus dem Store' : 'Price from the store'}</span></div>
        <button class="mrow" style="padding-left:0">${ic('help_outline')}<span class="grow"><span>${de(c) ? 'Frage zum Preis oder Kauf?' : 'Question about the price or purchase?'}</span><small>${de(c) ? 'Geht an Peter, mit Store und Plan, ohne Zahlungsdaten.' : 'Goes to Peter with store and plan, no payment details.'}</small></span>${ic('chevron_right', 'sm')}</button></div>`,
    },
    route: (c) => route(c, [hopApp, { ...hopTable, what: t('public.feedback + context_kind, context_ref', 'public.feedback + context_kind, context_ref') }, hopDigest], t('context_ref holds the move or the rejection; it names the item only when the user kept the chip, and then the digest mail names it too.', 'context_ref enthält die Verschiebung oder die Ablehnung; den Eintrag nennt es nur, wenn der Chip blieb, und dann nennt ihn auch die Sammelmail.')),
    peter: (c) => {
      const item = de(c) ? 'Hafermilch' : 'Oat milk';
      return (
        digest(c, c.scen === 'bug' ? [`context: moved · “${item}” pantry → chilled · same move 3× this week (3 households that kept the item chip, grouped by canonical_key)`] : c.scen === 'error' ? [`context: rejected · ItemRejected · add · 42501 · “${item}” · 18:42`] : [], c.scen === 'bug' ? '' : undefined) +
        tableRow(c, c.scen === 'bug' ? [['message', '(none)'], ['context_kind', 'item.moved'], ['context_ref', `${item} · pantry → chilled`]] : c.scen === 'error' ? [['context_kind', 'rejected'], ['context_ref', `ItemRejected · add · 42501 · ${item} · 18:42`]] : [['context_kind', 'general']])
      );
    },
  },

  {
    id: 'FB4',
    name: t('Feedback with replies and status', 'Feedback mit Antworten und Status'),
    line: t('A “Feedback & ideas” page in More: your notes with their status (Sent, Read, Planned, Fixed in 1.4.1) and Peter’s replies, plus a short list of ideas Peter is weighing that the household can +1. Peter writes status and replies by hand in the dashboard.', 'Eine Seite „Feedback & Ideen“ unter Mehr: deine Notizen mit Status (Gesendet, Gelesen, Geplant, Behoben in 1.4.1) und Peters Antworten, dazu eine kurze Liste von Ideen, die Peter abwägt und denen der Haushalt +1 geben kann. Status und Antworten schreibt Peter von Hand im Dashboard.'),
    stack: true,
    service: null,
    answer: t('in the app: status and replies', 'in der App: Status und Antworten'),
    shake: {
      mode: 'optin',
      text: t(
        'Off by default; opt-in under Settings → “Shake to send feedback” (#281’s detector and quiet rules). The page in More is the main door, and replies need people to come back there, not a gesture. Web no-op. Shake opens the compose form about the live screen; no screenshot.',
        'Standardmäßig aus; einschaltbar unter Einstellungen → „Schütteln für Feedback“ (Detektor und Ruheregeln aus #281). Die Seite unter Mehr ist die Haupttür, und Antworten brauchen, dass man dorthin zurückkommt, keine Geste. Web nichts. Schütteln öffnet das Formular zum aktuellen Bildschirm; kein Bildschirmfoto.',
      ),
    },
    facts: {
      enter: t('More → Feedback & ideas (a badge when Peter replied) → Write to Peter, or +1 an idea Peter listed.', 'Mehr → Feedback & Ideen (mit Zähler, wenn Peter antwortete) → An Peter schreiben, oder einer Idee von Peter +1 geben.'),
      attach: t('Today’s fields, each shown with its value under “Sent along”, screen and system with a switch; nothing from the list.', 'Die Felder von heute, jedes mit Wert unter „Wird mitgeschickt“, Bildschirm und System mit Schalter; nichts aus der Liste.'),
      send: t('public.feedback plus status and reply columns; votes in a household-owned table with RLS. Mail replies only with the contact box.', 'public.feedback plus Status- und Antwortspalten; Stimmen in einer Haushaltstabelle mit RLS. Antworten per Mail nur mit Kontakt-Häkchen.'),
      after: t('The note shows “Sent”, later “Read by Peter”, his reply, then “Fixed in 1.4.1” with a link to the changelog.', 'Die Notiz zeigt „Gesendet“, später „Von Peter gelesen“, seine Antwort, dann „Behoben in 1.4.1“ mit Link zum Änderungsprotokoll.'),
      peter: t('Table Editor: he sets status and types the reply; the digest lists new notes and vote counts.', 'Table Editor: Er setzt den Status und tippt die Antwort; die Sammelmail zeigt neue Notizen und Stimmen.'),
    },
    build: { days: 9, text: t('Hub page, read-own-notes RLS (clients can’t read notes today), status and reply columns, ideas and votes tables with RLS and cross-household cases, a security-definer count so households see totals but not who voted, badge, Peter’s editing workflow, export and deletion.', 'Seite, RLS zum Lesen eigener Notizen (heute dürfen Clients nichts lesen), Status- und Antwortspalten, Ideen- und Stimmtabellen mit RLS und haushaltsübergreifenden Fällen, eine Security-Definer-Zählung, damit Haushalte Summen sehen, aber nicht, wer abstimmte, Zähler, Peters Bearbeitungsweg, Export und Löschung.') },
    processors: [],
    att: () => [{ key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }, { key: 'language', fixed: true }],
    defaults: { screen: true, device: true },
    gestures: {},
    path: { bug: ['list', 'more', 'hub', 'compose', 'mine'], error: ['list', 'more', 'hub', 'compose', 'mine'], idea: ['list', 'more', 'hub', 'compose', 'mine'] },
    story: () => [
      { step: 'enter', state: 'hub' },
      { step: 'attach', state: 'compose' },
      { step: 'send' },
      { step: 'after', state: 'thread' },
      { step: 'peter' },
      { step: 'also', state: 'voted', caption: t('An idea Peter already listed takes one +1 (3 taps from the list).', 'Eine Idee, die Peter schon aufführt, kostet ein +1 (3 Tipps ab der Liste).') },
    ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' } }),
      more: (c) => moreScreen(c, { fbRows: [moreRow(c, { icon: 'forum_outlined', label: de(c) ? 'Feedback & Ideen' : 'Feedback & ideas', to: 'hub', hot: true, badge: '1', testid: 'more-feedback' })] }),
      hub: (c) => hub(c),
      voted: (c) => hub(c, { voted: true }),
      compose: (c) => hub(c) + sheet(c, de(c) ? 'An Peter schreiben' : 'Write to Peter', formBody(c, { sendTo: 'mine', att: attPanel(c, flows[4].att()) }), { closeTo: 'hub' }),
      mine: (c) => hub(c, { mine: true }) + snack(c, de(c) ? 'Gesendet. Du siehst hier, wenn Peter sie liest.' : 'Sent. You’ll see here when Peter reads it.'),
      thread: (c) => `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.back}">${ic('arrow_back')}</button><h2 class="grow">${de(c) ? 'Deine Notiz' : 'Your note'}</h2></div>
        <div class="scroll" style="display:grid;gap:10px;align-content:start"><div class="thread">
        <span class="status-chip fixed">${ic('check_circle', 'xs')} ${c.scen === 'idea' ? (de(c) ? 'Geplant' : 'Planned') : de(c) ? 'Behoben in 1.4.1' : 'Fixed in 1.4.1'}</span>
        <div class="bubble me">${esc(L(c, scenarios[c.scen].message))}<small>${de(c) ? 'Sa., 18:44 · von Peter gelesen' : 'Sat 18:44 · read by Peter'}</small></div>
        <div class="bubble peter">${c.scen === 'idea' ? (de(c) ? 'Danke! Die Reihenfolge der Gänge steht jetzt bei den Ideen. Wer sie auch will, gibt dort +1.' : 'Thanks! Aisle order is under ideas now. Anyone who wants it too can +1 it there.') : c.scen === 'error' ? (de(c) ? 'Danke, das lag an einer abgelehnten Änderung beim Wiederverbinden. In 1.4.1 behoben.' : 'Thanks, that was a change refused on reconnect. Fixed in 1.4.1.') : de(c) ? 'Danke, das war ein Fehler in der Sortierung. In 1.4.1 behoben; Hafermilch landet jetzt im Kühlregal.' : 'Thanks, that was a sorting bug. Fixed in 1.4.1; oat milk now goes to Chilled.'}<small>Peter · ${de(c) ? 'So., 10:02' : 'Sun 10:02'}</small></div>
        <a class="muted" style="font-size:calc(14px * var(--ts,1))">${de(c) ? 'Was ist neu in 1.4.1 →' : 'What’s new in 1.4.1 →'}</a></div></div>`,
    },
    route: (c) =>
      route(
        c,
        [
          hopApp,
          { ...hopTable, what: t('public.feedback + status, reply', 'public.feedback + Status, Antwort') },
          { what: t('Peter sets status and writes the reply', 'Peter setzt Status und schreibt die Antwort'), where: t('Supabase dashboard, by hand', 'Supabase-Dashboard, von Hand'), reader: t('The sender reads only their own notes (new RLS select policy).', 'Der Absender liest nur die eigenen Notizen (neue RLS-Leseregel).') },
          hopDigest,
        ],
        t('Canny would do this out of the box, but it stores everything in the US and its Autopilot AI reads posts: ruled out.', 'Canny könnte das fertig, speichert aber alles in den USA und seine Autopilot-KI liest Beiträge: ausgeschlossen.'),
      ),
    peter: (c) =>
      tableRow(c, [['status', c.scen === 'idea' ? 'planned' : 'fixed'], ['fixed_in', c.scen === 'idea' ? '' : '1.4.1'], ['reply', de(c) ? 'Danke, …' : 'Thanks, …'], ['replied_at', '2026-11-16 10:02']]) +
      desk('Supabase · Table Editor · public.feedback_ideas', kv([['aisle-order', '14 households +1'], ['meal-plan', '9 (10 after this household’s +1)'], ['shared-receipts', '4']]), de(c) ? 'Von Peter angelegt; Haushalte geben nur +1' : 'Written by Peter; households only +1'),
  },

  {
    id: 'FB5',
    name: t('Ask at the right moment: survey and crash link', 'Im richtigen Moment fragen: Umfrage und Absturz-Verknüpfung'),
    line: t('No gesture: the app asks. After a crash, the next launch offers “Tell Peter what you were doing”, linked to the crash report; after the 3rd trip, a one-question survey; a note written after a reported error can link to it. Uses PostHog EU (already in the app) and adds Sentry EU, both only with the usage-data yes.', 'Keine Geste: Die App fragt. Nach einem Absturz bietet der nächste Start „Sag Peter, was du gemacht hast“ an, verknüpft mit dem Absturzbericht; nach dem 3. Einkauf eine Ein-Frage-Umfrage; eine Notiz nach einem gemeldeten Fehler kann darauf verweisen. Nutzt PostHog EU (schon in der App) und dazu Sentry EU, beides nur mit Ja zu Nutzungsdaten.'),
    stack: false,
    service: t('PostHog EU surveys + Sentry EU (de.sentry.io)', 'PostHog-EU-Umfragen + Sentry EU (de.sentry.io)'),
    answer: t('by mail, if ticked; fixes in What’s new', 'per Mail, wenn angehakt; Behebungen in „Was ist neu“'),
    shake: {
      mode: 'off',
      text: t(
        'Off everywhere, by design: the app starts the conversation at the moments that matter (a crash, a trip), so no gesture needs teaching and nothing fires by accident. Web the same. More → Send feedback stays as today for anything else.',
        'Überall aus, mit Absicht: Die App beginnt das Gespräch in den Momenten, die zählen (ein Absturz, ein Einkauf), also muss keine Geste erklärt werden und nichts löst aus Versehen aus. Web ebenso. Mehr → Feedback senden bleibt wie heute für alles andere.',
      ),
    },
    facts: {
      enter: t('In these three situations: More → Send feedback, as today. Only a crash or the 3rd trip makes the app ask (the extra frames). Never without the usage-data yes.', 'In diesen drei Situationen: Mehr → Feedback senden, wie heute. Nur ein Absturz oder der 3. Einkauf lässt die App fragen (die Zusatzbilder). Nie ohne Ja zu Nutzungsdaten.'),
      attach: t('Today’s fields with switches; after a reported error, “Link to the error report”. A crash or error went to Sentry automatically when it happened (usage-data yes); the switch only drops the link.', 'Die Felder von heute mit Schaltern; nach einem gemeldeten Fehler „Verknüpfung zum Fehlerbericht“. Ein Absturz oder Fehler ging beim Auftreten automatisch an Sentry (Ja zu Nutzungsdaten); der Schalter entfernt nur die Verknüpfung.'),
      send: t('Note text: public.feedback with sentry_event_id. Crashes and refused writes: Sentry EU, no screenshots, no replay, breadcrumbs as fixed route names only. Survey score: PostHog EU.', 'Notiztext: public.feedback mit sentry_event_id. Abstürze und abgelehnte Änderungen: Sentry EU, keine Bildschirmfotos, kein Replay, Schritte nur als feste Routennamen. Umfragenote: PostHog EU.'),
      after: t('“Thanks!” Fixes show in What’s new, not per person.', '„Danke!“ Behebungen stehen in „Was ist neu“, nicht pro Person.'),
      peter: t('The note in the digest and Table Editor; the linked Sentry issue (EU); survey results in PostHog EU.', 'Die Notiz in Sammelmail und Table Editor; das verknüpfte Sentry-Issue (EU); Umfrageergebnisse in PostHog EU.'),
    },
    build: { days: 6, text: t('Sentry SDK in an EU org with generative AI off, a DPA and §10/§12 policy text; crash prompt; PostHog survey and its consent gate; event id column.', 'Sentry-SDK in EU-Organisation mit generativer KI aus, AVV und Text in §10/§12; Absturz-Hinweis; PostHog-Umfrage mit Einwilligungsprüfung; Spalte für die Event-ID.') },
    processors: [{ name: 'Sentry', usPart: true }],
    tapsNote: t('change rejected: the 7 points need the usage-data yes (Sentry has the error only then); without it 2', 'Änderung abgelehnt: Die 7 Punkte brauchen das Ja zu Nutzungsdaten (nur dann hat Sentry den Fehler); ohne sind es 2'),
    att: (scen) => (scen === 'error' ? [{ key: 'errlink' }, { key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }] : [{ key: 'screen' }, { key: 'version', fixed: true }, { key: 'device' }, { key: 'language', fixed: true }]),
    defaults: { errlink: true, crash: true, screen: true, device: true, face: 2 },
    gestures: {},
    path: { bug: ['list', 'more', 'form', 'sent'], error: ['list', 'more', 'form', 'sent'], idea: ['list', 'more', 'form', 'sent'] },
    story: () => [
      { step: 'enter', state: 'more' },
      { step: 'attach', state: 'form' },
      { step: 'send' },
      { step: 'after', state: 'sent' },
      { step: 'peter' },
      { step: 'also', state: 'crash', caption: t('After a crash, the next launch asks (2 taps to send).', 'Nach einem Absturz fragt der nächste Start (2 Tipps bis gesendet).') },
      { step: 'also', state: 'crashform', caption: t('Linked to the crash report, which Sentry already has.', 'Verknüpft mit dem Absturzbericht, den Sentry schon hat.') },
      { step: 'also', state: 'rated', caption: t('After the 3rd trip, once per 90 days: one question (score to PostHog, comment as a note).', 'Nach dem 3. Einkauf, höchstens alle 90 Tage: eine Frage (Note an PostHog, Kommentar als Notiz).') },
    ],
    screens: {
      list: (c) => listFor(c, { tabs: { more: 'more' } }),
      more: (c) => moreScreen(c, { fbTo: 'form', hot: true }),
      form: (c) => moreScreen(c) + sheet(c, c.T.fbTitle, formBody(c, { att: attPanel(c, flows[5].att(c.scen)) }), { closeTo: 'more' }),
      crash: (c) =>
        listScreen(c, {
          banner: `<div class="banner">${ic('error_outline')}<span class="grow"><span><b>${de(c) ? 'Snacklist wurde gestern unerwartet beendet.' : 'Snacklist closed unexpectedly yesterday.'}</b><br>${de(c) ? 'Magst du Peter sagen, was du gerade gemacht hast?' : 'Want to tell Peter what you were doing?'}</span><span class="acts">${tact(c.T.notNow)}${tact(de(c) ? 'Peter sagen' : 'Tell Peter', { honey: true })}</span></span></div>`,
        }),
      crashform: (c) => listScreen(c) + sheet(c, de(c) ? 'Was hast du gemacht?' : 'What were you doing?', formBody(c, { chips: false, msg: de(c) ? 'Ich hab beim Einkaufen schnell drei Sachen abgehakt.' : 'I ticked three things quickly while shopping.', att: attPanel(c, [{ key: 'crash' }, { key: 'version', fixed: true }, { key: 'device' }]) }), { closeTo: 'list' }),
      rated: (c) => listScreen(c) + sheet(c, de(c) ? 'Kurze Frage' : 'Quick question', surveyBody(c)),
      sent: (c) => moreScreen(c, { snack: snack(c, c.T.thanks) }),
    },
    route: (c) =>
      route(
        c,
        [
          hopApp,
          { ...hopTable, what: t('The note (+ sentry_event_id when linked)', 'Die Notiz (+ sentry_event_id, wenn verknüpft)') },
          hopDigest,
          { what: t('Crash and error reports, sent when they happen', 'Absturz- und Fehlerberichte, gesendet, wenn sie passieren'), where: t('Sentry EU (de.sentry.io, Frankfurt)', 'Sentry EU (de.sentry.io, Frankfurt)'), reader: t('Only with the usage-data yes, no per-crash choice. Generative AI off for the org; no screenshots or replay. Sentry keeps account data in the US.', 'Nur mit Ja zu Nutzungsdaten, ohne Wahl pro Absturz. Generative KI für die Organisation aus; keine Bildschirmfotos, kein Replay. Sentry hält Kontodaten in den USA.') },
          { what: t('Survey scores', 'Umfragenoten'), where: t('PostHog Cloud EU, Frankfurt', 'PostHog Cloud EU, Frankfurt'), reader: t('Only with the usage-data yes; PostHog’s AI stays off (org setting).', 'Nur mit Ja zu Nutzungsdaten; PostHogs KI bleibt aus (Organisationseinstellung).') },
        ],
        t('The note text never goes to Sentry or PostHog: analytics carry no free text (events.dart allow-list).', 'Der Notiztext geht nie an Sentry oder PostHog: Analytics tragen keinen Freitext (Allow-List in events.dart).'),
      ),
    peter: (c) =>
      tableRow(c, c.scen === 'error' ? [['sentry_event_id', '7f3a9c…']] : []) +
      (c.scen === 'error'
        ? desk('Sentry (EU) · SNACKLIST-4F · ItemRejected on reconnect', kv([['events · users', '17 · 9'], ['release', '1.4.0 (1325)'], ['last seen', '18:42'], ['linked notes', 'feedback 7c1e… (public.feedback)']]), de(c) ? 'Peter, eingeloggt in de.sentry.io' : 'Peter, signed in at de.sentry.io')
        : desk('PostHog EU · Surveys · “Shopping today”', kv([['responses (30 d)', '212'], ['1 · 2 · 3 · 4 · 5', '6 · 19 · 41 · 88 · 58'], ['median', '4'], ['comments', de(c) ? 'als Notizen in public.feedback' : 'as notes in public.feedback']]), de(c) ? 'Peter, eingeloggt in eu.posthog.com' : 'Peter, signed in at eu.posthog.com')),
  },
];

const reportBody = (c) => {
  const bug = c.scen === 'bug';
  const key = bug ? 'item' : 'error';
  const label = bug ? (de(c) ? 'Hafermilch: Vorrat & Konserven → Kühlregal' : 'Oat milk: Pantry → Chilled') : de(c) ? 'Abgelehnt: Hafermilch, 18:42 · add 42501' : 'Rejected: Oat milk, 18:42 · add 42501';
  return `<div class="pad">${c.att[key] ? `<span class="chipx" data-testid="${key}-chip">${bug ? '🥣' : ic('sync_problem', 'sm')} ${label}<button aria-label="${de(c) ? 'Entfernen' : 'Remove'}" data-tog="${key}">${ic('close', 'sm')}</button></span>` : `<span class="muted">${de(c) ? 'Ohne Eintrag: Peter sieht nur, dass etwas nicht stimmte.' : 'Without the item: Peter only sees that something was off.'}</span>`}</div>
  ${messageField(c, bug ? '' : undefined)}${attPanel(c, flows[3].att(c.scen).filter((r) => r.key !== key))}<div class="actions">${tact(c.T.send, { to: 'sent', honey: true, testid: 'send' })}</div>`;
};

const hub = (c, { voted, mine } = {}) => `${statusBar()}<div class="page-top"><button class="ibtn" aria-label="${c.T.back}" ${go('more')}>${ic('arrow_back')}</button><h2 class="grow">${de(c) ? 'Feedback & Ideen' : 'Feedback & ideas'}</h2></div>
  <div class="scroll" style="display:grid;gap:10px;align-content:start;padding-bottom:120px">
  <div class="pad">${tact(de(c) ? 'An Peter schreiben' : 'Write to Peter', { to: 'compose', honey: true, icon: 'edit_outlined', testid: 'write' })}</div>
  <div class="section-h">${de(c) ? 'Deine Notizen' : 'Your notes'}</div>
  ${mine ? `<div class="note-card"><span class="status-chip">${ic('schedule', 'xs')} ${de(c) ? 'Gesendet' : 'Sent'}</span><p>${esc(L(c, scenarios[c.scen].message))}</p></div>` : ''}
  <button class="note-card" style="text-align:left"><span class="status-chip read">${ic('reply', 'xs')} ${de(c) ? 'Peter hat geantwortet' : 'Peter replied'}</span><p>${de(c) ? 'Die Summe springt, wenn ich einen Preis ändere.' : 'The total jumps when I change a price.'}</p></button>
  <div class="note-card"><span class="status-chip fixed">${ic('check_circle', 'xs')} ${de(c) ? 'Behoben in 1.4.0' : 'Fixed in 1.4.0'}</span><p>${de(c) ? 'Dunkles Design: Preise schwer lesbar.' : 'Dark theme: prices hard to read.'}</p></div>
  <div class="section-h">${de(c) ? 'Ideen, die Peter abwägt' : 'Ideas Peter is weighing'}</div>
  <div class="idea"><span class="grow"><b>${de(c) ? 'Liste in der Reihenfolge der Gänge' : 'List in aisle order'}</b><small class="muted">${de(c) ? 'Geplant' : 'Planned'}</small></span><button class="vote">${ic('thumb_up_outlined', 'sm')}14</button></div>
  <div class="idea"><span class="grow"><b>${de(c) ? 'Wochenplan für Essen' : 'Weekly meal plan'}</b><small class="muted">${de(c) ? 'Wird überlegt' : 'Considering'}</small></span><button class="vote ${voted ? 'on' : ''}" aria-pressed="${!!voted}" data-testid="vote">${ic(voted ? 'thumb_up' : 'thumb_up_outlined', 'sm')}${voted ? 10 : 9}</button></div>
  <div class="idea"><span class="grow"><b>${de(c) ? 'Gemeinsame Kassenbons' : 'Shared receipts'}</b><small class="muted">${de(c) ? 'Wird überlegt' : 'Considering'}</small></span><button class="vote">${ic('thumb_up_outlined', 'sm')}4</button></div>
  <p class="included">${de(c) ? 'Ideen schreibt Peter. Andere sehen nur die Zahl, nie wer abgestimmt hat.' : 'Peter writes the ideas. Others see only the count, never who voted.'}</p></div>`;

const surveyBody = (c) =>
  `<p class="pad" style="font-size:calc(17px * var(--ts,1))">${de(c) ? 'Wie einfach war der Einkauf heute?' : 'How easy was shopping today?'}</p>
  <div class="faces pad">${['😣', '🙁', '😐', '🙂', '😄'].map((f, i) => `<button class="face ${i === 1 ? 'on' : ''}" aria-label="${i + 1}">${f}</button>`).join('')}</div>
  ${messageField(c, de(c) ? 'Ich musste die Liste dreimal hoch und runter scrollen.' : 'I scrolled the list up and down three times.')}<p class="included">${de(c) ? 'Die Note geht an PostHog EU, der Kommentar als Notiz an Peter. Höchstens alle 90 Tage, nur mit Ja zu Nutzungsdaten.' : 'The score goes to PostHog EU, the comment to Peter as a note. At most every 90 days, only with the usage-data yes.'}</p>
  <div class="actions">${tact(c.T.notNow)}${tact(c.T.send, { honey: true })}</div>`;

export const T = chrome;
