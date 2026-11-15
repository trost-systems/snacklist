// Round JH: a new user joins an existing household. Today plus five end-to-end flows.
// Each option has screens (state -> HTML), meta (state -> step tags, caption, screen group) and
// paths(scenario) -> { list, app }: the steps from the invite in front of the user to the first shared list,
// and to the shared list inside the installed app. metrics.js counts taps and screens from these paths.
import { T } from '../model.js';
import * as u from '../ui.js';

const { btn, act, ic, M } = u;
const en = (en, de) => ({ en, de });

// A path step: the state shown and how the user got there (`via`), which control (`by`), how many actions (`n`).
const st = (s, via = 'tap', by, n, label) => ({ s, via, ...(by ? { by } : {}), ...(n ? { n } : {}), ...(label ? { label } : {}) });
const auto = (s, label) => st(s, 'auto', undefined, undefined, label);
const wait = (s) => st(s, 'wait', undefined, undefined, en('Mia lets you in (in her app)', 'Mia lässt dich rein (in ihrer App)'));
const typed = (s, label = en('Type K7QM-4XPA', 'K7QM-4XPA tippen')) => st(s, 'type', undefined, undefined, label);
const home = en('Swipe to the home screen', 'Zum Home-Bildschirm wischen');
const searchStore = en('Open the App Store and search for Snacklist', 'App Store öffnen und nach Snacklist suchen');
const copyFromChat = en('Copy the code from the chat (hold, Copy)', 'Code im Chat kopieren (halten, Kopieren)');

// Screens every option shares: the invite in the chat, the camera, the home screen, the App Store, the Apple sheet.
const common = {
  msg: (c) => u.chat(c, { text: c.T.shareInvite(u.LINK, u.CODE) }),
  'msg-code': (c) => u.chat(c, { text: c.T.shareCodeOnly(u.codeDash) }),
  cam: (c) => u.camera(c, { pill: true }),
  home: (c) => u.homeScreen(c, { snacklist: c.scen.app === 'installed' || c.installed }),
  'home-app': (c) => u.homeScreen(c, { snacklist: true }),
  'store-get': (c) => u.appStore(c, { phase: 'get' }),
  'store-open': (c) => u.appStore(c, { phase: 'open' }),
};
const commonMeta = {
  msg: { step: 'entry', cap: en('Mia’s invite in WhatsApp: the link and the code, shared by Mia from her phone.', 'Mias Einladung in WhatsApp: Link und Code, von Mia selbst geteilt.') },
  'msg-again': { step: 'entry', scr: 'msg', cap: en('Back in the chat, the same link again. Now that the app is there, it opens the app.', 'Zurück im Chat, derselbe Link noch mal. Jetzt, wo die App da ist, öffnet er die App.') },
  'msg-code': { step: 'entry', cap: en('Mia typed only the code into a message (or said it out loud).', 'Mia hat nur den Code in eine Nachricht getippt (oder gesagt).') },
  'cam-again': { step: 'entry', scr: 'cam', cap: en('After installing, the camera on Mia’s QR code again: now the link opens the app.', 'Nach der Installation die Kamera noch einmal auf Mias QR-Code: Jetzt öffnet der Link die App.') },
  cam: { step: 'entry', cap: en('Mia shows the QR code on her phone; Ida points her camera at it. The camera offers the link.', 'Mia zeigt den QR-Code auf ihrem Handy; Ida hält die Kamera drauf. Die Kamera bietet den Link an.') },
  home: { step: 'entry', cap: en('The home screen.', 'Der Home-Bildschirm.') },
  'home-app': { step: 'entry', scr: 'home', cap: en('The home screen, with Snacklist now installed.', 'Der Home-Bildschirm, Snacklist ist jetzt installiert.') },
  'store-get': { step: 'install', cap: en('The App Store page.', 'Die App-Store-Seite.') },
  'store-open': { step: 'install', scr: 'store-get', cap: en('Installed.', 'Installiert.') },
};
common['msg-again'] = common.msg;
common['cam-again'] = common.cam;

// Today: main's screens. The link opens sign-in without saying who invites; consent comes before the join.
const today = {
  id: 'today',
  name: en('Today (main)', 'Heute (main)'),
  line: en(
    'Installed, the link opens sign-in (“Invite saved”), then usage data, then the join screen with only the household’s name. Not installed, the link opens the web join page; joining there stays in the browser. “Paste invite” on the start screen is the bridge for a code or link copied before installing.',
    'Installiert öffnet der Link die Anmeldung („Einladung gemerkt“), dann Nutzungsdaten, dann die Beitrittsseite mit nur dem Haushaltsnamen. Ohne App öffnet er die Web-Beitrittsseite; wer dort beitritt, bleibt im Browser. „Einladung einfügen“ auf dem Startbildschirm ist die Brücke für einen vor der Installation kopierten Code oder Link.',
  ),
  service: null,
  pasteGone: false,
  screens: {
    ...common,
    'web-today': (c) => u.webJoin(c),
    'web-login': (c) => u.webApp(c, `${u.brandBlock(c)}${u.providerButtons(c)}<p class="body muted center-t">${c.T.invitePasteWaiting}</p>`),
    'web-apple': (c) => u.appleSheet(c, u.webApp(c, `${u.brandBlock(c)}${u.providerButtons(c)}`)),
    'web-consent': (c) => u.webApp(c, u.consentBody(c)),
    'web-join': (c) => u.webApp(c, u.joinScreen(c).replace(u.statusBar(), '')),
    'web-list': (c) => u.webApp(c, `<div class="web-list">${u.listScreen(c, { top: u.firstSteps(c, { joined: true }) }).replace(u.statusBar(), '')}</div>`),
    'web-wait': (c) => u.webApp(c, u.waitingScreen(c).replace(u.statusBar(), '')),
    'start-today': (c) => u.startScreen(c),
    'login-inv': (c) => u.loginScreen(c, { invite: true }),
    apple: (c) => u.appleSheet(c, u.loginScreen(c, { invite: true })),
    consent: (c) => u.consentScreen(c),
    join: (c) => u.joinScreen(c),
    wait: (c) => u.waitingScreen(c),
    list: (c) => u.listScreen(c, { top: u.firstSteps(c, { joined: true }) }),
    'list-approved': (c) => u.listScreen(c, { top: u.firstSteps(c, { joined: true }), snack: c.T.joinApprovedNotice(M(c).household) }),
    'app-start': (c) => u.startScreen(c),
    'app-login': (c) => u.loginScreen(c),
    'app-apple': (c) => u.appleSheet(c, u.loginScreen(c)),
    'app-consent': (c) => u.consentScreen(c),
    'app-list': (c) => u.listScreen(c, { top: u.firstSteps(c, { joined: true }) }),
  },
  meta: {
    ...commonMeta,
    'web-today': { step: 'landing', cap: en('Not installed: the static join page names Mia and the household, with the code and “Join in the browser”. Store buttons are built but off until the listings are public.', 'Ohne App: Die statische Beitrittsseite nennt Mia und den Haushalt, mit Code und „Im Browser beitreten“. Store-Knöpfe sind gebaut, aber aus, bis die Einträge öffentlich sind.') },
    'web-login': { step: 'account', cap: en('The web app’s sign-in, “Invite saved”.', 'Die Anmeldung der Web-App, „Einladung gemerkt“.') },
    'web-apple': { step: 'account', scr: 'web-login', cap: en('Sign in with Apple creates the account.', 'Mit Apple anmelden legt das Konto an.') },
    'web-consent': { step: 'consent', cap: en('Usage data, asked before the join.', 'Nutzungsdaten, vor dem Beitritt gefragt.') },
    'web-join': { step: 'landing', cap: en('The join screen: the household’s name only, “Join household”.', 'Die Beitrittsseite: nur der Haushaltsname, „Haushalt beitreten“.') },
    'web-wait': { step: 'wait', cap: en('Request sent. The first button offers a household of her own.', 'Anfrage gesendet. Der erste Knopf bietet einen eigenen Haushalt an.') },
    'web-list': { step: 'list', cap: en('The shared list, in the browser. The app is still not installed.', 'Die gemeinsame Liste, im Browser. Die App ist noch nicht installiert.') },
    'start-today': { step: 'entry', cap: en('The start screen: “Get started”, “Sign in”, and “Paste invite” right under it.', 'Der Startbildschirm: „Los geht’s“, „Anmelden“ und direkt darunter „Einladung einfügen“.') },
    'login-inv': { step: 'account', cap: en('The link opens sign-in with “Invite saved”. Nothing says who invites, or to what.', 'Der Link öffnet die Anmeldung mit „Einladung gemerkt“. Nichts sagt, wer wohin einlädt.') },
    apple: { step: 'account', scr: 'login-inv', cap: en('Sign in with Apple creates the account.', 'Mit Apple anmelden legt das Konto an.') },
    consent: { step: 'consent', cap: en('Usage data, a full screen between sign-in and the join.', 'Nutzungsdaten, ein ganzer Bildschirm zwischen Anmeldung und Beitritt.') },
    join: { step: 'landing', cap: en('The join screen: code filled in, the household’s name only. The first time she sees where she is going.', 'Die Beitrittsseite: Code eingetragen, nur der Haushaltsname. Zum ersten Mal sieht sie, wohin es geht.') },
    wait: { step: 'wait', cap: en('“Request sent.” The first button is “Create your own household”.', '„Anfrage gesendet.“ Der erste Knopf ist „Eigenen Haushalt anlegen“.') },
    list: { step: 'list', cap: en('The shared list. First steps: “Joined the household”.', 'Die gemeinsame Liste. Erste Schritte: „Haushalt beigetreten“.') },
    'list-approved': { step: 'list', scr: 'list', cap: en('Approved: the list opens by itself, “You’re now in …”.', 'Bestätigt: Die Liste öffnet sich von selbst, „Du bist jetzt in …“.') },
    'app-start': { step: 'entry', scr: 'start-today', cap: en('Later, in the installed app: the start screen again.', 'Später, in der installierten App: wieder der Startbildschirm.') },
    'app-login': { step: 'account', cap: en('Sign in once more, with the same account.', 'Noch einmal anmelden, mit demselben Konto.') },
    'app-apple': { step: 'account', scr: 'app-login', cap: en('Apple again.', 'Noch einmal Apple.') },
    'app-consent': { step: 'consent', cap: en('Usage data again: the answer is per install.', 'Nochmal Nutzungsdaten: Die Antwort gilt je Installation.') },
    'app-list': { step: 'list', cap: en('The shared list in the app.', 'Die gemeinsame Liste in der App.') },
  },
  paths: (sc) => {
    const ok = sc.approval === 'on' ? [st('wait', 'tap'), wait('list-approved')] : [st('list')];
    const inApp = [st('login-inv', 'tap', 'paste'), st('apple', 'tap', 'apple'), st('consent'), st('join', 'tap', 'decline'), ...ok];
    const webOk = sc.approval === 'on' ? [st('web-wait'), wait('web-list')] : [st('web-list')];
    const web = [st('web-today', 'tap', 'link'), st('web-login', 'tap', 'web-join'), st('web-apple', 'tap', 'apple'), st('web-consent'), st('web-join', 'tap', 'decline'), ...webOk];
    const later = [auto('home', home), st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('app-start'), st('app-login', 'tap', 'login'), st('app-apple', 'tap', 'apple'), st('app-consent'), st('app-list', 'tap', 'decline')];
    let list;
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), st('home', 'tap', 'outside', 2, copyFromChat)];
      list = sc.app === 'installed'
        ? [...pre, st('start-today', 'tap', 'snacklist'), ...inApp]
        : [...pre, st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-today'), ...inApp];
      return { list, app: list };
    }
    const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
    const by = sc.entry === 'qr' ? 'primary' : 'link';
    if (sc.app === 'installed') {
      list = [entry, { ...inApp[0], by }, ...inApp.slice(1)];
      return { list, app: list };
    }
    list = [entry, { ...web[0], by }, ...web.slice(1)];
    return { list, app: [...list, ...later] };
  },
};
// The Today code path pastes on the start screen; its home step carries the copy.
today.screens.home = (c) => u.homeScreen(c, { snacklist: c.scen.app === 'installed' });

