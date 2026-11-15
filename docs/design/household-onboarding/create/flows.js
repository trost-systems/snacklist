// Round CH: a new user creates their own household. Today (main's guided start) plus five flows.
// paths(scenario) -> { list, share }: from the start screen to the first list, and to an invite shared
// by the scenario's channel (share sheet, QR shown, code copied). Same data shape as join/flows.js.
import { T } from '../model.js';
import * as u from '../ui.js';

const { btn, act, ic, M } = u;
const en = (en, de) => ({ en, de });
const st = (s, via = 'tap', by, n, label) => ({ s, via, ...(by ? { by } : {}), ...(n ? { n } : {}), ...(label ? { label } : {}) });
const auto = (s, label) => st(s, 'auto', undefined, undefined, label);
const setupDone = en('The household is set up', 'Der Haushalt ist eingerichtet');

// The guided start's step frame (app/lib/onboarding/onboarding_frame.dart): "Step N of M", back, X, progress bar.
const stepFrame = (c, { n, of = 7, back = true, close = true, body }) =>
  `${u.statusBar()}${u.appBar(c, { title: c.T.onboardingProgress(n, of), back, close })}<div class="scroll"><div class="pg">${u.progress(n, of)}${body}</div></div>`;
const nextSkip = (c, { next = c.T.onboardingNext, skip = true } = {}) =>
  `<div class="stack">${btn(c, next, { kind: 'primary' })}${skip ? btn(c, c.T.onboardingSkip, { by: 'skip' }) : ''}</div>`;
const chips = (c, items, { on = [], by } = {}) =>
  `<div class="chips flat">${items.map((t, i) => `<button class="chip ${on.includes(i) ? 'on' : ''}" ${by && i === 1 ? act(c, by) : ''}><span>${t}</span></button>`).join('')}</div>`;

const whoBody = (c, o = {}) => `<h1 class="h">${c.T.whoTitle}</h1><p class="body muted">${c.T.whoBody}</p>${chips(c, c.T.kinds, { on: o.on ?? [], by: o.chipBy })}${o.extra ?? ''}`;
const nameBody = (c) => `<h1 class="h">${c.T.nameTitle}</h1><p class="body muted">${c.T.nameBody}</p><div class="lfield"><label>${c.T.householdName}</label><div class="hexfield"><span>${M(c).ownName}</span></div></div>`;
const storesBody = (c) => `<h1 class="h">${c.T.storesStepTitle}</h1><p class="body muted">${c.T.onboardingStoresHint}</p>${chips(c, c.T.stores)}${btn(c, c.T.storeAddOwn, { kind: 'text', icon: 'add' })}`;
const needBody = (c) => `<h1 class="h">${c.T.needTitle}</h1><p class="body muted">${c.T.needBody}</p>${chips(c, c.T.staples)}<div class="lfield"><label>${c.T.needFieldLabel}</label><div class="hexfield"><span class="muted">${c.T.needFieldHint}</span></div></div>`;
const accountBody = (c) => `<h1 class="h">${c.T.accountStepTitle}</h1><p class="body muted">${c.T.accountStepBody}</p>${u.providerButtons(c)}${u.legalFooter(c)}`;

const own = (c) => M(c).ownName;
const listOwn = (c, o = {}) => u.listScreen(c, { household: own(c), items: o.items ?? 'none', top: o.top, overlay: o.overlay, headerExtra: o.headerExtra });
const switcher = (c, under) => u.switcherSheet(c, under);
const invitePage = (c, under, group) => u.invitePage(c, under, { group });
const shareSheet = (c, under) => u.shareSheet(c, under);
const compose = (c) => u.chat(c, { text: c.T.shareOther(u.LINK, u.CODE), mine: true, compose: true });
const sent = (c) => u.chat(c, { text: c.T.shareOther(u.LINK, u.CODE), mine: true, sent: true });
const copied = (c, under) => `${under}${u.snack(c.T.codeCopied)}`;
const consentCard = (c) => u.consentCard(c);

// Today's invite step (app/lib/onboarding/invite_step.dart).
const inviteStep = (c, { card } = {}) =>
  stepFrame(c, {
    n: 7, back: false, close: false,
    body: `<h1 class="h">${c.T.inviteStepOther}</h1><div class="center">${ic('person_add_outlined', 'xl brandc')}</div><p class="body center-t">${c.T.inviteStepBody}</p><p class="hint center-t">${c.T.inviteJoinPageHint}</p>
    ${card ? u.inviteCard(c, { revoke: false }) : ''}<div class="stack">${card ? btn(c, c.T.inviteAnother, { icon: 'add' }) : btn(c, c.T.inviteStepOther, { kind: 'primary', icon: 'person_add_outlined', by: 'invite-first' })}${btn(c, card ? c.T.toTheList : c.T.later, { kind: 'text', by: 'later' })}</div>`,
  });
const setup = (c) => `${u.statusBar()}${u.appBar(c, { title: 'Snacklist', close: true })}<div class="scroll"><div class="pg"><h1 class="h">${c.T.setupBusy}</h1><div class="center"><span class="spinner"></span></div></div></div>`;
const apple = (c, under) => u.appleSheet(c, under, { owner: true });
const startToday = (c) => u.startScreen(c);
const startNoPaste = (c, o = {}) => u.startScreen(c, { paste: false, ...o });

const shareMeta = {
  'share-sheet': { step: 'invite', cap: en('The share sheet opens at once.', 'Das Teilen-Blatt öffnet sich sofort.') },
  compose: { step: 'invite', cap: en('WhatsApp with the invite text filled in: link and code.', 'WhatsApp mit dem Einladungstext: Link und Code.') },
  sent: { step: 'shared', cap: en('Sent by Mia herself. Snacklist sends nothing.', 'Von Mia selbst gesendet. Snacklist sendet nichts.') },
  copied: { step: 'shared', cap: en('Code copied: Mia can paste it anywhere or read it out.', 'Code kopiert: Mia kann ihn überall einfügen oder vorlesen.') },
};
const meta = (o) => ({ ...shareMeta, ...o });

// The three ways to share from a screen whose Share opens the share sheet (`from`) and that shows a code to copy.
const shareTail = (sc, { sheetBy = 'share', codeFrom = 'card', qr }) => {
  if (sc.share === 'link') return [st('share-sheet', 'tap', sheetBy), st('compose', 'tap', 'whatsapp'), st('sent', 'tap', 'send')];
  if (sc.share === 'qr') return qr;
  return codeFrom === 'sheet'
    ? [st('share-sheet', 'tap', sheetBy), st('card', 'tap', 'close'), st('copied', 'tap', 'copy-code')]
    : [st('copied', 'tap', 'copy-code')];
};