// ---- shared new screens ---------------------------------------------------------------------------------

const joinLabel = (c) => (c.lang === 'de' ? `„${M(c).household}“ beitreten` : `Join “${M(c).household}”`);
const notYou = (c) => btn(c, c.lang === 'de' ? 'Lieber eine eigene Liste anlegen' : 'Start my own list instead', { kind: 'text' });
const youreIn = (c, extra = '') =>
  `<div class="sticker welcome-card"><b>${c.lang === 'de' ? `Du bist in „${M(c).household}“` : `You’re in “${M(c).household}”`}</b><p class="small muted">${c.lang === 'de' ? 'Mia und Noah sehen jetzt, was du hinzufügst.' : 'Mia and Noah now see what you add.'}</p>${extra}</div>`;
const landingStd = (c, o = {}) =>
  u.landing(c, { actions: `${btn(c, joinLabel(c), { kind: 'primary', by: 'join' })}${o.more ?? ''}${notYou(c)}`, ...o });
const kindWait = (c, o = {}) =>
  `${u.statusBar()}<div class="scroll"><div class="pg land" data-wait><div class="center"><span class="phex big honey">${ic('hourglass_top_outlined')}</span></div>
  <h1 class="h center-t">${c.lang === 'de' ? `Mia lässt dich gleich rein` : `Mia will let you in`}</h1>
  <p class="body center-t">${c.lang === 'de' ? `„${M(c).household}“ bestätigt neue Mitglieder. Mia hat deine Anfrage gerade bekommen.` : `“${M(c).household}” confirms new members. Mia just got your request.`}</p>
  <p class="body center-t muted">${c.lang === 'de' ? 'Die Liste öffnet sich hier von selbst, sobald sie zustimmt.' : 'The list opens right here as soon as she says yes.'}</p>
  ${o.mid ?? ''}<div class="stack">${o.actions ?? ''}${btn(c, c.T.joinRequestWithdraw, { kind: 'text' })}</div></div></div>`;
const listIn = (c, o = {}) => u.listScreen(c, { top: `${o.welcome === false ? '' : youreIn(c, o.welcomeExtra)}${o.consent ? u.consentCard(c) : ''}${o.more ?? ''}`, snack: o.snack, overlay: o.overlay });
const codeScreen = (c, { typed, paste, title, scan } = {}) =>
  `${u.statusBar()}${u.appBar(c, { title: title ?? (c.lang === 'de' ? 'Haushalt beitreten' : 'Join a household'), back: true })}<div class="scroll"><div class="pg">
  <p class="body">${c.lang === 'de' ? 'Gib den Code aus der Einladung ein. Er hat 8 Zeichen, zum Beispiel K7QM-4XPA.' : 'Enter the code from the invite. It has 8 characters, like K7QM-4XPA.'}</p>
  ${u.codeField(c, { typed })}${scan ? btn(c, c.lang === 'de' ? 'QR-Code scannen' : 'Scan a QR code', { icon: 'qr_code_scanner', by: 'scan' }) : ''}
  <div class="stack">${btn(c, c.T.inviteCheck, { kind: 'primary' })}</div></div></div>${typed ? '' : u.keyboard(c, { paste })}`;

const accountOver = (c, under) => u.accountSheet(c, under);
const appleOver = (c, under) => u.appleSheet(c, under);

// ---- JH1: a deep-link service carries the invite through the store ------------------------------------

const jh1 = {
  id: 'JH1',
  name: en('The store remembers the invite (deep-link service)', 'Der Store merkt sich die Einladung (Deep-Link-Dienst)'),
  line: en(
    'Join links become links of an existing deep-link service. Not installed, the link goes straight to the App Store; on first start Ida taps “I was invited”, the service matches her install to the tap and the app opens Mia’s invite. Usage data is a card on the list.',
    'Beitrittslinks werden Links eines fertigen Deep-Link-Dienstes. Ohne App führt der Link direkt in den App Store; beim ersten Start tippt Ida „Ich wurde eingeladen“, der Dienst ordnet die Installation dem Tipp zu, und die App öffnet Mias Einladung. Nutzungsdaten sind eine Karte auf der Liste.',
  ),
  service: en('Deep-link service (Branch or AppsFlyer OneLink; EU storage on request)', 'Deep-Link-Dienst (Branch oder AppsFlyer OneLink; EU-Speicherung auf Anfrage)'),
  pasteGone: true,
  screens: {
    ...common,
    'start-jh1': (c) =>
      u.startScreen(c, {
        paste: false,
        extra: `<div class="sticker invited-card"><b>${c.lang === 'de' ? 'Hat dich jemand eingeladen?' : 'Did someone invite you?'}</b><p class="small muted">${c.lang === 'de' ? 'Wir fragen den Link-Dienst nach deiner Einladung. Dafür gehen Gerätetyp und IP-Adresse an ihn.' : 'We ask our link service for your invite. It gets your device type and IP address for that.'}</p>${btn(c, c.lang === 'de' ? 'Ich wurde eingeladen' : 'I was invited', { kind: 'primary', by: 'find' })}${btn(c, c.lang === 'de' ? 'Ich habe einen Code' : 'I have a code', { kind: 'text', by: 'code' })}</div>`,
      }),
    landing: (c) => landingStd(c),
    acct: (c) => accountOver(c, landingStd(c)),
    apple: (c) => appleOver(c, landingStd(c)),
    code: (c) => codeScreen(c),
    'code-typed': (c) => codeScreen(c, { typed: true }),
    wait: (c) => kindWait(c),
    list: (c) => listIn(c, { consent: true }),
    'list-approved': (c) => listIn(c, { consent: true, snack: c.T.joinApprovedNotice(M(c).household) }),
  },
  meta: {
    ...commonMeta,
    'store-get': { step: 'install', cap: en('The service’s link sends her straight to the App Store; it notes the tap (IP address, device type).', 'Der Link des Dienstes führt direkt in den App Store; er merkt sich den Tipp (IP-Adresse, Gerätetyp).') },
    'start-jh1': { step: 'entry', cap: en('First start: “Did someone invite you?” The match runs only on her tap (Legal N-111: no automatic read).', 'Erster Start: „Hat dich jemand eingeladen?“ Der Abgleich läuft erst auf ihren Tipp (Legal N-111: kein automatisches Auslesen).') },
    landing: { step: 'landing', cap: en('The invite in the app: Mia, the household, members and open items. Nothing more than the join page.', 'Die Einladung in der App: Mia, der Haushalt, Mitglieder und offene Einträge. Nicht mehr als die Beitrittsseite.') },
    acct: { step: 'account', cap: en('“Create your account to join”: Apple, Google, email; Imprint and Privacy.', '„Konto erstellen, um beizutreten“: Apple, Google, E-Mail; Impressum und Datenschutz.') },
    apple: { step: 'account', scr: 'acct', cap: en('Sign in with Apple creates the account; the join follows at once.', 'Mit Apple anmelden legt das Konto an; der Beitritt folgt sofort.') },
    code: { step: 'entry', cap: en('“I have a code” on the start screen: one field.', '„Ich habe einen Code“ auf dem Startbildschirm: ein Feld.') },
    'code-typed': { step: 'entry', scr: 'code', cap: en('Code typed.', 'Code getippt.') },
    wait: { step: 'wait', cap: en('Approval on: “Mia will let you in”. The list opens here by itself; no “create your own” button.', 'Bestätigung an: „Mia lässt dich gleich rein“. Die Liste öffnet sich hier von selbst; kein „eigenen anlegen“.') },
    list: { step: ['list', 'consent'], cap: en('The shared list, “You’re in”. Usage data is a card with two equal buttons.', 'Die gemeinsame Liste, „Du bist drin“. Nutzungsdaten sind eine Karte mit zwei gleichen Knöpfen.') },
    'list-approved': { step: ['list', 'consent'], scr: 'list', cap: en('Approved: the list opens, “You’re now in …”.', 'Bestätigt: Die Liste öffnet sich, „Du bist jetzt in …“.') },
  },
  paths: (sc) => {
    const ok = sc.approval === 'on' ? [st('wait'), wait('list-approved')] : [st('list')];
    const join = [st('acct', 'tap', 'join'), st('apple', 'tap', 'apple'), ...ok.map((x, i) => (i === 0 ? { ...x, by: 'primary' } : x))];
    const viaCode = [st('code', 'tap', 'code'), typed('code-typed'), st('landing'), ...join];
    let list;
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), auto('home', home)];
      list = sc.app === 'installed'
        ? [...pre, st('start-jh1', 'tap', 'snacklist'), ...viaCode]
        : [...pre, st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-jh1'), ...viaCode];
    } else {
      const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
      const by = sc.entry === 'qr' ? 'primary' : 'link';
      list = sc.app === 'installed'
        ? [entry, st('landing', 'tap', by), ...join]
        : [entry, st('store-get', 'tap', by), st('store-open'), st('start-jh1'), st('landing', 'tap', 'find'), ...join];
    }
    return { list, app: list };
  },
};

// ---- JH2: join in the browser first, get the app afterwards (today's stack) ----------------------------

const webJoinJH2 = (c, o = {}) =>
  u.webJoin(c, {
    joinLabel: joinLabel(c),
    codeHint: c.lang === 'de' ? 'Hast du die App schon? Der Link öffnet sie direkt.' : 'Have the app already? The link opens it directly.',
    top: `<p class="body">${c.lang === 'de' ? 'Tritt hier bei, ganz ohne App. Die App kannst du danach laden: Melde dich dort mit demselben Konto an, und die Liste ist da.' : 'Join right here, no app needed. Get the app afterwards: sign in there with the same account, and the list is waiting.'}</p>`,
    ...o,
  });
const getAppCard = (c) =>
  `<div class="sticker app-card"><b>${c.lang === 'de' ? 'Snacklist als App' : 'Snacklist as an app'}</b><p class="small muted">${c.lang === 'de' ? 'Mit Siri, Widgets und schneller. Melde dich dort mit Apple an, die Liste ist schon da.' : 'With Siri, widgets, and faster. Sign in there with Apple; the list is already there.'}</p>${btn(c, c.T.web.appStore, { kind: 'primary', by: 'get-app', icon: 'download' })}</div>`;
const jh2 = {
  id: 'JH2',
  name: en('Join in the browser, then get the app', 'Im Browser beitreten, dann die App holen'),
  line: en(
    'The join page is the landing: “Join Brandt family” right there, an account with Apple, and Ida is in the shared list in the browser. A card then offers the app; she signs in there with the same account and the list is waiting. Nothing has to cross the install.',
    'Die Beitrittsseite ist die Landeseite: „Familie Brandt beitreten“ direkt dort, ein Konto mit Apple, und Ida ist in der gemeinsamen Liste im Browser. Eine Karte bietet dann die App an; dort meldet sie sich mit demselben Konto an, und die Liste ist da. Nichts muss über die Installation getragen werden.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    ...common,
    'web-land': (c) => webJoinJH2(c),
    'web-acct': (c) => accountOver(c, webJoinJH2(c)),
    'web-apple': (c) => appleOver(c, webJoinJH2(c)),
    'web-wait': (c) => u.webApp(c, kindWait(c, { mid: getAppCard(c) }).replace(u.statusBar(), '')),
    'web-list': (c) => u.webApp(c, `<div class="web-list">${listIn(c, { consent: true, more: getAppCard(c) }).replace(u.statusBar(), '')}</div>`),
    'web-list-approved': (c) => u.webApp(c, `<div class="web-list">${listIn(c, { consent: true, more: getAppCard(c), snack: c.T.joinApprovedNotice(M(c).household) }).replace(u.statusBar(), '')}</div>`),
    'start-jh2': (c) => u.startScreen(c, { paste: false }),
    'login-jh2': (c) => u.loginScreen(c, { paste: false }),
    join: (c) => u.joinScreen(c),
    'apple-jh2': (c) => appleOver(c, u.loginScreen(c, { paste: false })),
    'app-list': (c) => listIn(c, { consent: true, welcome: false }),
    landing: (c) => landingStd(c),
    acct: (c) => accountOver(c, landingStd(c)),
    apple: (c) => appleOver(c, landingStd(c)),
    wait: (c) => kindWait(c),
    list: (c) => listIn(c, { consent: true }),
    'list-approved': (c) => listIn(c, { consent: true, snack: c.T.joinApprovedNotice(M(c).household) }),
    consent: (c) => u.consentScreen(c),
    welcome: (c) => `${u.statusBar()}${u.appBar(c, { title: c.lang === 'de' ? 'Willkommen bei Snacklist' : 'Welcome to Snacklist', logout: true })}<div class="scroll"><div class="pg">${u.brandBlock(c, true)}
      <div class="mrow card-row">${ic('add_home_outlined')}<span class="grow"><span>${c.lang === 'de' ? 'Haushalt erstellen' : 'Create a household'}</span></span>${ic('chevron_right', 'sm')}</div>
      <button class="mrow card-row" ${act(c, 'join-code')}>${ic('group_add_outlined')}<span class="grow"><span>${c.T.onboardingJoin}</span><small>${c.lang === 'de' ? 'Du hast einen Link oder einen Code bekommen.' : 'You’ve received a link or a code.'}</small></span>${ic('chevron_right', 'sm')}</button></div></div>`,
    code: (c) => codeScreen(c, { title: c.T.onboardingJoin }),
    'code-typed': (c) => codeScreen(c, { typed: true, title: c.T.onboardingJoin }),
  },
  meta: {
    ...commonMeta,
    'web-land': { step: 'landing', cap: en('The join page is the landing: Mia, the household, the counts, and “Join Brandt family” as the main button.', 'Die Beitrittsseite ist die Landeseite: Mia, der Haushalt, die Zahlen und „Familie Brandt beitreten“ als Hauptknopf.') },
    'web-acct': { step: 'account', cap: en('An account in the browser: Apple, Google or email.', 'Ein Konto im Browser: Apple, Google oder E-Mail.') },
    'web-apple': { step: 'account', scr: 'web-acct', cap: en('Sign in with Apple, on the web.', 'Mit Apple anmelden, im Web.') },
    'web-wait': { step: 'wait', cap: en('Approval on: the wait, with the app offered meanwhile.', 'Bestätigung an: das Warten, mit der App als Angebot für die Zeit.') },
    'web-list': { step: ['list', 'consent'], cap: en('The shared list in the browser: “You’re in”, usage data as a card, “Get the app”.', 'Die gemeinsame Liste im Browser: „Du bist drin“, Nutzungsdaten als Karte, „App laden“.') },
    'web-list-approved': { step: ['list', 'consent'], scr: 'web-list', cap: en('Approved: the list opens in the browser.', 'Bestätigt: Die Liste öffnet sich im Browser.') },
    'start-jh2': { step: 'entry', cap: en('The installed app’s start screen, without “Paste invite”.', 'Der Startbildschirm der App, ohne „Einladung einfügen“.') },
    'login-jh2': { step: 'account', cap: en('Sign in with the account from the browser.', 'Anmelden mit dem Konto aus dem Browser.') },
    'apple-jh2': { step: 'account', scr: 'login-jh2', cap: en('Apple again; the household is on the account.', 'Noch einmal Apple; der Haushalt hängt am Konto.') },
    'app-list': { step: ['list', 'consent'], cap: en('The shared list in the app. Usage data is asked once more: the answer is per install.', 'Die gemeinsame Liste in der App. Nutzungsdaten werden noch einmal gefragt: Die Antwort gilt je Installation.') },
    landing: { step: 'landing', cap: en('Installed: the link opens the same landing in the app.', 'Installiert: Der Link öffnet dieselbe Landeseite in der App.') },
    acct: { step: 'account', cap: en('Account sheet over the landing.', 'Konto-Blatt über der Landeseite.') },
    apple: { step: 'account', scr: 'acct', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    wait: { step: 'wait', cap: en('Approval on: a kind wait.', 'Bestätigung an: freundliches Warten.') },
    list: { step: ['list', 'consent'], cap: en('The shared list, usage data as a card.', 'Die gemeinsame Liste, Nutzungsdaten als Karte.') },
    'list-approved': { step: ['list', 'consent'], scr: 'list', cap: en('Approved.', 'Bestätigt.') },
    consent: { step: 'consent', cap: en('A code typed by hand goes the long way: account first, usage data, then “Join with an invite”.', 'Ein getippter Code geht den langen Weg: erst Konto, Nutzungsdaten, dann „Einladung annehmen“.') },
    welcome: { step: 'entry', cap: en('“Welcome to Snacklist”: the only place to type a code.', '„Willkommen bei Snacklist“: der einzige Ort, einen Code zu tippen.') },
    code: { step: 'entry', cap: en('Join with an invite: the code field.', 'Einladung annehmen: das Codefeld.') },
    'code-typed': { step: 'entry', scr: 'code', cap: en('Code typed.', 'Code getippt.') },
    join: { step: 'landing', cap: en('Today’s preview: the household’s name, “Join household”.', 'Die heutige Vorschau: der Haushaltsname, „Haushalt beitreten“.') },
  },
  paths: (sc) => {
    const ok = (a, b) => (sc.approval === 'on' ? [st(a, 'tap', 'primary'), wait(b)] : [st(b.replace('-approved', ''), 'tap', 'primary')]);
    const nativeJoin = [st('acct', 'tap', 'join'), st('apple', 'tap', 'apple'), ...ok('wait', 'list-approved')];
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), auto('home', home)];
      const install = sc.app === 'installed' ? [st('start-jh2', 'tap', 'snacklist')] : [st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-jh2')];
      const list = [...pre, ...install, st('login-jh2', 'tap', 'login'), st('apple-jh2', 'tap', 'apple'), st('consent'), st('welcome', 'tap', 'decline'), st('code', 'tap', 'join-code'), typed('code-typed'), st('join'), ...(sc.approval === 'on' ? [st('wait'), wait('list-approved')] : [st('list')])];
      return { list, app: list };
    }
    const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
    const by = sc.entry === 'qr' ? 'primary' : 'link';
    if (sc.app === 'installed') {
      const list = [entry, st('landing', 'tap', by), ...nativeJoin];
      return { list, app: list };
    }
    const webOk = sc.approval === 'on' ? [st('web-wait'), wait('web-list-approved')] : [st('web-list')];
    const list = [entry, st('web-land', 'tap', by), st('web-acct', 'tap', 'web-join'), st('web-apple', 'tap', 'apple'), ...webOk];
    const app = [...list, st('store-get', 'tap', 'get-app'), st('store-open'), st('start-jh2'), st('login-jh2', 'tap', 'login'), st('apple-jh2', 'tap', 'apple'), st('app-list')];
    return { list, app };
  },
};

// ---- JH3: two doors on the start screen; after installing, tap the same link again ---------------------

const startJH3 = (c) =>
  u.startScreen(c, {
    paste: false,
    buttons: `${btn(c, c.lang === 'de' ? 'Eigene Liste anlegen' : 'Start my own list', { kind: 'primary', by: 'go' })}${btn(c, c.lang === 'de' ? 'Einem Haushalt beitreten' : 'Join a household', { by: 'door', icon: 'group_add_outlined' })}${btn(c, c.T.startLogIn, { kind: 'text', by: 'login' })}`,
  });
const webJH3 = (c) =>
  u.webJoin(c, {
    join: false,
    top: `<ol class="steps-list"><li>${c.lang === 'de' ? 'App laden' : 'Get the app'}</li><li>${c.lang === 'de' ? 'Zurück in den Chat und den Link noch einmal antippen' : 'Go back to the chat and tap the link again'}</li></ol>${btn(c, c.T.web.appStore, { kind: 'primary', by: 'get-app', icon: 'download' })}${btn(c, c.T.web.join, { kind: 'text' })}`,
    codeHint: c.lang === 'de' ? 'Oder in der App: „Einem Haushalt beitreten“ und den Code eintippen.' : 'Or in the app: “Join a household” and type the code.',
  });
const consentSheet = (c, under) =>
  `${under}<div class="scrim"></div><div class="sheet"><div class="handle"></div><div class="sheet-body pad-top"><div class="pad">${u.consentBody(c)}</div></div></div>`;