// ---- Today ----------------------------------------------------------------------------------------------
const today = {
  id: 'today',
  name: en('Today (main): the guided start', 'Heute (main): der geführte Start'),
  line: en(
    'Get started, then seven steps: usage data, who, name, stores, what’s missing, the account, and the invite step. The list comes after the invite step; later invites come from the switcher sheet’s invite page (job 242).',
    'Los geht’s, dann sieben Schritte: Nutzungsdaten, mit wem, Name, Läden, was fehlt, das Konto und der Einladungsschritt. Die Liste kommt nach dem Einladungsschritt; spätere Einladungen kommen von der Einladungsseite im Umschalter-Blatt (Job 242).',
  ),
  service: null,
  pasteGone: false,
  screens: {
    start: startToday,
    usage: (c) => stepFrame(c, { n: 1, back: false, body: u.consentBody(c) }),
    who: (c) => stepFrame(c, { n: 2, back: false, body: `${whoBody(c)}${nextSkip(c)}` }),
    name: (c) => stepFrame(c, { n: 3, body: `${nameBody(c)}${nextSkip(c, { skip: false })}` }),
    stores: (c) => stepFrame(c, { n: 4, body: `${storesBody(c)}${nextSkip(c)}` }),
    need: (c) => stepFrame(c, { n: 5, body: `${needBody(c)}${nextSkip(c, { next: c.T.needNext(0), skip: false })}` }),
    account: (c) => stepFrame(c, { n: 6, body: accountBody(c) }),
    apple: (c) => apple(c, stepFrame(c, { n: 6, body: accountBody(c) })),
    setup,
    invite: (c) => inviteStep(c),
    'share-sheet': (c) => shareSheet(c, inviteStep(c)),
    card: (c) => inviteStep(c, { card: true }),
    copied: (c) => copied(c, inviteStep(c, { card: true })),
    compose, sent,
    list: (c) => listOwn(c),
    switcher: (c) => switcher(c, listOwn(c)),
    'invite-page': (c) => invitePage(c, listOwn(c)),
    'invite-qr': (c) => invitePage(c, listOwn(c), 'qr'),
  },
  meta: meta({
    start: { step: 'start', cap: en('The start screen, “Paste invite” under “Sign in”.', 'Der Startbildschirm, „Einladung einfügen“ unter „Anmelden“.') },
    usage: { step: ['setup', 'consent'], cap: en('Step 1 of 7: usage data (only if this install has not answered).', 'Schritt 1 von 7: Nutzungsdaten (nur wenn diese Installation noch nicht geantwortet hat).') },
    who: { step: 'setup', cap: en('Step 2: who do you shop with?', 'Schritt 2: Mit wem kaufst du ein?') },
    name: { step: 'setup', cap: en('Step 3: the household’s name, filled in.', 'Schritt 3: der Name des Haushalts, vorausgefüllt.') },
    stores: { step: 'setup', cap: en('Step 4: stores.', 'Schritt 4: Läden.') },
    need: { step: 'setup', cap: en('Step 5: what do you need right now?', 'Schritt 5: Was fehlt gerade?') },
    account: { step: 'account', cap: en('Step 6: the account.', 'Schritt 6: das Konto.') },
    apple: { step: 'account', scr: 'account', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    setup: { step: 'setup', cap: en('“Setting up your household…”', '„Wir richten euren Haushalt ein …“') },
    invite: { step: 'invite', cap: en('Step 7: “Invite someone”, before the list.', 'Schritt 7: „Jemanden einladen“, vor der Liste.') },
    card: { step: 'invite', scr: 'invite', cap: en('The invite card with its code.', 'Die Einladungskarte mit Code.') },
    list: { step: 'list', cap: en('The list (empty on the shortest path).', 'Die Liste (auf dem kürzesten Weg leer).') },
    switcher: { step: 'invite', cap: en('Later: the switcher sheet’s household page, “Invite”.', 'Später: die Haushaltsseite im Umschalter-Blatt, „Einladen“.') },
    'invite-page': { step: 'invite', cap: en('The invite page inside the sheet (job 242). The QR needs a group link.', 'Die Einladungsseite im Blatt (Job 242). Der QR braucht einen Gruppenlink.') },
    'invite-qr': { step: 'shared', cap: en('Group link created: the QR to show.', 'Gruppenlink erstellt: der QR zum Zeigen.') },
  }),
  paths: (sc) => {
    const toInvite = [st('start', 'start'), st('usage', 'tap', 'go'), st('who', 'tap', 'decline'), st('name', 'tap', 'skip'), st('stores'), st('need', 'tap', 'skip'), st('account'), st('apple', 'tap', 'apple'), st('setup'), auto('invite', setupDone)];
    const list = [...toInvite, st('list', 'tap', 'later')];
    const qr = [st('list', 'tap', 'later'), st('switcher', 'tap', 'switcher'), st('invite-page', 'tap', 'invite'), st('invite-qr', 'tap', 'group')];
    return { list, share: [...toInvite, ...shareTail(sc, { sheetBy: 'invite-first', codeFrom: 'sheet', qr })] };
  },
};

// ---- CH1: today's start, three steps shorter -------------------------------------------------------------
const ch1Invite = (c, o = {}) =>
  stepFrame(c, {
    n: 4, of: 4, back: false, close: false,
    body: `<h1 class="h">${c.T.inviteStepOther}</h1><p class="body">${c.T.inviteStepBody}</p><p class="hint">${c.T.inviteJoinPageHint}</p>${u.inviteCard(c, { revoke: false })}${o.qr ? '' : `<div class="stack">${btn(c, c.lang === 'de' ? 'QR-Code zeigen' : 'Show QR code', { icon: 'qr_code_2', by: 'show-qr' })}</div>`}${o.qr ? `<div class="sticker qr-card">${u.qr(220)}<p class="small muted center-t">${c.lang === 'de' ? 'Halte das Handy hoch: Die Kamera der anderen öffnet die Einladung.' : 'Hold up your phone: their camera opens the invite.'}</p></div>` : ''}${btn(c, c.T.later, { kind: 'text', by: 'later' })}`,
  });
const firstStepsOwn = (c) =>
  `<div class="sticker fs"><div class="fs-h">${ic('flag_outlined', 'sm brandc')}<b class="grow">${c.T.checklistTitle}</b><small class="muted">${c.T.checklistProgress(1, 4)}</small></div>
  <div class="fs-row done"><span class="phex xs">${ic('check', 'xs')}</span><span>${c.T.checklistStarted}</span></div>
  <div class="fs-row"><span class="phex xs"></span><span class="grow"><b>${c.lang === 'de' ? 'Läden wählen' : 'Pick your stores'}</b><small class="muted">${c.lang === 'de' ? 'Die Liste ordnet sich nach deinem Laden.' : 'The list sorts itself by your store.'}</small></span>${btn(c, c.lang === 'de' ? 'Wählen' : 'Pick', { wide: false })}</div>
  <div class="fs-row"><span class="phex xs"></span><span class="grow"><b>${c.lang === 'de' ? 'Erste Artikel' : 'First items'}</b><small class="muted">${c.lang === 'de' ? 'Tipp unten, was fehlt.' : 'Type below what you need.'}</small></span></div></div>`;
const ch1 = {
  id: 'CH1',
  name: en('Today, three steps shorter', 'Heute, drei Schritte kürzer'),
  line: en(
    'The same guided start with only who, name and the account; stores and first items move to First steps on the list, usage data to a card there. The invite step stays before the list and already shows the code, Share and “Show QR code”.',
    'Derselbe geführte Start mit nur „mit wem“, Name und Konto; Läden und erste Artikel wandern in Erste Schritte auf der Liste, Nutzungsdaten in eine Karte dort. Der Einladungsschritt bleibt vor der Liste und zeigt schon Code, Teilen und „QR-Code zeigen“.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    start: (c) => startNoPaste(c, { extra: btn(c, c.lang === 'de' ? 'Ich habe eine Einladung' : 'I have an invite', { kind: 'text', icon: 'key_outlined' }) }),
    who: (c) => stepFrame(c, { n: 1, of: 4, back: false, body: `${whoBody(c)}${nextSkip(c)}` }),
    name: (c) => stepFrame(c, { n: 2, of: 4, body: `${nameBody(c)}${nextSkip(c, { skip: false })}` }),
    account: (c) => stepFrame(c, { n: 3, of: 4, body: accountBody(c) }),
    apple: (c) => apple(c, stepFrame(c, { n: 3, of: 4, body: accountBody(c) })),
    setup,
    invite: (c) => ch1Invite(c),
    'invite-qr': (c) => ch1Invite(c, { qr: true }),
    'share-sheet': (c) => shareSheet(c, ch1Invite(c)),
    copied: (c) => copied(c, ch1Invite(c)),
    compose, sent,
    list: (c) => listOwn(c, { top: `${firstStepsOwn(c)}${consentCard(c)}` }),
  },
  meta: meta({
    start: { step: 'start', cap: en('Start: “Get started”, “Sign in”, and “I have an invite” in place of “Paste invite”.', 'Start: „Los geht’s“, „Anmelden“ und „Ich habe eine Einladung“ statt „Einladung einfügen“.') },
    who: { step: 'setup', cap: en('Step 1 of 4: who do you shop with? (No usage question first.)', 'Schritt 1 von 4: Mit wem kaufst du ein? (Keine Nutzungsfrage davor.)') },
    name: { step: 'setup', cap: en('Step 2: the name, filled in.', 'Schritt 2: der Name, vorausgefüllt.') },
    account: { step: 'account', cap: en('Step 3: the account.', 'Schritt 3: das Konto.') },
    apple: { step: 'account', scr: 'account', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    setup: { step: 'setup', cap: en('Setting up.', 'Einrichten.') },
    invite: { step: 'invite', cap: en('Step 4: the invite is already made: code, link, Share, “Show QR code”.', 'Schritt 4: Die Einladung ist schon da: Code, Link, Teilen, „QR-Code zeigen“.') },
    'invite-qr': { step: 'shared', cap: en('The QR, big enough for a camera across the table.', 'Der QR, groß genug für eine Kamera über den Tisch.') },
    list: { step: ['list', 'consent'], cap: en('The list: First steps (stores, first items) and usage data as a card.', 'Die Liste: Erste Schritte (Läden, erste Artikel) und Nutzungsdaten als Karte.') },
  }),
  paths: (sc) => {
    const toInvite = [st('start', 'start'), st('who', 'tap', 'go'), st('name', 'tap', 'skip'), st('account'), st('apple', 'tap', 'apple'), st('setup'), auto('invite', setupDone)];
    return { list: [...toInvite, st('list', 'tap', 'later')], share: [...toInvite, ...shareTail(sc, { qr: [st('invite-qr', 'tap', 'show-qr')] })] };
  },
};

// ---- CH2: the account, then the list ---------------------------------------------------------------------
const ch2Account = (c) =>
  `${u.statusBar()}${u.appBar(c, { back: true })}<div class="scroll"><div class="pg"><h1 class="h">${c.T.accountStepTitle}</h1><p class="body muted">${c.lang === 'de' ? 'Danach ist deine Liste sofort da. Name, Läden und Einladung kannst du dort anpassen.' : 'Your list is ready right after. Name, stores and invites are on the list.'}</p>${u.providerButtons(c)}${u.legalFooter(c)}</div></div>`;
const ch2List = (c) => listOwn(c, { top: `${u.firstSteps(c, { invite: true })}${consentCard(c)}` });
const ch2 = {
  id: 'CH2',
  name: en('The account, then the list', 'Das Konto, dann die Liste'),
  line: en(
    'No questions: “Get started” asks for the account and opens the list, named “Our household”. First steps on the list carry “Invite your family” (opening the invite page in the switcher sheet), stores and the name; usage data is a card.',
    'Keine Fragen: „Los geht’s“ fragt nach dem Konto und öffnet die Liste, „Unser Haushalt“ genannt. Erste Schritte auf der Liste tragen „Familie einladen“ (öffnet die Einladungsseite im Umschalter-Blatt), Läden und den Namen; Nutzungsdaten sind eine Karte.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    start: (c) => startNoPaste(c, { extra: btn(c, c.lang === 'de' ? 'Ich habe eine Einladung' : 'I have an invite', { kind: 'text', icon: 'key_outlined' }) }),
    account: ch2Account,
    apple: (c) => apple(c, ch2Account(c)),
    setup,
    list: ch2List,
    'invite-page': (c) => invitePage(c, ch2List(c)),
    'invite-qr': (c) => invitePage(c, ch2List(c), 'qr'),
    'share-sheet': (c) => shareSheet(c, invitePage(c, ch2List(c), 'card')),
    card: (c) => invitePage(c, ch2List(c), 'card'),
    copied: (c) => copied(c, invitePage(c, ch2List(c), 'card')),
    compose, sent,
  },
  meta: meta({
    start: { step: 'start', cap: en('Start, with “I have an invite”.', 'Start, mit „Ich habe eine Einladung“.') },
    account: { step: 'account', cap: en('The account first: “Your list is ready right after.”', 'Zuerst das Konto: „Danach ist deine Liste sofort da.“') },
    apple: { step: 'account', scr: 'account', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    setup: { step: 'setup', cap: en('Setting up “Our household”.', '„Unser Haushalt“ wird eingerichtet.') },
    list: { step: ['list', 'consent'], cap: en('The list with First steps: “Invite your family” first. Usage data as a card.', 'Die Liste mit Erste Schritte: zuerst „Familie einladen“. Nutzungsdaten als Karte.') },
    'invite-page': { step: 'invite', cap: en('The invite page in the switcher sheet (job 242).', 'Die Einladungsseite im Umschalter-Blatt (Job 242).') },
    'invite-qr': { step: 'shared', cap: en('Group link: the QR to show.', 'Gruppenlink: der QR zum Zeigen.') },
    card: { step: 'invite', scr: 'invite-page', cap: en('The new invite’s card.', 'Die Karte der neuen Einladung.') },
  }),
  paths: (sc) => {
    const list = [st('start', 'start'), st('account', 'tap', 'go'), st('apple', 'tap', 'apple'), st('setup'), auto('list', setupDone)];
    const page = [st('invite-page', 'tap', 'fs-invite')];
    return { list, share: [...list, ...page, ...shareTail(sc, { sheetBy: 'new-invite', codeFrom: 'sheet', qr: [st('invite-qr', 'tap', 'group')] })] };
  },
};

// ---- CH3: the list first, the account when sharing -------------------------------------------------------
const ch3List = (c, o = {}) =>
  listOwn(c, {
    top: `<div class="sticker welcome-card"><b>${c.lang === 'de' ? 'Deine Liste ist da' : 'Your list is ready'}</b><p class="small muted">${c.lang === 'de' ? 'Sie liegt auf diesem Handy. Zum Teilen legst du ein Konto an.' : 'It lives on this phone. To share it, create an account.'}</p></div>${consentCard(c)}`,
    headerExtra: btn(c, c.T.switcherInvite, { icon: 'person_add_outlined', by: 'hdr-invite', wide: false }),
    ...o,
  });
const ch3Acct = (c) => u.accountSheet(c, ch3List(c), { title: c.lang === 'de' ? 'Zum Teilen ein Konto anlegen' : 'Create an account to share', sub: c.lang === 'de' ? 'Deine Liste kommt mit. Danach öffnet sich die Einladung.' : 'Your list comes along. The invite opens right after.' });
const ch3 = {
  id: 'CH3',
  name: en('The list first, the account when you share', 'Erst die Liste, das Konto beim Teilen'),
  line: en(
    '“Start a list” opens the list at once, on a guest account (Supabase anonymous sign-in). The list has “Invite” in the header; the account (Apple, Google, email) is asked only then, and the invite page follows. Usage data is a card.',
    '„Liste starten“ öffnet die Liste sofort, auf einem Gastkonto (anonyme Supabase-Anmeldung). Die Liste hat „Einladen“ oben; das Konto (Apple, Google, E-Mail) wird erst dann gefragt, danach folgt die Einladungsseite. Nutzungsdaten sind eine Karte.',
  ),
  service: en('Supabase anonymous sign-ins (our stack)', 'Anonyme Supabase-Anmeldung (unser Stack)'),
  pasteGone: true,
  screens: {
    start: (c) => startNoPaste(c, { buttons: `${btn(c, c.lang === 'de' ? 'Liste starten' : 'Start a list', { kind: 'primary', by: 'go' })}${btn(c, c.lang === 'de' ? 'Einem Haushalt beitreten' : 'Join a household', { icon: 'group_add_outlined' })}${btn(c, c.T.startLogIn, { kind: 'text' })}` }),
    list: (c) => ch3List(c),
    acct: ch3Acct,
    apple: (c) => apple(c, ch3Acct(c)),
    'invite-page': (c) => invitePage(c, ch3List(c)),
    'invite-qr': (c) => invitePage(c, ch3List(c), 'qr'),
    'share-sheet': (c) => shareSheet(c, invitePage(c, ch3List(c), 'card')),
    card: (c) => invitePage(c, ch3List(c), 'card'),
    copied: (c) => copied(c, invitePage(c, ch3List(c), 'card')),
    compose, sent,
  },
  meta: meta({
    start: { step: 'start', cap: en('Start: “Start a list” and “Join a household”.', 'Start: „Liste starten“ und „Einem Haushalt beitreten“.') },
    list: { step: ['list', 'consent'], cap: en('The list, at once, on a guest account. “Invite” sits in the header.', 'Die Liste, sofort, auf einem Gastkonto. „Einladen“ sitzt oben.') },
    acct: { step: 'account', cap: en('“Create an account to share”: only now.', '„Zum Teilen ein Konto anlegen“: erst jetzt.') },
    apple: { step: 'account', scr: 'acct', cap: en('Sign in with Apple; the guest list moves to the account.', 'Mit Apple anmelden; die Gastliste wandert ins Konto.') },
    'invite-page': { step: 'invite', cap: en('The invite page opens by itself.', 'Die Einladungsseite öffnet sich von selbst.') },
    'invite-qr': { step: 'shared', cap: en('Group link: the QR to show.', 'Gruppenlink: der QR zum Zeigen.') },
    card: { step: 'invite', scr: 'invite-page', cap: en('The new invite’s card.', 'Die Karte der neuen Einladung.') },
  }),
  paths: (sc) => {
    const list = [st('start', 'start'), st('list', 'tap', 'go')];
    const acct = [st('acct', 'tap', 'hdr-invite'), st('apple', 'tap', 'apple'), st('invite-page')];
    return { list, share: [...list, ...acct, ...shareTail(sc, { sheetBy: 'new-invite', codeFrom: 'sheet', qr: [st('invite-qr', 'tap', 'group')] })] };
  },
};

// ---- CH4: invite before the list, in person or by link ---------------------------------------------------
const ch4Invite = (c, o = {}) =>
  `${u.statusBar()}${u.appBar(c, { title: c.T.inviteStepFamily })}<div class="scroll"><div class="pg"><p class="body">${c.lang === 'de' ? 'Sitzt deine Familie neben dir? Lass sie den Code scannen. Sonst teil den Link.' : 'Family next to you? Let them scan the code. Otherwise share the link.'}</p>
  <div class="sticker qr-card">${u.qr(o.big ? 260 : 180)}<b class="code">${u.codeDash}</b></div><p class="hint">${c.T.inviteJoinPageHint}</p>
  <div class="stack">${btn(c, c.T.share, { kind: 'primary', icon: 'ios_share', by: 'share' })}${btn(c, c.T.copyCode, { icon: 'content_copy', by: 'copy-code' })}${o.big ? '' : btn(c, c.lang === 'de' ? 'QR größer zeigen' : 'Show QR bigger', { icon: 'qr_code_2', by: 'show-qr' })}${btn(c, c.T.later, { kind: 'text', by: 'later' })}</div></div></div>`;
const ch4 = {
  id: 'CH4',
  name: en('Invite first, by QR or link', 'Zuerst einladen, per QR oder Link'),
  line: en(
    'Two steps: who (Family, Partner, Flatmates…) and the account. Then a full invite screen with the QR code shown big, Share and Copy code, before the list. “Just me” skips it. The name comes from the pick; stores and items wait on the list.',
    'Zwei Schritte: mit wem (Familie, Partner·in, WG …) und das Konto. Dann ein ganzer Einladungsbildschirm mit großem QR-Code, Teilen und Code kopieren, vor der Liste. „Nur ich“ überspringt ihn. Der Name kommt aus der Wahl; Läden und Artikel warten auf der Liste.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    start: (c) => startNoPaste(c, { extra: btn(c, c.lang === 'de' ? 'Ich habe eine Einladung' : 'I have an invite', { kind: 'text', icon: 'key_outlined' }) }),
    who: (c) => stepFrame(c, { n: 1, of: 3, back: false, body: `${whoBody(c, { chipBy: 'chip' })}${nextSkip(c, { skip: false })}` }),
    'who-picked': (c) => stepFrame(c, { n: 1, of: 3, back: false, body: `${whoBody(c, { on: [1] })}${nextSkip(c, { skip: false })}` }),
    account: (c) => stepFrame(c, { n: 2, of: 3, body: accountBody(c) }),
    apple: (c) => apple(c, stepFrame(c, { n: 2, of: 3, body: accountBody(c) })),
    setup,
    invite: (c) => ch4Invite(c),
    'invite-qr': (c) => ch4Invite(c, { big: true }),
    'share-sheet': (c) => shareSheet(c, ch4Invite(c)),
    copied: (c) => copied(c, ch4Invite(c)),
    compose, sent,
    list: (c) => listOwn(c, { top: `${firstStepsOwn(c)}${consentCard(c)}` }),
  },
  meta: meta({
    start: { step: 'start', cap: en('Start, with “I have an invite”.', 'Start, mit „Ich habe eine Einladung“.') },
    who: { step: 'setup', cap: en('Step 1 of 3: who do you shop with? A pick is needed (it names the household and the invite).', 'Schritt 1 von 3: Mit wem kaufst du ein? Eine Wahl ist nötig (sie benennt Haushalt und Einladung).') },
    'who-picked': { step: 'setup', scr: 'who', cap: en('Family picked.', 'Familie gewählt.') },
    account: { step: 'account', cap: en('Step 2: the account.', 'Schritt 2: das Konto.') },
    apple: { step: 'account', scr: 'account', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    setup: { step: 'setup', cap: en('Setting up “Our family”.', '„Unsere Familie“ wird eingerichtet.') },
    invite: { step: 'invite', cap: en('Step 3: the QR is on screen at once, with Share and Copy code.', 'Schritt 3: Der QR ist sofort zu sehen, mit Teilen und Code kopieren.') },
    'invite-qr': { step: 'shared', cap: en('The QR, big, for a camera across the table.', 'Der QR, groß, für eine Kamera über den Tisch.') },
    list: { step: ['list', 'consent'], cap: en('The list: First steps and usage data as a card.', 'Die Liste: Erste Schritte und Nutzungsdaten als Karte.') },
  }),
  paths: (sc) => {
    const toInvite = [st('start', 'start'), st('who', 'tap', 'go'), st('who-picked', 'tap', 'chip'), st('account'), st('apple', 'tap', 'apple'), st('setup'), auto('invite', setupDone)];
    return { list: [...toInvite, st('list', 'tap', 'later')], share: [...toInvite, ...shareTail(sc, { qr: [st('invite-qr', 'tap', 'show-qr')] })] };
  },
};

// ---- CH5: today's steps, a door for the invited, stores and items on one screen ----------------------------
const ch5Who = (c) =>
  whoBody(c, { extra: `<p class="small muted">${c.lang === 'de' ? 'Nutzt jemand von euch Snacklist schon?' : 'Someone you shop with already uses Snacklist?'} <a>${c.lang === 'de' ? 'Seinem Haushalt beitreten' : 'Join their household'}</a></p>` });
const ch5Shop = (c) =>
  `<h1 class="h">${c.lang === 'de' ? 'Wo kauft ihr ein, und was fehlt?' : 'Where do you shop, and what’s missing?'}</h1>${chips(c, c.T.stores.slice(0, 6))}<p class="lab" style="padding:0">${c.T.needTitle}</p>${chips(c, c.T.staples.slice(0, 8))}`;
const ch5 = {
  id: 'CH5',
  name: en('Today’s steps with two doors', 'Die heutigen Schritte mit zwei Türen'),
  line: en(
    'The start screen gets two equal doors, “Start my own list” and “Join a household” (the JH3 door), so a referred user never starts a household by mistake. Today’s guided start follows without the usage step (a card on the list) and with stores and items on one screen. The invite step stays.',
    'Der Startbildschirm bekommt zwei gleichwertige Türen, „Eigene Liste anlegen“ und „Einem Haushalt beitreten“ (die Tür aus JH3), damit niemand aus Versehen einen Haushalt anlegt. Der heutige geführte Start folgt ohne Nutzungsschritt (eine Karte auf der Liste) und mit Läden und Artikeln auf einem Bildschirm. Der Einladungsschritt bleibt.',
  ),
  service: null,
  pasteGone: true,
  screens: {
    start: (c) => startNoPaste(c, { buttons: `${btn(c, c.lang === 'de' ? 'Eigene Liste anlegen' : 'Start my own list', { kind: 'primary', by: 'go' })}${btn(c, c.lang === 'de' ? 'Einem Haushalt beitreten' : 'Join a household', { icon: 'group_add_outlined' })}${btn(c, c.T.startLogIn, { kind: 'text' })}` }),
    who: (c) => stepFrame(c, { n: 1, of: 5, back: false, body: `${ch5Who(c)}${nextSkip(c)}` }),
    name: (c) => stepFrame(c, { n: 2, of: 5, body: `${nameBody(c)}${nextSkip(c, { skip: false })}` }),
    shop: (c) => stepFrame(c, { n: 3, of: 5, body: `${ch5Shop(c)}${nextSkip(c)}` }),
    account: (c) => stepFrame(c, { n: 4, of: 5, body: accountBody(c) }),
    apple: (c) => apple(c, stepFrame(c, { n: 4, of: 5, body: accountBody(c) })),
    setup,
    invite: (c) => inviteStep(c).replace(c.T.onboardingProgress(7, 7), c.T.onboardingProgress(5, 5)),
    'share-sheet': (c) => shareSheet(c, inviteStep(c)),
    card: (c) => inviteStep(c, { card: true }),
    copied: (c) => copied(c, inviteStep(c, { card: true })),
    compose, sent,
    list: (c) => listOwn(c, { top: consentCard(c) }),
    switcher: (c) => switcher(c, listOwn(c, { top: consentCard(c) })),
    'invite-page': (c) => invitePage(c, listOwn(c, { top: consentCard(c) })),
    'invite-qr': (c) => invitePage(c, listOwn(c, { top: consentCard(c) }), 'qr'),
  },
  meta: meta({
    start: { step: 'start', cap: en('Two doors: “Start my own list” and “Join a household”.', 'Zwei Türen: „Eigene Liste anlegen“ und „Einem Haushalt beitreten“.') },
    who: { step: 'setup', cap: en('Step 1 of 5: who, with “Join their household” under the chips.', 'Schritt 1 von 5: mit wem, darunter „Seinem Haushalt beitreten“.') },
    name: { step: 'setup', cap: en('Step 2: the name.', 'Schritt 2: der Name.') },
    shop: { step: 'setup', cap: en('Step 3: stores and what’s missing, on one screen.', 'Schritt 3: Läden und was fehlt, auf einem Bildschirm.') },
    account: { step: 'account', cap: en('Step 4: the account.', 'Schritt 4: das Konto.') },
    apple: { step: 'account', scr: 'account', cap: en('Sign in with Apple.', 'Mit Apple anmelden.') },
    setup: { step: 'setup', cap: en('Setting up.', 'Einrichten.') },
    invite: { step: 'invite', cap: en('Step 5: today’s invite step.', 'Schritt 5: der heutige Einladungsschritt.') },
    card: { step: 'invite', scr: 'invite', cap: en('The invite card.', 'Die Einladungskarte.') },
    list: { step: ['list', 'consent'], cap: en('The list, usage data as a card.', 'Die Liste, Nutzungsdaten als Karte.') },
    switcher: { step: 'invite', cap: en('Later: the switcher sheet.', 'Später: das Umschalter-Blatt.') },
    'invite-page': { step: 'invite', cap: en('The invite page (job 242).', 'Die Einladungsseite (Job 242).') },
    'invite-qr': { step: 'shared', cap: en('Group link: the QR.', 'Gruppenlink: der QR.') },
  }),
  paths: (sc) => {
    const toInvite = [st('start', 'start'), st('who', 'tap', 'go'), st('name', 'tap', 'skip'), st('shop'), st('account', 'tap', 'skip'), st('apple', 'tap', 'apple'), st('setup'), auto('invite', setupDone)];
    const qr = [st('list', 'tap', 'later'), st('switcher', 'tap', 'switcher'), st('invite-page', 'tap', 'invite'), st('invite-qr', 'tap', 'group')];
    return { list: [...toInvite, st('list', 'tap', 'later')], share: [...toInvite, ...shareTail(sc, { sheetBy: 'invite-first', codeFrom: 'sheet', qr })] };
  },
};

today.facts = {
  questions: en('5 (usage, who, name, stores, need)', '5 (Nutzung, mit wem, Name, Läden, was fehlt)'),
  inviteWhere: en('invite step before the list; later the switcher sheet’s invite page', 'Einladungsschritt vor der Liste; später die Einladungsseite im Umschalter-Blatt'),
  qr: en('group link only, from the switcher', 'nur Gruppenlink, über den Umschalter'),
  consent: en('step 1, before the account', 'Schritt 1, vor dem Konto'),
  guard: en('“Paste invite” under “Sign in”', '„Einladung einfügen“ unter „Anmelden“'),
  build: en('0 (live)', '0 (live)'),
  service: en('none', 'keiner'),
};
ch1.facts = {
  questions: en('2 (who, name)', '2 (mit wem, Name)'),
  inviteWhere: en('invite step before the list, invite made already', 'Einladungsschritt vor der Liste, Einladung schon erstellt'),
  qr: en('“Show QR code” on the invite step (person invite)', '„QR-Code zeigen“ im Einladungsschritt (Einladung für eine Person)'),
  consent: en('card on the list', 'Karte auf der Liste'),
  guard: en('“I have an invite” text button', 'Textknopf „Ich habe eine Einladung“'),
  build: en('3 days', '3 Tage'),
  service: en('none', 'keiner'),
};
ch2.facts = {
  questions: en('0', '0'),
  inviteWhere: en('First steps card on the list → switcher invite page', 'Erste-Schritte-Karte auf der Liste → Einladungsseite im Umschalter'),
  qr: en('group link on the invite page', 'Gruppenlink auf der Einladungsseite'),
  consent: en('card on the list', 'Karte auf der Liste'),
  guard: en('“I have an invite” text button', 'Textknopf „Ich habe eine Einladung“'),
  build: en('3 days', '3 Tage'),
  service: en('none', 'keiner'),
};
ch3.facts = {
  questions: en('0', '0'),
  inviteWhere: en('“Invite” in the list header → account → invite page', '„Einladen“ oben in der Liste → Konto → Einladungsseite'),
  qr: en('group link on the invite page', 'Gruppenlink auf der Einladungsseite'),
  consent: en('card on the list', 'Karte auf der Liste'),
  guard: en('“Join a household” door', 'Tür „Einem Haushalt beitreten“'),
  build: en('12 days (JH5’s guest accounts plus limits for guests without a code)', '12 Tage (Gastkonten aus JH5 plus Grenzen für Gäste ohne Code)'),
  service: en('Supabase anonymous sign-ins', 'Anonyme Supabase-Anmeldung'),
};
ch4.facts = {
  questions: en('1 (who, a pick needed)', '1 (mit wem, Wahl nötig)'),
  inviteWhere: en('full invite screen before the list, QR shown', 'ganzer Einladungsbildschirm vor der Liste, QR sichtbar'),
  qr: en('on screen at once (person invite)', 'sofort sichtbar (Einladung für eine Person)'),
  consent: en('card on the list', 'Karte auf der Liste'),
  guard: en('“I have an invite” text button', 'Textknopf „Ich habe eine Einladung“'),
  build: en('3 days', '3 Tage'),
  service: en('none', 'keiner'),
};
ch5.facts = {
  questions: en('3 (who, name, stores and items)', '3 (mit wem, Name, Läden und Artikel)'),
  inviteWhere: en('invite step before the list; later the switcher sheet', 'Einladungsschritt vor der Liste; später das Umschalter-Blatt'),
  qr: en('group link only, from the switcher', 'nur Gruppenlink, über den Umschalter'),
  consent: en('card on the list', 'Karte auf der Liste'),
  guard: en('two equal doors, and “Join their household” on step 1', 'zwei gleichwertige Türen und „Seinem Haushalt beitreten“ in Schritt 1'),
  build: en('3 days', '3 Tage'),
  service: en('none', 'keiner'),
};
const D = (o, d) => (o.detail = d);
D(today, {
  flow: en('Start → Get started → usage data → who → name → stores → need → account → setup → invite step → list.', 'Start → Los geht’s → Nutzungsdaten → mit wem → Name → Läden → was fehlt → Konto → Einrichtung → Einladungsschritt → Liste.'),
  invite: en('The invite step’s button makes an invite and opens the share sheet. Later: list header → switcher sheet → Invite → the invite page (person invites, group link with QR).', 'Der Knopf im Einladungsschritt erstellt eine Einladung und öffnet das Teilen-Blatt. Später: Kopf der Liste → Umschalter-Blatt → Einladen → Einladungsseite (Einladungen für eine Person, Gruppenlink mit QR).'),
  consent: en('Usage data is step 1, before anything else.', 'Nutzungsdaten sind Schritt 1, vor allem anderen.'),
  guard: en('“Paste invite” is the only sign for the invited, under “Sign in”.', '„Einladung einfügen“ ist der einzige Hinweis für Eingeladene, unter „Anmelden“.'),
  build: en('Live.', 'Live.'),
  risks: en('Five questions before the list; a referred user who taps “Get started” builds a second household.', 'Fünf Fragen vor der Liste; wer eingeladen ist und „Los geht’s“ tippt, baut einen zweiten Haushalt.'),
});
D(ch1, {
  flow: en('Start → who → name → account → setup → invite step (invite made) → list with First steps.', 'Start → mit wem → Name → Konto → Einrichtung → Einladungsschritt (Einladung erstellt) → Liste mit Erste Schritte.'),
  invite: en('The invite step shows the made invite: code, link, Share, Copy, “Show QR code”. Later: the switcher sheet as today.', 'Der Einladungsschritt zeigt die erstellte Einladung: Code, Link, Teilen, Kopieren, „QR-Code zeigen“. Später: das Umschalter-Blatt wie heute.'),
  consent: en('A card on the list with two equal buttons.', 'Eine Karte auf der Liste mit zwei gleichen Knöpfen.'),
  guard: en('“I have an invite” under “Sign in” (opens the JH code screen).', '„Ich habe eine Einladung“ unter „Anmelden“ (öffnet den Codeschirm aus JH).'),
  build: en('About 3 days: drop three steps, a made invite on the step, First steps rows.', 'Etwa 3 Tage: drei Schritte weg, eine erstellte Einladung im Schritt, Zeilen in Erste Schritte.'),
  risks: en('An invite is made even when Mia shares nothing (it expires in 7 days).', 'Eine Einladung entsteht, auch wenn Mia nichts teilt (sie läuft nach 7 Tagen ab).'),
});
D(ch2, {
  flow: en('Start → account → setup → list.', 'Start → Konto → Einrichtung → Liste.'),
  invite: en('First steps’ “Invite your family” opens the invite page in the switcher sheet; “New invite” opens the share sheet.', '„Familie einladen“ in Erste Schritte öffnet die Einladungsseite im Umschalter-Blatt; „Neue Einladung“ öffnet das Teilen-Blatt.'),
  consent: en('A card on the list.', 'Eine Karte auf der Liste.'),
  guard: en('“I have an invite” under “Sign in”.', '„Ich habe eine Einladung“ unter „Anmelden“.'),
  build: en('About 3 days.', 'Etwa 3 Tage.'),
  risks: en('No kind, so the invite text and tips are generic; the name is “Our household” until changed.', 'Keine Art, also sind Einladungstext und Tipps allgemein; der Name ist „Unser Haushalt“, bis er geändert wird.'),
});
D(ch3, {
  flow: en('Start → Start a list → the list (guest account).', 'Start → Liste starten → die Liste (Gastkonto).'),
  invite: en('“Invite” in the header asks for the account first, then opens the invite page.', '„Einladen“ oben fragt erst nach dem Konto und öffnet dann die Einladungsseite.'),
  consent: en('A card on the list.', 'Eine Karte auf der Liste.'),
  guard: en('“Join a household” door next to “Start a list”.', 'Tür „Einem Haushalt beitreten“ neben „Liste starten“.'),
  build: en('About 12 days: JH5’s guest accounts (10 days, JH-Q10), plus limits for guests that arrive without an invite code, which JH5’s sign-up check doesn’t cover (CH-Q6).', 'Etwa 12 Tage: die Gastkonten aus JH5 (10 Tage, JH-Q10), plus Grenzen für Gäste ohne Einladungscode, die die Prüfung bei der Anmeldung aus JH5 nicht abdeckt (CH-Q6).'),
  risks: en('A guest list is lost with the phone until an account exists; guests need deletion and export too.', 'Eine Gastliste geht mit dem Handy verloren, bis es ein Konto gibt; auch Gäste brauchen Löschung und Export.'),
});
D(ch4, {
  flow: en('Start → who (pick) → account → setup → invite screen with QR → list.', 'Start → mit wem (Wahl) → Konto → Einrichtung → Einladungsbildschirm mit QR → Liste.'),
  invite: en('A full invite screen with the QR, Share and Copy code; a person invite gets a QR too (today only group links).', 'Ein ganzer Einladungsbildschirm mit QR, Teilen und Code kopieren; auch eine Einladung für eine Person bekommt einen QR (heute nur Gruppenlinks).'),
  consent: en('A card on the list.', 'Eine Karte auf der Liste.'),
  guard: en('“I have an invite” under “Sign in”.', '„Ich habe eine Einladung“ unter „Anmelden“.'),
  build: en('About 3 days.', 'Etwa 3 Tage.'),
  risks: en('A QR for a one-person invite works once; a second scanner gets “used”.', 'Ein QR für eine Einladung für eine Person wirkt einmal; wer als Zweites scannt, bekommt „verbraucht“.'),
});
D(ch5, {
  flow: en('Start (two doors) → who → name → stores and items → account → setup → invite step → list.', 'Start (zwei Türen) → mit wem → Name → Läden und Artikel → Konto → Einrichtung → Einladungsschritt → Liste.'),
  invite: en('Today’s invite step and switcher sheet.', 'Der heutige Einladungsschritt und das Umschalter-Blatt.'),
  consent: en('A card on the list.', 'Eine Karte auf der Liste.'),
  guard: en('Two equal doors on start, and “Join their household” on step 1.', 'Zwei gleichwertige Türen am Start und „Seinem Haushalt beitreten“ in Schritt 1.'),
  build: en('About 3 days (the door is shared with JH3).', 'Etwa 3 Tage (die Tür teilt es mit JH3).'),
  risks: en('Still five screens of setup before the list.', 'Immer noch fünf Einrichtungsbildschirme vor der Liste.'),
});

export const round = {
  T,
  options: [today, ch1, ch2, ch3, ch4, ch5],
  scenarios: {
    share: { label: en('Invite by', 'Einladen per'), values: ['link', 'qr', 'code'], names: { link: en('Share link', 'Link teilen'), qr: en('Show QR', 'QR zeigen'), code: en('Copy code', 'Code kopieren') } },
  },
  goals: [
    { key: 'list', label: en('First list', 'Erste Liste') },
    { key: 'share', label: en('Invite shared', 'Einladung geteilt') },
  ],
  steps: {
    start: { n: 1, ...en('Start', 'Start') },
    setup: { n: 2, ...en('Setup', 'Einrichtung') },
    account: { n: 3, ...en('Account', 'Konto') },
    consent: { n: 4, ...en('Consent', 'Einwilligung') },
    list: { n: 5, ...en('First list', 'Erste Liste') },
    invite: { n: 6, ...en('Invite', 'Einladen') },
    shared: { n: 7, ...en('Shared', 'Geteilt') },
  },
  via: { tap: en('tap', 'Tipp'), auto: en('no tap', 'kein Tipp'), type: en('typing', 'Tippen von Text'), wait: en('waiting', 'warten'), scan: en('scan', 'scannen') },
  viaIcon: { auto: 'arrow_forward', type: 'keyboard', wait: 'hourglass_top_outlined', scan: 'qr_code_scanner', tap: 'touch_app' },
  facts: ['questions', 'inviteWhere', 'qr', 'consent', 'guard', 'build', 'service'],
  detail: ['flow', 'invite', 'consent', 'guard', 'build', 'risks'],
  detailNames: {
    flow: en('Path', 'Weg'), invite: en('Inviting afterwards', 'Später einladen'), consent: en('Consent and legal', 'Einwilligung und Rechtliches'),
    guard: en('For someone who was invited', 'Für Eingeladene'), build: en('Build effort (estimate)', 'Bauaufwand (Schätzung)'), risks: en('Risks', 'Risiken'),
  },
  rec: { pick: 'CH1', runnerUp: 'CH2', file: 'RECOMMENDATION' },
  page: {
    en: {
      title: 'Creating a household (CH1–CH5)', back: 'All prototype rounds', overview: 'Overview', rec: 'Recommendation', light: 'Light', dark: 'Dark', text: 'Text',
      compare: 'Five ways for a new user to create a household and invite someone, next to Today (main’s guided start and the job 242 invite page in the switcher sheet). Each goes from the start screen to the first list, and to an invite shared by link, QR or code. Mock data, measured on an iPhone with Sign in with Apple, taking Skip wherever a step offers it.',
      tap: 'tap', taps: 'taps', screens: 'screens', typed: 'plus typing', pick: 'Pick', runnerUp: 'Runner-up', stack: 'today’s stack, no new vendor', pasteGone: '“Paste invite” gone', pasteKept: '“Paste invite” kept',
      table: 'Comparison', allScen: 'link · QR · code',
      cols: ['Option', 'Taps / screens to the first list', 'Taps / screens to an invite shared', 'Questions before the list', 'Where the invite lives', 'QR', 'Consent', 'For someone invited', 'Build effort', 'Existing service'],
      tapsNote: 'Measured by walking each path from the start screen, taking Skip where a step has it and signing in with Apple. Bold: the channel picked above; small: the range over link, QR and code. A tap on a button, a chip or a system sheet counts 1; the system “Sign in with Apple” sheet is not counted as a screen. “Invite shared” ends when WhatsApp sends the link, the QR is on screen, or the code is copied. verify.mjs drives every path with real clicks and checks the numbers.',
      side: 'Side by side', sideNote: 'Every option’s path to an invite shared, for the channel picked above. Open an option for big phones and Try it.',
      factsTitle: 'The path, inviting, consent and effort', tryIt: 'Try it', reset: 'Start again', tapHint: 'Tap the outlined control in the phone.',
      soFar: (n) => `${n} ${n === 1 ? 'tap' : 'taps'} so far`, doneAfter: (n, s) => `Done: ${n} ${n === 1 ? 'tap' : 'taps'}, ${s} steps.`,
      goalNow: (g, t, s) => `${g}: ${t} taps, ${s} screens on this path.`,
      partTitle: (g, n) => `${g}: from step ${n}, where the paths part`,
    },
    de: {
      title: 'Einen Haushalt anlegen (CH1–CH5)', back: 'Alle Prototyp-Runden', overview: 'Überblick', rec: 'Empfehlung', light: 'Hell', dark: 'Dunkel', text: 'Text',
      compare: 'Fünf Wege, wie jemand Neues einen Haushalt anlegt und jemanden einlädt, neben Heute (der geführte Start auf main und die Einladungsseite im Umschalter-Blatt aus Job 242). Jeder geht vom Startbildschirm bis zur ersten Liste und bis zu einer geteilten Einladung per Link, QR oder Code. Beispieldaten, gemessen auf einem iPhone mit „Mit Apple anmelden“, mit Überspringen, wo ein Schritt es anbietet.',
      tap: 'Tipp', taps: 'Tipps', screens: 'Bildschirme', typed: 'plus Tippen von Text', pick: 'Empfehlung', runnerUp: 'Zweite Wahl', stack: 'unser Stack, kein neuer Anbieter', pasteGone: '„Einladung einfügen“ entfällt', pasteKept: '„Einladung einfügen“ bleibt',
      table: 'Vergleich', allScen: 'Link · QR · Code',
      cols: ['Variante', 'Tipps / Bildschirme bis zur ersten Liste', 'Tipps / Bildschirme bis zur geteilten Einladung', 'Fragen vor der Liste', 'Wo die Einladung liegt', 'QR', 'Einwilligung', 'Für Eingeladene', 'Bauaufwand', 'Fertiger Dienst'],
      tapsNote: 'Gemessen, indem jeder Weg vom Startbildschirm durchgegangen wird, mit Überspringen, wo ein Schritt es hat, und Anmeldung mit Apple. Fett: der oben gewählte Kanal; klein: der Bereich über Link, QR und Code. Ein Tipp auf einen Knopf, einen Chip oder ein System-Blatt zählt 1; das System-Blatt „Mit Apple anmelden“ zählt nicht als Bildschirm. „Einladung geteilt“ endet, wenn WhatsApp den Link sendet, der QR zu sehen ist oder der Code kopiert ist. verify.mjs geht jeden Weg mit echten Klicks durch und prüft die Zahlen.',
      side: 'Nebeneinander', sideNote: 'Der Weg jeder Variante bis zur geteilten Einladung, für den oben gewählten Kanal. Öffne eine Variante für große Handys und Ausprobieren.',
      factsTitle: 'Der Weg, Einladen, Einwilligung und Aufwand', tryIt: 'Ausprobieren', reset: 'Neu starten', tapHint: 'Tippe im Handy auf das umrandete Element.',
      soFar: (n) => `bisher ${n} ${n === 1 ? 'Tipp' : 'Tipps'}`, doneAfter: (n, s) => `Fertig: ${n} ${n === 1 ? 'Tipp' : 'Tipps'}, ${s} Schritte.`,
      goalNow: (g, t, s) => `${g}: ${t} Tipps, ${s} Bildschirme auf diesem Weg.`,
      partTitle: (g, n) => `${g}: ab Schritt ${n}, wo sich die Wege trennen`,
    },
  },
};