const jh3 = {
  id: 'JH3',
  name: en('Two doors: tap the link again, or type the code', 'Zwei Türen: Link noch einmal antippen oder Code tippen'),
  line: en(
    'The start screen has two equal doors, “Start my own list” and “Join a household”. Not installed, the join page says: get the app, then tap the link in the chat again; the code is the visible fallback. No service, no clipboard, nothing read from the device. Usage data is a sheet over the first list.',
    'Der Startbildschirm hat zwei gleichwertige Türen, „Eigene Liste anlegen“ und „Einem Haushalt beitreten“. Ohne App sagt die Beitrittsseite: App laden, dann den Link im Chat noch einmal antippen; der Code ist der sichtbare Ausweg. Kein Dienst, keine Zwischenablage, nichts wird vom Gerät gelesen. Nutzungsdaten sind ein Blatt über der ersten Liste.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    ...common,
    'web-jh3': (c) => webJH3(c),
    'start-jh3': (c) => startJH3(c),
    code: (c) => codeScreen(c, { scan: true }),
    'code-typed': (c) => codeScreen(c, { typed: true, scan: true }),
    landing: (c) => landingStd(c),
    acct: (c) => accountOver(c, landingStd(c)),
    apple: (c) => appleOver(c, landingStd(c)),
    wait: (c) => kindWait(c, { mid: `<div class="sticker"><b>${c.lang === 'de' ? 'Während du wartest' : 'While you wait'}</b><p class="small muted">${c.lang === 'de' ? 'Mia sieht deinen Namen und dass du beitreten willst. Sonst nichts.' : 'Mia sees your name and that you want to join. Nothing else.'}</p></div>` }),
    consent: (c) => consentSheet(c, listIn(c)),
    'consent-approved': (c) => consentSheet(c, listIn(c, { snack: c.T.joinApprovedNotice(M(c).household) })),
    list: (c) => listIn(c),
  },
  meta: {
    ...commonMeta,
    'web-jh3': { step: 'landing', cap: en('Not installed: Mia, the household, and two steps, “Get the app” and “tap the link again”. The code stays visible.', 'Ohne App: Mia, der Haushalt und zwei Schritte, „App laden“ und „Link noch einmal antippen“. Der Code bleibt sichtbar.') },
    'start-jh3': { step: 'entry', cap: en('Start screen with two doors. “Join a household” replaces “Paste invite”.', 'Startbildschirm mit zwei Türen. „Einem Haushalt beitreten“ ersetzt „Einladung einfügen“.') },
    code: { step: 'entry', cap: en('Join a household: one code field, “Scan a QR code” under it.', 'Einem Haushalt beitreten: ein Codefeld, darunter „QR-Code scannen“.') },
    'code-typed': { step: 'entry', scr: 'code', cap: en('Code typed.', 'Code getippt.') },
    landing: { step: 'landing', cap: en('The invite in the app: Mia, household, counts.', 'Die Einladung in der App: Mia, Haushalt, Zahlen.') },
    acct: { step: 'account', cap: en('Account sheet over the landing.', 'Konto-Blatt über der Landeseite.') },
    apple: { step: 'account', scr: 'acct', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    wait: { step: 'wait', cap: en('Approval on: what Mia sees, and that the list opens by itself.', 'Bestätigung an: Was Mia sieht, und dass sich die Liste von selbst öffnet.') },
    consent: { step: ['list', 'consent'], cap: en('Joined: usage data as a sheet over the shared list, with today’s text; either answer closes it.', 'Beigetreten: Nutzungsdaten als Blatt über der gemeinsamen Liste, mit dem heutigen Text; jede Antwort schließt es.') },
    'consent-approved': { step: ['list', 'consent'], scr: 'consent', cap: en('Approved: usage data over the list.', 'Bestätigt: Nutzungsdaten über der Liste.') },
    list: { step: 'list', cap: en('The shared list, “You’re in”, once usage data is answered.', 'Die gemeinsame Liste, „Du bist drin“, sobald Nutzungsdaten beantwortet sind.') },
  },
  paths: (sc) => {
    const ok = sc.approval === 'on' ? [st('wait'), wait('consent-approved'), st('list', 'tap', 'decline')] : [st('consent'), st('list', 'tap', 'decline')];
    const join = [st('acct', 'tap', 'join'), st('apple', 'tap', 'apple'), ...ok];
    const viaCode = [st('code', 'tap', 'door'), typed('code-typed'), st('landing'), ...join];
    let list;
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), auto('home', home)];
      list = sc.app === 'installed'
        ? [...pre, st('start-jh3', 'tap', 'snacklist'), ...viaCode]
        : [...pre, st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-jh3'), ...viaCode];
    } else {
      const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
      const by = sc.entry === 'qr' ? 'primary' : 'link';
      if (sc.app === 'installed') list = [entry, st('landing', 'tap', by), ...join];
      else if (sc.entry === 'qr')
        list = [entry, st('web-jh3', 'tap', by), st('store-get', 'tap', 'get-app'), st('store-open'), st('cam-again', 'tap', 'outside', undefined, en('Open the camera, point it at Mia’s QR code again', 'Kamera öffnen, noch einmal auf Mias QR-Code halten')), st('landing', 'tap', 'primary'), ...join];
      else list = [entry, st('web-jh3', 'tap', by), st('store-get', 'tap', 'get-app'), st('store-open'), st('msg-again', 'tap', 'outside', undefined, en('Open WhatsApp again', 'WhatsApp wieder öffnen')), st('landing', 'tap', 'link'), ...join];
    }
    return { list, app: list };
  },
};

// ---- JH4: an App Clip joins before anything is installed ------------------------------------------------

const clipCard = (c, under) =>
  `${under}<div class="scrim"></div><div class="sheet os-sheet clip"><div class="clip-hero"><span class="mark big"><i>${ic('shopping_cart')}</i></span></div><div class="clip-row"><div class="grow"><b>${c.T.os.clipTitle}</b><small class="muted">${c.T.os.clipSub}</small></div><button class="os-btn small" ${act(c)}>${c.T.os.clipOpen}</button></div><p class="tiny muted pad">App Clip · ${c.lang === 'de' ? 'Nichts wird installiert' : 'Nothing is installed'}</p></div>`;
const clipFrame = (c, inner) => `<div class="clipbar">${ic('shopping_cart', 'xs')} App Clip · Snacklist</div>${inner}`;
const clipLanding = (c) =>
  clipFrame(c, u.landing(c, { actions: `${btn(c, `<span class="apple"></span>${c.lang === 'de' ? `Mit Apple beitreten` : `Join with Apple`}`, { kind: 'primary', by: 'apple' })}${notYou(c)}`, body: c.lang === 'de' ? 'Tritt direkt hier bei. Die App kannst du später laden, die Liste kommt mit.' : 'Join right here. Get the app later; the list comes along.' }).replace(u.statusBar(), u.statusBar()));
const fullAppCard = (c) =>
  `<div class="sticker app-card"><b>${c.lang === 'de' ? 'Behalte die Liste auf dem Handy' : 'Keep the list on your phone'}</b><p class="small muted">${c.lang === 'de' ? 'Das App Clip verschwindet nach einiger Zeit. Mit der App bleibt alles, du bist schon angemeldet.' : 'The App Clip goes away after a while. The app keeps everything, and you’re already signed in.'}</p>${btn(c, c.T.os.clipFull, { kind: 'primary', by: 'get-app', icon: 'download' })}</div>`;
const jh4 = {
  id: 'JH4',
  name: en('App Clip: join before installing', 'App Clip: beitreten, bevor etwas installiert ist'),
  line: en(
    'On an iPhone without the app, the link or QR code opens an App Clip card: a small part of Snacklist that runs without installing. Ida joins with Apple inside it and sees the list. “Get the full app” installs Snacklist, which starts signed in. Android has no clip and uses the web join.',
    'Auf einem iPhone ohne App öffnen Link oder QR-Code eine App-Clip-Karte: ein kleiner Teil von Snacklist, der ohne Installation läuft. Ida tritt darin mit Apple bei und sieht die Liste. „Ganze App laden“ installiert Snacklist, die angemeldet startet. Android hat kein Clip und nutzt den Web-Beitritt.',
  ),
  service: en('Apple App Clips (platform, no new processor)', 'Apple App Clips (Plattform, kein neuer Auftragsverarbeiter)'),
  pasteGone: true,
  screens: {
    ...common,
    'clip-card': (c) => clipCard(c, c.scen.entry === 'qr' ? u.camera(c) : u.chat(c, { text: c.T.shareInvite(u.LINK, u.CODE) })),
    'clip-landing': (c) => clipLanding(c),
    'clip-apple': (c) => appleOver(c, clipLanding(c)),
    'clip-wait': (c) => clipFrame(c, kindWait(c)),
    'clip-list': (c) => clipFrame(c, listIn(c, { more: fullAppCard(c) })),
    'clip-list-approved': (c) => clipFrame(c, listIn(c, { more: fullAppCard(c), snack: c.T.joinApprovedNotice(M(c).household) })),
    'clip-store': (c) => `${clipFrame(c, listIn(c, { more: fullAppCard(c) }))}<div class="scrim"></div><div class="sheet os-sheet overlay-store"><div class="clip-row"><span class="mark store-mark"><i>${ic('shopping_cart')}</i></span><div class="grow"><b>Snacklist</b><small class="muted">${c.T.os.storeSub}</small></div><button class="os-btn small" ${act(c)}>${c.T.os.storeGet}</button></div></div>`,
    'clip-store-open': (c) => `${clipFrame(c, listIn(c, { more: fullAppCard(c) }))}<div class="scrim"></div><div class="sheet os-sheet overlay-store"><div class="clip-row"><span class="mark store-mark"><i>${ic('shopping_cart')}</i></span><div class="grow"><b>Snacklist</b><small class="muted">${c.T.os.storeSub}</small></div><button class="os-btn small" ${act(c)}>${c.T.os.storeOpen}</button></div></div>`,
    'app-list': (c) => listIn(c, { consent: true, welcome: false }),
    'start-jh4': (c) => u.startScreen(c, { paste: false, extra: btn(c, c.lang === 'de' ? 'Ich habe einen Einladungscode' : 'I have an invite code', { kind: 'text', by: 'code', icon: 'key_outlined' }) }),
    code: (c) => codeScreen(c),
    'code-typed': (c) => codeScreen(c, { typed: true }),
    landing: (c) => landingStd(c),
    acct: (c) => accountOver(c, landingStd(c)),
    apple: (c) => appleOver(c, landingStd(c)),
    wait: (c) => kindWait(c),
    list: (c) => listIn(c, { consent: true }),
    'list-approved': (c) => listIn(c, { consent: true, snack: c.T.joinApprovedNotice(M(c).household) }),
  },
  meta: {
    ...commonMeta,
    'clip-card': { step: 'install', cap: en('iOS shows the App Clip card for Snacklist: nothing is installed yet.', 'iOS zeigt die App-Clip-Karte von Snacklist: Noch ist nichts installiert.') },
    'clip-landing': { step: 'landing', cap: en('The invite inside the clip: Mia, household, counts. “Join with Apple”.', 'Die Einladung im Clip: Mia, Haushalt, Zahlen. „Mit Apple beitreten“.') },
    'clip-apple': { step: 'account', cap: en('Sign in with Apple inside the clip creates the account.', 'Mit Apple anmelden im Clip legt das Konto an.') },
    'clip-wait': { step: 'wait', cap: en('Approval on: the wait, inside the clip.', 'Bestätigung an: das Warten, im Clip.') },
    'clip-list': { step: 'list', cap: en('The shared list, still in the clip. No usage data in the clip (it collects none).', 'Die gemeinsame Liste, noch im Clip. Keine Nutzungsdaten im Clip (er erfasst keine).') },
    'clip-list-approved': { step: 'list', scr: 'clip-list', cap: en('Approved: the list opens in the clip.', 'Bestätigt: Die Liste öffnet sich im Clip.') },
    'clip-store': { step: 'install', cap: en('“Get the full app”: the store opens over the clip.', '„Ganze App laden“: Der Store öffnet sich über dem Clip.') },
    'clip-store-open': { step: 'install', scr: 'clip-store', cap: en('Installed.', 'Installiert.') },
    'app-list': { step: ['list', 'consent'], cap: en('The app starts signed in (the clip left the session in their shared container). Usage data is a card.', 'Die App startet angemeldet (der Clip hat die Sitzung im gemeinsamen Speicher gelassen). Nutzungsdaten sind eine Karte.') },
    'start-jh4': { step: 'entry', cap: en('Start screen: “I have an invite code” replaces “Paste invite”.', 'Startbildschirm: „Ich habe einen Einladungscode“ ersetzt „Einladung einfügen“.') },
    code: { step: 'entry', cap: en('The code field.', 'Das Codefeld.') },
    'code-typed': { step: 'entry', scr: 'code', cap: en('Code typed.', 'Code getippt.') },
    landing: { step: 'landing', cap: en('Installed: the full app’s landing.', 'Installiert: die Landeseite der App.') },
    acct: { step: 'account', cap: en('Account sheet.', 'Konto-Blatt.') },
    apple: { step: 'account', scr: 'acct', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    wait: { step: 'wait', cap: en('Approval on: a kind wait.', 'Bestätigung an: freundliches Warten.') },
    list: { step: ['list', 'consent'], cap: en('The shared list, usage data as a card.', 'Die gemeinsame Liste, Nutzungsdaten als Karte.') },
    'list-approved': { step: ['list', 'consent'], scr: 'list', cap: en('Approved.', 'Bestätigt.') },
  },
  paths: (sc) => {
    const ok = sc.approval === 'on' ? [st('wait'), wait('list-approved')] : [st('list')];
    const join = [st('acct', 'tap', 'join'), st('apple', 'tap', 'apple'), ...ok];
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), auto('home', home)];
      const viaCode = [st('code', 'tap', 'code'), typed('code-typed'), st('landing'), ...join];
      const list = sc.app === 'installed'
        ? [...pre, st('start-jh4', 'tap', 'snacklist'), ...viaCode]
        : [...pre, st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-jh4'), ...viaCode];
      return { list, app: list };
    }
    const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
    const by = sc.entry === 'qr' ? 'primary' : 'link';
    if (sc.app === 'installed') {
      const list = [entry, st('landing', 'tap', by), ...join];
      return { list, app: list };
    }
    const clipOk = sc.approval === 'on' ? [st('clip-wait'), wait('clip-list-approved')] : [st('clip-list')];
    const list = [entry, st('clip-card', 'tap', by), st('clip-landing'), st('clip-apple', 'tap', 'apple'), ...clipOk];
    const app = [...list, st('clip-store', 'tap', 'get-app'), st('clip-store-open'), st('app-list')];
    return { list, app };
  },
};

// ---- JH5: name first, account later; the wait says what happens ----------------------------------------

const nameField = (c, typedName) =>
  `<div class="lfield"><label>${c.lang === 'de' ? 'Dein Vorname (Mia sieht ihn)' : 'Your first name (Mia sees it)'}</label><div class="hexfield ${typedName ? '' : 'focus'}"><span class="${typedName ? '' : 'muted'}">${typedName ? 'Ida' : c.lang === 'de' ? 'z. B. Ida' : 'e.g. Ida'}</span></div></div>`;
const landingJH5 = (c, typedName) =>
  u.landing(c, {
    mid: nameField(c, typedName),
    actions: `${btn(c, joinLabel(c), { kind: 'primary', by: 'join' })}${notYou(c)}`,
    foot: `<p class="small muted center-t">${c.lang === 'de' ? 'Ohne Konto, ohne Passwort. Sichern kannst du es später mit Apple, Google oder E-Mail.' : 'No account, no password. Save it later with Apple, Google or email.'} ${u.legalLine(c)}</p>`,
  }) + (typedName ? '' : u.keyboard(c));
const saveCard = (c) =>
  `<div class="sticker app-card"><b>${c.lang === 'de' ? 'Zugang sichern' : 'Keep your access'}</b><p class="small muted">${c.lang === 'de' ? 'Damit die Liste auch auf einem neuen Handy da ist.' : 'So the list is there on a new phone too.'}</p><div class="row2">${btn(c, `<span class="apple"></span>Apple`, { by: 'save' })}${btn(c, 'Google')}</div></div>`;
const startJH5 = (c) =>
  u.startScreen(c, {
    paste: false,
    extra: `<div class="sticker invited-card"><b>${c.lang === 'de' ? 'Kommst du von einer Einladung?' : 'Coming from an invite?'}</b><p class="small muted">${c.lang === 'de' ? 'Die Beitrittsseite hat sie kopiert. Setz sie hier ein, dann geht es weiter.' : 'The join page copied it. Paste it here to continue.'}</p><button class="paste-ctl big" ${act(c, 'paste-ctl')}>${ic('content_paste', 'sm')} ${c.lang === 'de' ? 'Einsetzen' : 'Paste'}</button>${btn(c, c.lang === 'de' ? 'Code eintippen' : 'Type a code', { kind: 'text', by: 'code' })}</div>`,
  });
const webJH5 = (c) =>
  u.webJoin(c, {
    join: false,
    top: `${btn(c, `${c.T.web.appStore}`, { kind: 'primary', by: 'get-app', icon: 'download' })}<p class="small muted">${c.lang === 'de' ? 'Der Knopf kopiert deine Einladung. In der App tippst du „Einsetzen“.' : 'The button copies your invite. In the app, tap “Paste”.'}</p>${btn(c, c.T.web.join, { kind: 'text' })}`,
  });
const waitJH5 = (c) =>
  kindWait(c, {
    mid: `<div class="sticker"><b>${c.lang === 'de' ? 'Was Mia sieht' : 'What Mia sees'}</b><p class="small muted">${c.lang === 'de' ? '„Ida möchte Familie Brandt beitreten“, mit Aufnehmen und Ablehnen.' : '“Ida wants to join Brandt family”, with Approve and Decline.'}</p></div>`,
    actions: btn(c, c.lang === 'de' ? 'Sag mir Bescheid, wenn ich drin bin' : 'Tell me when I’m in', { icon: 'notifications_outlined' }),
  });
const jh5 = {
  id: 'JH5',
  name: en('Name first, account later; a clear wait', 'Erst der Name, Konto später; klares Warten'),
  line: en(
    'The landing asks only for a first name, the one Mia sees. “Join” makes a guest account (Supabase anonymous sign-in) and opens the list; a card offers to save the account with Apple, Google or email later. Not installed, the join page’s store button copies the invite and the app’s first screen has a Paste button. The wait says what Mia sees.',
    'Die Landeseite fragt nur nach dem Vornamen, den Mia sieht. „Beitreten“ legt ein Gastkonto an (anonyme Supabase-Anmeldung) und öffnet die Liste; eine Karte bietet an, das Konto später mit Apple, Google oder E-Mail zu sichern. Ohne App kopiert der Store-Knopf der Beitrittsseite die Einladung, und der erste Bildschirm der App hat einen Einsetzen-Knopf. Das Warten sagt, was Mia sieht.',
  ),
  service: en('Supabase anonymous sign-ins (our stack)', 'Anonyme Supabase-Anmeldung (unser Stack)'),
  pasteGone: true,
  screens: {
    ...common,
    'web-jh5': (c) => webJH5(c),
    'start-jh5': (c) => startJH5(c),
    code: (c) => codeScreen(c),
    'code-typed': (c) => codeScreen(c, { typed: true }),
    landing: (c) => landingJH5(c, false),
    'landing-named': (c) => landingJH5(c, true),
    wait: (c) => waitJH5(c),
    list: (c) => listIn(c, { more: `${saveCard(c)}${u.consentCard(c)}` }),
    'list-approved': (c) => listIn(c, { more: `${saveCard(c)}${u.consentCard(c)}`, snack: c.T.joinApprovedNotice(M(c).household) }),
  },
  meta: {
    ...commonMeta,
    'web-jh5': { step: 'landing', cap: en('Not installed: the join page’s store button also copies the invite (her tap, no prompt).', 'Ohne App: Der Store-Knopf der Beitrittsseite kopiert auch die Einladung (ihr Tipp, keine Nachfrage).') },
    'start-jh5': { step: 'entry', cap: en('First start: “Coming from an invite?” with the system Paste button (reads the clipboard only on that tap, no iOS prompt).', 'Erster Start: „Kommst du von einer Einladung?“ mit dem System-Einsetzen-Knopf (liest die Zwischenablage nur auf diesen Tipp, ohne iOS-Nachfrage).') },
    code: { step: 'entry', cap: en('“Type a code”: the code field.', '„Code eintippen“: das Codefeld.') },
    'code-typed': { step: 'entry', scr: 'code', cap: en('Code typed.', 'Code getippt.') },
    landing: { step: 'landing', cap: en('The invite: Mia, household, counts, and one field, her first name for Mia.', 'Die Einladung: Mia, Haushalt, Zahlen und ein Feld, ihr Vorname für Mia.') },
    'landing-named': { step: ['landing', 'account'], scr: 'landing', cap: en('Name typed. “Join” creates a guest account (no password). Imprint and Privacy under it.', 'Name getippt. „Beitreten“ legt ein Gastkonto an (ohne Passwort). Impressum und Datenschutz darunter.') },
    wait: { step: 'wait', cap: en('Approval on: “Mia will let you in”, what Mia sees, and an offer to notify (asked only on that tap).', 'Bestätigung an: „Mia lässt dich gleich rein“, was Mia sieht, und Bescheid auf Wunsch (nur auf diesen Tipp gefragt).') },
    list: { step: ['list', 'consent'], cap: en('The shared list. Cards: save the account (Apple, Google), then usage data.', 'Die gemeinsame Liste. Karten: Konto sichern (Apple, Google), dann Nutzungsdaten.') },
    'list-approved': { step: ['list', 'consent'], scr: 'list', cap: en('Approved: the list opens by itself.', 'Bestätigt: Die Liste öffnet sich von selbst.') },
  },
  paths: (sc) => {
    const ok = sc.approval === 'on' ? [st('wait', 'tap', 'join'), wait('list-approved')] : [st('list', 'tap', 'join')];
    const named = [typed('landing-named', en('Type “Ida”', '„Ida“ tippen')), ...ok];
    if (sc.entry === 'code') {
      const pre = [st('msg-code', 'start'), auto('home', home)];
      const viaCode = [st('code', 'tap', 'code'), typed('code-typed'), st('landing'), ...named];
      const list = sc.app === 'installed'
        ? [...pre, st('start-jh5', 'tap', 'snacklist'), ...viaCode]
        : [...pre, st('store-get', 'tap', 'store', 2, searchStore), st('store-open'), st('start-jh5'), ...viaCode];
      return { list, app: list };
    }
    const entry = sc.entry === 'qr' ? st('cam', 'start') : st('msg', 'start');
    const by = sc.entry === 'qr' ? 'primary' : 'link';
    const list = sc.app === 'installed'
      ? [entry, st('landing', 'tap', by), ...named]
      : [entry, st('web-jh5', 'tap', by), st('store-get', 'tap', 'get-app'), st('store-open'), st('start-jh5'), st('landing', 'tap', 'paste-ctl'), ...named];
    return { list, app: list };
  },
};

const en2 = en;
export const round = {
  T,
  options: [today, jh1, jh2, jh3, jh4, jh5],
  scenarios: {
    entry: { label: en2('Entry', 'Einstieg'), values: ['link', 'qr', 'code'], names: { link: en2('Invite link', 'Einladungslink'), qr: en2('QR code', 'QR-Code'), code: en2('Code typed', 'Code getippt') } },
    app: { label: en2('App', 'App'), values: ['missing', 'installed'], names: { missing: en2('Not installed', 'Nicht installiert'), installed: en2('Installed', 'Installiert') } },
    approval: { label: en2('Confirm new members', 'Beitritte bestätigen'), values: ['off', 'on'], names: { off: en2('Off', 'Aus'), on: en2('On', 'An') } },
  },
  goals: [
    { key: 'list', label: en2('First shared list', 'Erste gemeinsame Liste') },
    { key: 'app', label: en2('Shared list in the app', 'Gemeinsame Liste in der App') },
  ],
  steps: {
    entry: { n: 1, ...en2('Entry', 'Einstieg') },
    install: { n: '↓', ...en2('Install', 'Installieren') },
    landing: { n: 2, ...en2('Landing', 'Landeseite') },
    account: { n: 3, ...en2('Account', 'Konto') },
    consent: { n: 4, ...en2('Consent', 'Einwilligung') },
    wait: { n: 5, ...en2('Approval wait', 'Warten auf Bestätigung') },
    list: { n: 6, ...en2('Shared list', 'Gemeinsame Liste') },
  },
  via: {
    tap: en2('tap', 'Tipp'), scan: en2('scan', 'scannen'), type: en2('typing', 'Tippen von Text'), wait: en2('waiting', 'warten'), auto: en2('no tap', 'kein Tipp'),
  },
  viaIcon: { scan: 'qr_code_scanner', type: 'keyboard', wait: 'hourglass_top_outlined', auto: 'arrow_forward', tap: 'touch_app' },
  facts: ['paste', 'manual', 'deferred', 'firstList', 'approval', 'consent', 'privacy', 'build', 'service'],
  detail: ['entry', 'landing', 'account', 'consent', 'approval', 'firstList', 'manual', 'deferred', 'privacy', 'leaves', 'build', 'service', 'risks'],
  detailNames: {
    entry: en2('1 Entry', '1 Einstieg'), landing: en2('2 Landing', '2 Landeseite'), account: en2('3 Account', '3 Konto'), consent: en2('4 Consent and legal', '4 Einwilligung und Rechtliches'),
    approval: en2('5 Approval on / off', '5 Bestätigung an / aus'), firstList: en2('6 First screen in the list', '6 Erster Bildschirm in der Liste'), manual: en2('“I have an invite” lives', '„Ich habe eine Einladung“ steht'),
    deferred: en2('Not installed (deferred link)', 'Nicht installiert (verzögerter Link)'), privacy: en2('Privacy exposure', 'Datenschutz-Exposition'), leaves: en2('What leaves the device', 'Was das Gerät verlässt'),
    build: en2('Build effort (estimate)', 'Bauaufwand (Schätzung)'), service: en2('Existing service', 'Fertiger Dienst'), risks: en2('Risks and open points', 'Risiken und offene Punkte'),
  },
  rec: { pick: 'JH5', runnerUp: 'JH3', file: 'RECOMMENDATION' },
  page: {
    en: {
      title: 'Joining a household (JH1–JH5)', back: 'All prototype rounds', overview: 'Overview', rec: 'Recommendation', light: 'Light', dark: 'Dark', text: 'Text',
      compare: 'Five end-to-end ways for a new user to join a household they were invited to, next to Today (main’s link, sign-in, usage data, join screen, approval wait and “Paste invite”). Each covers the invite link with and without the app, a QR code and a typed code, the landing, the account, consent, the approval wait when “Confirm new members” is on, and the first screen in the shared list. Mock data, measured on an iPhone.',
      tap: 'tap', taps: 'taps', screens: 'screens', typed: 'plus typing', pick: 'Pick', runnerUp: 'Runner-up', stack: 'today’s stack, no new vendor', pasteGone: '“Paste invite” gone', pasteKept: '“Paste invite” kept',
      table: 'Comparison', allScen: 'all 12 scenarios',
      cols: ['Option', 'Taps / screens to the first shared list', 'Taps / screens to the shared list in the app', '“Paste invite”', 'Manual “I have an invite”', 'Not installed (deferred link)', 'First list in', 'Approval wait', 'Consent', 'Privacy exposure', 'Build effort', 'Existing service'],
      tapsNote: 'Taps and screens are measured by walking each path: the bold numbers are the scenario picked above, the small ones the range over all 12 scenarios (3 entries × installed or not × approval on or off). A tap on a button, a link, the camera’s link or a system sheet counts 1; “open the App Store and search” counts 2; copying from a chat (hold, Copy) 2. Typing text, waiting for Mia and switching apps count 0. Screens are the distinct screens after the invite: an app sheet counts as a screen, the system “Sign in with Apple” sheet and a typed field do not. verify.mjs drives every path with real clicks and checks the numbers.',
      side: 'Side by side', sideNote: 'Every option’s path for the scenario picked above, to the shared list in the app. Open an option for big phones and Try it.',
      factsTitle: 'The six steps, the hand-off and the effort', tryIt: 'Try it', reset: 'Start again', tapHint: 'Tap the outlined control in the phone.',
      soFar: (n) => `${n} ${n === 1 ? 'tap' : 'taps'} so far`, doneAfter: (n, s) => `Done: ${n} ${n === 1 ? 'tap' : 'taps'}, ${s} steps.`,
      goalNow: (g, t, s) => `${g}: ${t} taps, ${s} screens on this path.`,
      partTitle: (g, n) => `${g}: from step ${n}, where the paths part`,
    },
    de: {
      title: 'Einem Haushalt beitreten (JH1–JH5)', back: 'Alle Prototyp-Runden', overview: 'Überblick', rec: 'Empfehlung', light: 'Hell', dark: 'Dunkel', text: 'Text',
      compare: 'Fünf durchgehende Wege, wie jemand Neues einem Haushalt beitritt, zu dem er eingeladen wurde, neben Heute (Link, Anmeldung, Nutzungsdaten, Beitrittsseite, Warten auf Bestätigung und „Einladung einfügen“ auf main). Jeder deckt den Einladungslink mit und ohne App, einen QR-Code und einen getippten Code ab, die Landeseite, das Konto, die Einwilligung, das Warten, wenn „Beitritte bestätigen“ an ist, und den ersten Bildschirm in der gemeinsamen Liste. Beispieldaten, gemessen auf einem iPhone.',
      tap: 'Tipp', taps: 'Tipps', screens: 'Bildschirme', typed: 'plus Tippen von Text', pick: 'Empfehlung', runnerUp: 'Zweite Wahl', stack: 'unser Stack, kein neuer Anbieter', pasteGone: '„Einladung einfügen“ entfällt', pasteKept: '„Einladung einfügen“ bleibt',
      table: 'Vergleich', allScen: 'alle 12 Szenarien',
      cols: ['Variante', 'Tipps / Bildschirme bis zur ersten gemeinsamen Liste', 'Tipps / Bildschirme bis zur Liste in der App', '„Einladung einfügen“', 'Manuell „Ich habe eine Einladung“', 'Nicht installiert (verzögerter Link)', 'Erste Liste in', 'Warten auf Bestätigung', 'Einwilligung', 'Datenschutz-Exposition', 'Bauaufwand', 'Fertiger Dienst'],
      tapsNote: 'Tipps und Bildschirme werden gemessen, indem jeder Weg durchgegangen wird: fett das oben gewählte Szenario, klein der Bereich über alle 12 Szenarien (3 Einstiege × installiert oder nicht × Bestätigung an oder aus). Ein Tipp auf einen Knopf, einen Link, den Link der Kamera oder ein System-Blatt zählt 1; „App Store öffnen und suchen“ zählt 2; Kopieren aus einem Chat (halten, Kopieren) 2. Text tippen, auf Mia warten und App wechseln zählen 0. Bildschirme sind die verschiedenen Bildschirme nach der Einladung: Ein Blatt der App zählt als Bildschirm, das System-Blatt „Mit Apple anmelden“ und ein getipptes Feld nicht. verify.mjs geht jeden Weg mit echten Klicks durch und prüft die Zahlen.',
      side: 'Nebeneinander', sideNote: 'Der Weg jeder Variante im oben gewählten Szenario, bis zur Liste in der App. Öffne eine Variante für große Handys und Ausprobieren.',
      factsTitle: 'Die sechs Schritte, die Übergabe und der Aufwand', tryIt: 'Ausprobieren', reset: 'Neu starten', tapHint: 'Tippe im Handy auf das umrandete Element.',
      soFar: (n) => `bisher ${n} ${n === 1 ? 'Tipp' : 'Tipps'}`, doneAfter: (n, s) => `Fertig: ${n} ${n === 1 ? 'Tipp' : 'Tipps'}, ${s} Schritte.`,
      goalNow: (g, t, s) => `${g}: ${t} Tipps, ${s} Bildschirme auf diesem Weg.`,
      partTitle: (g, n) => `${g}: ab Schritt ${n}, wo sich die Wege trennen`,
    },
  },
};

// Table cells and the facts box: one record per option.
today.facts = ({
  paste: en('kept, on start and sign-in', 'bleibt, auf Start und Anmeldung'),
  manual: en('“Paste invite” on start and sign-in; “Join with an invite” after sign-in', '„Einladung einfügen“ auf Start und Anmeldung; „Einladung annehmen“ nach der Anmeldung'),
  deferred: en('none: web join stays in the browser; Paste invite if the code was copied', 'keiner: Web-Beitritt bleibt im Browser; Einladung einfügen, wenn der Code kopiert wurde'),
  firstList: en('app (installed) or browser', 'App (installiert) oder Browser'),
  approval: en('“Request sent”; first button “Create your own household”', '„Anfrage gesendet“; erster Knopf „Eigenen Haushalt anlegen“'),
  consent: en('full screen before the join, again per install', 'ganzer Bildschirm vor dem Beitritt, je Installation erneut'),
  privacy: en('low: nothing new', 'niedrig: nichts Neues'),
  build: en('0 (live)', '0 (live)'),
  service: en('none', 'keiner'),
});
jh1.facts = ({
  paste: en('gone', 'entfällt'),
  manual: en('“I have a code” in the start screen’s invite card', '„Ich habe einen Code“ in der Einladungskarte des Startbildschirms'),
  deferred: en('the service matches the install to the tap, after “I was invited” (iOS by IP and device type; Android by store referrer)', 'der Dienst ordnet die Installation dem Tipp zu, nach „Ich wurde eingeladen“ (iOS über IP und Gerätetyp; Android über den Store-Referrer)'),
  firstList: en('app', 'App'),
  approval: en('“Mia will let you in”, list opens by itself, no “create your own”', '„Mia lässt dich gleich rein“, Liste öffnet sich selbst, kein „eigenen anlegen“'),
  consent: en('card on the first list', 'Karte auf der ersten Liste'),
  privacy: en('high: new US-parented processor gets IP, user agent, device data at click and first start', 'hoch: neuer Auftragsverarbeiter mit US-Mutter bekommt IP, User-Agent, Gerätedaten bei Klick und erstem Start'),
  build: en('7 days + DPA, Legal', '7 Tage + AVV, Legal'),
  service: en('Branch or AppsFlyer OneLink', 'Branch oder AppsFlyer OneLink'),
});
jh2.facts = ({
  paste: en('gone', 'entfällt'),
  manual: en('“Join with an invite” on Welcome, after sign-in only', '„Einladung annehmen“ auf Willkommen, erst nach der Anmeldung'),
  deferred: en('not needed: she joins on the web; the membership is on her account', 'nicht nötig: Sie tritt im Web bei; die Mitgliedschaft hängt am Konto'),
  firstList: en('browser (app installed: app)', 'Browser (App installiert: App)'),
  approval: en('kind wait; “Get the app” offered while waiting', 'freundliches Warten; „App laden“ in der Wartezeit'),
  consent: en('card on the list; asked again in the app (per install)', 'Karte auf der Liste; in der App erneut (je Installation)'),
  privacy: en('low: nothing new', 'niedrig: nichts Neues'),
  build: en('4 days', '4 Tage'),
  service: en('none (today’s web app)', 'keiner (heutige Web-App)'),
});
jh3.facts = ({
  paste: en('gone', 'entfällt'),
  manual: en('“Join a household”, an equal second door on the start screen (code or QR)', '„Einem Haushalt beitreten“, gleichwertige zweite Tür auf dem Startbildschirm (Code oder QR)'),
  deferred: en('the join page says “get the app, then tap the link again”; the code is the fallback', 'die Beitrittsseite sagt „App laden, dann Link noch einmal antippen“; der Code ist der Ausweg'),
  firstList: en('app', 'App'),
  approval: en('kind wait, says what Mia sees', 'freundliches Warten, sagt, was Mia sieht'),
  consent: en('sheet over the first list (1 tap)', 'Blatt über der ersten Liste (1 Tipp)'),
  privacy: en('low: nothing read from the device', 'niedrig: nichts wird vom Gerät gelesen'),
  build: en('4 days (scanner later, JH-Q8)', '4 Tage (Scanner später, JH-Q8)'),
  service: en('none', 'keiner'),
});
jh4.facts = ({
  paste: en('gone', 'entfällt'),
  manual: en('“I have an invite code” under the start buttons', '„Ich habe einen Einladungscode“ unter den Start-Knöpfen'),
  deferred: en('iOS: the App Clip joins and hands the session to the app; Android: web join', 'iOS: Das App Clip tritt bei und übergibt die Sitzung an die App; Android: Web-Beitritt'),
  firstList: en('App Clip, then app', 'App Clip, dann App'),
  approval: en('kind wait inside the clip', 'freundliches Warten im Clip'),
  consent: en('none in the clip; card in the app', 'keine im Clip; Karte in der App'),
  privacy: en('low: Apple only (already the store)', 'niedrig: nur Apple (ohnehin der Store)'),
  build: en('15 days (second iOS target, Flutter in a clip)', '15 Tage (zweites iOS-Target, Flutter im Clip)'),
  service: en('Apple App Clips', 'Apple App Clips'),
});
jh5.facts = ({
  paste: en('gone; a system Paste button on the first start', 'entfällt; ein System-Einsetzen-Knopf beim ersten Start'),
  manual: en('“Type a code” in the first start’s invite card', '„Code eintippen“ in der Einladungskarte beim ersten Start'),
  deferred: en('the join page’s store button copies the invite; the app’s Paste button reads it on her tap', 'der Store-Knopf der Beitrittsseite kopiert die Einladung; der Einsetzen-Knopf der App liest sie auf ihren Tipp'),
  firstList: en('app', 'App'),
  approval: en('wait shows what Mia sees, offers a notification', 'Warten zeigt, was Mia sieht, bietet Bescheid an'),
  consent: en('card on the list, after “Keep your access”', 'Karte auf der Liste, nach „Zugang sichern“'),
  privacy: en('medium: a guest account without email; clipboard read on her tap', 'mittel: Gastkonto ohne E-Mail; Zwischenablage auf ihren Tipp'),
  build: en('10 days (guest accounts, invite check, upgrade; JH-Q10)', '10 Tage (Gastkonten, Code-Prüfung, Upgrade; JH-Q10)'),
  service: en('Supabase anonymous sign-ins', 'Anonyme Supabase-Anmeldung'),
});

today.detail = {
  entry: en('Link in WhatsApp, QR from a group link (person invites have no QR), or a code read off a message.', 'Link in WhatsApp, QR eines Gruppenlinks (Einladungen für eine Person haben keinen QR), oder ein Code aus einer Nachricht.'),
  landing: en('Installed: none before the account; the sign-in says “Invite saved”, and the join screen after it names only the household. Not installed: the static join page names Mia, the household and the counts.', 'Installiert: keine vor dem Konto; die Anmeldung sagt „Einladung gemerkt“, die Beitrittsseite danach nennt nur den Haushalt. Ohne App: Die statische Beitrittsseite nennt Mia, den Haushalt und die Zahlen.'),
  account: en('The sign-in screen: Apple, Google, email.', 'Die Anmeldung: Apple, Google, E-Mail.'),
  consent: en('Full usage-data screen between sign-in and join; per install, so asked again on the web and in the app.', 'Ganzer Nutzungsdaten-Bildschirm zwischen Anmeldung und Beitritt; je Installation, also im Web und in der App erneut.'),
  approval: en('“Request sent”, primary button “Create your own household”, “Withdraw request”; the list opens by itself when approved.', '„Anfrage gesendet“, Hauptknopf „Eigenen Haushalt anlegen“, „Anfrage zurückziehen“; die Liste öffnet sich von selbst nach der Bestätigung.'),
  firstList: en('The list with First steps (“Joined the household”).', 'Die Liste mit Erste Schritte („Haushalt beigetreten“).'),
  manual: en('“Paste invite” on the start screen (no space above it, Peter’s screenshot) and on sign-in; “Join with an invite” on Welcome after sign-in.', '„Einladung einfügen“ auf dem Startbildschirm (ohne Abstand darüber, Peters Screenshot) und auf der Anmeldung; „Einladung annehmen“ auf Willkommen nach der Anmeldung.'),
  deferred: en('None. The link opens the web join page; joining there stays in the browser. To use the app, install it and sign in again; Paste invite carries a code copied before.', 'Keiner. Der Link öffnet die Web-Beitrittsseite; wer dort beitritt, bleibt im Browser. Für die App: installieren und neu anmelden; Einladung einfügen trägt einen vorher kopierten Code.'),
  privacy: en('Low.', 'Niedrig.'),
  leaves: en('Nothing beyond today: the code to our server; the clipboard is read only on the Paste tap.', 'Nichts über heute hinaus: der Code an unseren Server; die Zwischenablage nur auf den Einfügen-Tipp.'),
  build: en('Live.', 'Live.'),
  service: en('None.', 'Keiner.'),
  risks: en('A referred user who installs from the store first lands on “Get started” and builds a household of her own. Nothing before sign-in says who invited her.', 'Wer zuerst aus dem Store installiert, landet auf „Los geht’s“ und legt einen eigenen Haushalt an. Vor der Anmeldung sagt nichts, wer einlädt.'),
};
jh1.detail = {
  entry: en('Link (a service link on our domain), QR (the same link), or a code typed in “I have a code”.', 'Link (ein Dienst-Link auf unserer Domain), QR (derselbe Link) oder ein Code in „Ich habe einen Code“.'),
  landing: en('In the app: Mia, household, members, open items, Premium if set. Shown before any account.', 'In der App: Mia, Haushalt, Mitglieder, offene Einträge, Premium falls gesetzt. Vor jedem Konto.'),
  account: en('“Create your account to join”: a sheet over the landing (Apple, Google, email; Imprint, Privacy).', '„Konto erstellen, um beizutreten“: ein Blatt über der Landeseite (Apple, Google, E-Mail; Impressum, Datenschutz).'),
  consent: en('Usage data is a card on the first list, two equal buttons; nothing blocks the join. The service’s match is its own question (see risks).', 'Nutzungsdaten sind eine Karte auf der ersten Liste, zwei gleiche Knöpfe; nichts blockiert den Beitritt. Der Abgleich des Dienstes ist eine eigene Frage (siehe Risiken).'),
  approval: en('Off: the list. On: “Mia will let you in”, the list opens by itself, “Withdraw request” only.', 'Aus: die Liste. An: „Mia lässt dich gleich rein“, die Liste öffnet sich von selbst, nur „Anfrage zurückziehen“.'),
  firstList: en('The list with “You’re in Brandt family” and the usage-data card.', 'Die Liste mit „Du bist in Familie Brandt“ und der Nutzungsdaten-Karte.'),
  manual: en('“I have a code” in the start screen’s invite card.', '„Ich habe einen Code“ in der Einladungskarte des Startbildschirms.'),
  deferred: en('The service notes the tap on the link and matches the first start to it, when she taps “I was invited” (not automatically, Legal N-111).', 'Der Dienst merkt sich den Tipp auf den Link und ordnet ihm den ersten Start zu, wenn sie „Ich wurde eingeladen“ tippt (nicht automatisch, Legal N-111).'),
  privacy: en('High.', 'Hoch.'),
  leaves: en('To the service: IP address, user agent and device data at the click and again at first start, and the invite code. Branch keeps aggregates in North America; EU hosting is a sales add-on (RESEARCH §2.4).', 'An den Dienst: IP-Adresse, User-Agent und Gerätedaten beim Klick und beim ersten Start, und der Einladungscode. Branch hält Aggregate in Nordamerika; EU-Hosting ist ein Vertriebs-Zusatz (RESEARCH §2.4).'),
  build: en('About 7 days: SDK in both apps, link domain, the invited card, Legal and a DPA; paid tier likely.', 'Etwa 7 Tage: SDK in beiden Apps, Link-Domain, die Einladungskarte, Legal und AVV; wohl ein bezahlter Tarif.'),
  service: en('Branch or AppsFlyer OneLink (Firebase Dynamic Links shut down on 25 Aug 2025).', 'Branch oder AppsFlyer OneLink (Firebase Dynamic Links ist seit 25. Aug. 2025 abgeschaltet).'),
  risks: en('iOS matching is fingerprinting (IP plus device data): consent under § 25 TDDDG and ePrivacy 5(3), and Apple’s rules. If the service is down, links must still open our join page (our domain). A new processor and a cost.', 'Der iOS-Abgleich ist Fingerprinting (IP plus Gerätedaten): Einwilligung nach § 25 TDDDG und ePrivacy 5(3), dazu Apples Regeln. Fällt der Dienst aus, müssen Links weiter unsere Beitrittsseite öffnen (unsere Domain). Neuer Auftragsverarbeiter und Kosten.'),
};
jh2.detail = {
  entry: en('Link or QR open the join page (installed: the app). A code is typed only after an account exists.', 'Link oder QR öffnen die Beitrittsseite (installiert: die App). Ein Code wird erst getippt, wenn es ein Konto gibt.'),
  landing: en('The static join page, reworded: “Join Brandt family” is the main button and says no app is needed.', 'Die statische Beitrittsseite, neu formuliert: „Familie Brandt beitreten“ ist der Hauptknopf und sagt, dass keine App nötig ist.'),
  account: en('A sheet over the join page: Apple, Google, email. The web sign-in exists today.', 'Ein Blatt über der Beitrittsseite: Apple, Google, E-Mail. Die Web-Anmeldung gibt es heute.'),
  consent: en('A card on the list in the browser; the app asks again (one answer per install).', 'Eine Karte auf der Liste im Browser; die App fragt erneut (eine Antwort je Installation).'),
  approval: en('Off: the list in the browser. On: a kind wait that offers the app meanwhile.', 'Aus: die Liste im Browser. An: freundliches Warten, das in der Zeit die App anbietet.'),
  firstList: en('The list in the browser, with “Get the app” and the usage-data card.', 'Die Liste im Browser, mit „App laden“ und der Nutzungsdaten-Karte.'),
  manual: en('Only “Join with an invite” on Welcome, after an account: a typed code is the long way.', 'Nur „Einladung annehmen“ auf Willkommen, nach einem Konto: Ein getippter Code ist der lange Weg.'),
  deferred: en('Not needed: the membership is on her account. In the app she signs in with the same Apple ID.', 'Nicht nötig: Die Mitgliedschaft hängt an ihrem Konto. In der App meldet sie sich mit derselben Apple-ID an.'),
  privacy: en('Low.', 'Niedrig.'),
  leaves: en('Nothing new.', 'Nichts Neues.'),
  build: en('About 4 days: join page copy and account sheet, kind wait, the get-the-app card.', 'Etwa 4 Tage: Text und Konto-Blatt der Beitrittsseite, freundliches Warten, die App-Karte.'),
  service: en('None: the web app and the static join page are live.', 'Keiner: Web-App und statische Beitrittsseite sind live.'),
  risks: en('Flutter web is heavy on a phone; a user who stays in the browser has no Siri, widgets or push. Two sign-ins, two consent answers. In-app browsers (Instagram) keep the session there.', 'Flutter-Web ist auf dem Handy schwer; wer im Browser bleibt, hat kein Siri, keine Widgets, keine Mitteilungen. Zwei Anmeldungen, zwei Einwilligungen. In-App-Browser (Instagram) behalten die Sitzung dort.'),
};
jh3.detail = {
  entry: en('Link or QR; a code via “Join a household”, which also scans a QR.', 'Link oder QR; ein Code über „Einem Haushalt beitreten“, das auch QR scannt.'),
  landing: en('In the app: Mia, household, counts. Not installed: the join page with two numbered steps.', 'In der App: Mia, Haushalt, Zahlen. Ohne App: die Beitrittsseite mit zwei nummerierten Schritten.'),
  account: en('A sheet over the landing (Apple, Google, email; Imprint, Privacy).', 'Ein Blatt über der Landeseite (Apple, Google, E-Mail; Impressum, Datenschutz).'),
  consent: en('A sheet over the first list with today’s text; either answer closes it (counted as a tap).', 'Ein Blatt über der ersten Liste mit dem heutigen Text; jede Antwort schließt es (als Tipp gezählt).'),
  approval: en('Off: the list. On: the wait says what Mia sees (her name and the wish to join) and that the list opens by itself.', 'Aus: die Liste. An: Das Warten sagt, was Mia sieht (ihren Namen und den Beitrittswunsch), und dass sich die Liste von selbst öffnet.'),
  firstList: en('The list with “You’re in”, once the usage-data sheet is answered.', 'Die Liste mit „Du bist drin“, sobald das Nutzungsdaten-Blatt beantwortet ist.'),
  manual: en('“Join a household”, the second of two equal doors on the start screen.', '„Einem Haushalt beitreten“, die zweite von zwei gleichwertigen Türen auf dem Startbildschirm.'),
  deferred: en('No carry-over. The page says: get the app, then tap the link in the chat again (now a universal link). A QR scan goes through the door instead.', 'Keine Übergabe. Die Seite sagt: App laden, dann den Link im Chat noch einmal antippen (jetzt ein Universal Link). Ein QR-Scan geht stattdessen über die Tür.'),
  privacy: en('Low.', 'Niedrig.'),
  leaves: en('Nothing new; nothing is read from the device.', 'Nichts Neues; nichts wird vom Gerät gelesen.'),
  build: en('About 4 days: two doors, code screen, landing, account sheet, join page steps. The QR scanner shown on the code screen is extra (JH-Q8).', 'Etwa 4 Tage: zwei Türen, Codeschirm, Landeseite, Konto-Blatt, Schritte auf der Beitrittsseite. Der QR-Scanner auf dem Codeschirm kommt extra (JH-Q8).'),
  service: en('None.', 'Keiner.'),
  risks: en('Some users won’t go back to the chat; the code and the second door catch them. The in-app QR scanner adds a camera prompt.', 'Manche gehen nicht zurück in den Chat; Code und zweite Tür fangen sie auf. Der QR-Scanner in der App bringt eine Kamera-Nachfrage.'),
};
jh4.detail = {
  entry: en('Link or QR open the App Clip card on an iPhone without the app; a code goes through “I have an invite code”.', 'Link oder QR öffnen auf einem iPhone ohne App die App-Clip-Karte; ein Code geht über „Ich habe einen Einladungscode“.'),
  landing: en('Inside the clip: Mia, household, counts, “Join with Apple”.', 'Im Clip: Mia, Haushalt, Zahlen, „Mit Apple beitreten“.'),
  account: en('Sign in with Apple inside the clip.', 'Mit Apple anmelden im Clip.'),
  consent: en('None in the clip (it collects nothing); a card once the full app starts.', 'Keine im Clip (er erfasst nichts); eine Karte, sobald die App startet.'),
  approval: en('Off: the list in the clip. On: the wait in the clip.', 'Aus: die Liste im Clip. An: das Warten im Clip.'),
  firstList: en('The list inside the clip, with “Keep the list on your phone”.', 'Die Liste im Clip, mit „Behalte die Liste auf dem Handy“.'),
  manual: en('“I have an invite code” under the start buttons.', '„Ich habe einen Einladungscode“ unter den Start-Knöpfen.'),
  deferred: en('The clip writes the session to the App Group it shares with the app; the app starts signed in. Android: web join (no clip).', 'Der Clip legt die Sitzung in die App Group, die er mit der App teilt; die App startet angemeldet. Android: Web-Beitritt (kein Clip).'),
  privacy: en('Low.', 'Niedrig.'),
  leaves: en('Nothing new: Apple already runs the store; the session stays on the phone.', 'Nichts Neues: Apple betreibt ohnehin den Store; die Sitzung bleibt auf dem Handy.'),
  build: en('About 15 days: a second iOS target with a Flutter engine inside the clip’s size limit, App Clip experiences, the session hand-off. Not verified that WhatsApp links show the card.', 'Etwa 15 Tage: ein zweites iOS-Target mit Flutter-Engine in der Größengrenze des Clips, App-Clip-Erlebnisse, die Sitzungsübergabe. Nicht geprüft, ob WhatsApp-Links die Karte zeigen.'),
  service: en('Apple App Clips.', 'Apple App Clips.'),
  risks: en('Size limit with Flutter; iOS only; a second build in the release pipeline. Legal: is the hand-off through the shared container an automatic read?', 'Größengrenze mit Flutter; nur iOS; ein zweiter Build in der Release-Pipeline. Legal: Ist die Übergabe über den gemeinsamen Speicher ein automatisches Auslesen?'),
};
jh5.detail = {
  entry: en('Link or QR open the landing; a code through “Type a code”.', 'Link oder QR öffnen die Landeseite; ein Code über „Code eintippen“.'),
  landing: en('In the app: Mia, household, counts, and one field, her first name for Mia.', 'In der App: Mia, Haushalt, Zahlen und ein Feld, ihr Vorname für Mia.'),
  account: en('“Join” creates a guest account (Supabase anonymous sign-in). A card later saves it with Apple, Google or email.', '„Beitreten“ legt ein Gastkonto an (anonyme Supabase-Anmeldung). Eine Karte sichert es später mit Apple, Google oder E-Mail.'),
  consent: en('A card on the list, under “Keep your access”.', 'Eine Karte auf der Liste, unter „Zugang sichern“.'),
  approval: en('On: “Mia will let you in”, what Mia sees, “Tell me when I’m in” (notification prompt only on that tap).', 'An: „Mia lässt dich gleich rein“, was Mia sieht, „Sag mir Bescheid, wenn ich drin bin“ (Mitteilungs-Nachfrage nur auf diesen Tipp).'),
  firstList: en('The list with “You’re in”, “Keep your access” and the usage-data card.', 'Die Liste mit „Du bist drin“, „Zugang sichern“ und der Nutzungsdaten-Karte.'),
  manual: en('“Type a code” in the first start’s invite card.', '„Code eintippen“ in der Einladungskarte beim ersten Start.'),
  deferred: en('The join page’s store button copies the invite (her tap). In the app, the system Paste button reads it on her tap (no iOS prompt).', 'Der Store-Knopf der Beitrittsseite kopiert die Einladung (ihr Tipp). In der App liest der System-Einsetzen-Knopf sie auf ihren Tipp (keine iOS-Nachfrage).'),
  privacy: en('Medium.', 'Mittel.'),
  leaves: en('Her first name and the code to our server; nothing to a third party. The clipboard is read only on her Paste tap.', 'Ihr Vorname und der Code an unseren Server; nichts an Dritte. Die Zwischenablage nur auf ihren Einsetzen-Tipp.'),
  build: en('About 10 days: anonymous sign-in with a before-user-created hook that needs a valid invite code, the signed-in functions closed to guests, failed-code limits per network, linking to Apple/Google/email, the paste card (a native Paste control), the wait. No captcha (JH-Q10).', 'Etwa 10 Tage: anonyme Anmeldung mit einem Hook before-user-created, der einen gültigen Einladungscode verlangt, die Funktionen für Angemeldete für Gäste geschlossen, Grenzen für Fehlversuche je Netz, Verknüpfung mit Apple/Google/E-Mail, die Einsetzen-Karte (ein nativer Knopf), das Warten. Kein Captcha (JH-Q10).'),
  service: en('Supabase anonymous sign-ins (our stack).', 'Anonyme Supabase-Anmeldung (unser Stack).'),
  risks: en('A guest who never saves loses access with the phone. Guests need the three measures in JH-Q10 (code check at sign-up, signed-in functions closed, per-network limits). Account deletion and export must cover guests. Not verified: that the before-user-created hook runs for anonymous sign-ins on our plan.', 'Wer nie sichert, verliert den Zugang mit dem Handy. Gäste brauchen die drei Maßnahmen aus JH-Q10 (Code-Prüfung bei der Anmeldung, Funktionen für Angemeldete geschlossen, Grenzen je Netz). Kontolöschung und Export müssen Gäste abdecken. Nicht geprüft: dass der Hook before-user-created auf unserem Tarif auch bei anonymer Anmeldung läuft.'),
};
