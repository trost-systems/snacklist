// The app's chrome and the phone's system screens as HTML. Every builder takes the render context `c`
// ({ lang, T, scen, next, step, L }) and returns a string.
import { icons } from './icons.js';
import { mock, facts, list, CODE, codeDash, LINK, ownItems } from './model.js';

export const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[ch]);
export const ic = (name, cls = '') => {
  if (!icons[name]) throw new Error(`icon ${name} missing`);
  return `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;
};
export const M = (c) => mock[c.lang];

// The control that leads on along the path carries `data-go`: the path step names it with `by` (default `primary`).
export const act = (c, name = 'primary') => (name && c.next && c.step?.via === 'tap' && (c.step.by ?? 'primary') === name ? `data-go="${c.next}"` : '');

// Buttons: primary is the honey hex (FilledButton), secondary the white hex (OutlinedButton), text the bare label (TextButton).
export const btn = (c, label, { kind = 'secondary', by, icon, wide = true, extra = '' } = {}) => {
  const attr = act(c, by ?? (kind === 'primary' ? 'primary' : null));
  if (kind === 'text') return `<button class="tbtn" ${attr} ${extra}>${icon ? ic(icon, 'sm') : ''}<span>${label}</span></button>`;
  return `<button class="tact ${kind === 'primary' ? 'honey' : ''} ${wide ? 'wide' : ''}" ${attr} ${extra}><span>${icon ? ic(icon, 'sm') : ''}${label}</span></button>`;
};

export const statusBar = (dark) => `<div class="status ${dark ? 'on-dark' : ''}"><b>9:41</b><span class="grow"></span><span class="sig"></span></div>`;
export const appBar = (c, { title = '', back, close, logout, by } = {}) =>
  `<div class="appbar">${back ? `<button class="ibtn" aria-label="Back" ${by === 'back' ? act(c, 'back') : ''}>${ic('arrow_back')}</button>` : '<span class="ibtn-sp"></span>'}<h2 class="grow">${title}</h2>${close ? `<button class="ibtn" aria-label="${c.T.onboardingExit}">${ic('close')}</button>` : ''}${logout ? `<button class="ibtn" aria-label="Sign out">${ic('logout')}</button>` : ''}</div>`;

export const brandBlock = (c, small) => `<div class="brand ${small ? 'small' : ''}"><span class="mark"><i>${ic('shopping_cart')}</i></span><b>${c.T.appTitle}</b></div>`;
export const legalFooter = (c) => `<div class="legal"><a>${c.T.imprint}</a> · <a>${c.T.privacy}</a></div>`;
export const page = (inner, { cls = '' } = {}) => `<div class="scroll"><div class="pg ${cls}">${inner}</div></div>`;
export const progress = (s, n = 7) => `<div class="prog"><i style="width:${(s / n) * 100}%"></i></div>`;

// Start screen (app/lib/onboarding/start_screen.dart). `o.paste` false drops "Paste invite"; `o.extra` replaces it.
export const startScreen = (c, o = {}) =>
  statusBar() +
  page(`<div class="center">${brandBlock(c)}<p class="tagline">${c.T.startTagline}</p><p class="body muted">${o.welcome ?? c.T.startWelcome}</p></div>
  <div class="stack">${o.buttons ?? `${btn(c, c.T.startGo, { kind: 'primary', by: 'go' })}${btn(c, c.T.startLogIn, { kind: 'text', by: 'login' })}`}
  ${o.paste === false ? '' : btn(c, c.T.invitePaste, { kind: 'text', by: 'paste', icon: 'content_paste' })}${o.extra ?? ''}</div>${legalFooter(c)}`, { cls: 'start' });

export const providerButtons = (c, { email = true } = {}) =>
  `<div class="stack">${btn(c, `<span class="apple"></span>${c.T.signInWithApple}`, { kind: 'primary', by: 'apple' })}${btn(c, `<span class="g">G</span>${c.T.signInWithGoogle}`, { by: 'google' })}${email ? btn(c, c.T.continueWithEmail, { icon: 'mail_outline', by: 'email' }) : ''}</div>`;

// Sign-in screen (app/lib/session/login_screen.dart): with an invite it shows "Invite saved" instead of Paste invite.
export const loginScreen = (c, { invite, paste = true } = {}) =>
  statusBar() +
  page(`${brandBlock(c)}${providerButtons(c)}<div class="stack">${invite ? `<p class="body muted center-t">${c.T.invitePasteWaiting}</p>` : `${btn(c, c.T.loginNew, { kind: 'text' })}${paste ? btn(c, c.T.invitePaste, { kind: 'text', icon: 'content_paste' }) : ''}`}</div>${legalFooter(c)}`);

// The system "Sign in with Apple" sheet over whatever screen asked for it.
export const appleSheet = (c, under, { owner } = {}) =>
  `${under}<div class="scrim"></div><div class="sheet os-sheet"><div class="os-top"><b>${c.T.os.appleTitle}</b><button class="ibtn" aria-label="Close">${ic('close', 'sm')}</button></div>
  <div class="sheet-body"><div class="center"><span class="mark big"><i>${ic('shopping_cart')}</i></span></div><p class="body center-t">${c.T.os.appleBody(owner ? M(c).ownerMail : M(c).joinerMail)}</p>
  <div class="os-rows"><div><small>${c.T.os.appleName}</small><b>${owner ? M(c).owner : `${M(c).joiner} Brandt`}</b></div><div><small>${c.T.os.appleEmail}</small><b>${c.T.os.appleHide}</b></div></div>
  <button class="os-btn" ${act(c)}>${c.T.os.appleContinue}</button></div></div>`;

// Analytics consent (app/lib/analytics/consent_screen.dart).
export const consentBody = (c) =>
  `<div class="center">${ic('query_stats_outlined', 'xl brandc')}</div><h1 class="h">${c.T.analyticsConsentTitle}</h1><p class="body">${esc(c.T.analyticsConsentBody)} <a>${c.T.analyticsConsentPrivacyLink}</a>.</p>
  <div class="row2">${btn(c, c.T.analyticsDecline, { by: 'decline', extra: 'data-tonal' })}${btn(c, c.T.analyticsAccept, { by: 'accept', extra: 'data-tonal' })}</div>`;
export const consentScreen = (c) => statusBar() + appBar(c, { title: c.T.analyticsSection, logout: true }) + page(consentBody(c));

// Join screen, signed in (app/lib/household/join_screen.dart): the preview shows only the household's name.
export const joinScreen = (c) =>
  statusBar() +
  appBar(c, { title: c.T.onboardingJoin, back: true }) +
  page(`<div class="lfield"><label>${c.T.inviteCode}</label><div class="hexfield"><span>${CODE}</span></div></div>
  <div class="card outline"><span class="hexface"><span>${ic('home_outlined')}</span></span><div><small class="muted">${c.T.invitePreview}</small><b class="title-l">${M(c).household}</b></div></div>
  <div class="stack">${btn(c, c.T.joinHousehold, { kind: 'primary' })}${btn(c, c.T.cancel, { kind: 'text' })}</div>`);

// Join request waiting (app/lib/household/join_request_waiting.dart).
export const waitingScreen = (c) =>
  statusBar() +
  appBar(c, { title: c.T.onboardingJoin, logout: true }) +
  page(`<div class="center"><span class="phex honey">${ic('hourglass_top_outlined')}</span></div><p class="body center-t strong">${c.T.joinRequestSent(M(c).household)}</p>
  <div class="stack">${btn(c, c.T.joinRequestCreateOwn, { kind: 'primary' })}${btn(c, c.T.joinRequestWithdraw, { kind: 'text' })}</div>`);

const tabs = (c) => `<div class="nav"><div class="pill-wrap"><nav class="pill-nav"><button class="on">${ic('shopping_cart', 'sm')}<span>${c.T.tabList}</span></button><button>${ic('menu', 'sm')}<span>${c.T.tabMore}</span></button></nav></div></div>`;

// The list tab (app/lib/list/list_screen.dart) with the switcher header (job 242, list-declutter).
// `o.items`: 'household' (the joined list), 'own' (the new owner's first items) or 'none'; `o.top`: cards above the list.
export const listScreen = (c, o = {}) => {
  const hh = o.household ?? M(c).household;
  const cats = o.items === 'own' ? [[c.lang === 'de' ? 'Ohne Kategorie' : 'Uncategorized', ownItems[c.lang]]] : o.items === 'none' ? [] : list[c.lang];
  const rows = cats
    .map(([cat, items]) => `<div class="cat"><span>${cat}</span><i></i></div>${items.map(([e, n, qty]) => `<div class="item"><span class="emoji">${e}</span><span class="iname">${qty ? `<span class="qty">${qty}</span> ` : ''}${esc(n)}</span></div>`).join('')}`)
    .join('');
  return `${statusBar()}<div class="hdr"><button class="tact switch" ${act(c, 'switcher')}><span><span class="sw-txt"><small>${esc(hh)}</small><b>${c.T.listName}</b></span>${ic('unfold_more', 'sm')}</span></button><span class="grow"></span>${o.headerExtra ?? ''}<button class="tact"><span>${c.T.listEdit}</span></button></div>
  <div class="scroll">${o.top ?? ''}${rows || `<p class="body muted pad">${c.lang === 'de' ? 'Die Liste ist leer. Tippe unten ein, was fehlt.' : 'Your list is empty. Type what you need below.'}</p>`}<div class="endpad"></div></div>
  ${o.snack ? `<div class="snack"><span class="grow">${o.snack}</span></div>` : ''}
  <div class="bottom"><div class="addbar"><div class="addfield"><span class="in">${c.T.addFieldHint}</span>${ic('mic')}</div></div>${tabs(c)}</div>${o.overlay ?? ''}`;
};

// "First steps" card (app/lib/tips/hint_views.dart): a joiner's first row is "Joined the household".
export const firstSteps = (c, { joined, invite } = {}) =>
  `<div class="sticker fs"><div class="fs-h">${ic('flag_outlined', 'sm brandc')}<b class="grow">${c.T.checklistTitle}</b><small class="muted">${c.T.checklistProgress(1, invite ? 3 : 2)}</small>${ic('close', 'sm')}</div>
  <div class="fs-row done"><span class="phex xs">${ic('check', 'xs')}</span><span>${joined ? c.T.checklistJoined : c.T.checklistStarted}</span></div>
  ${invite ? `<div class="fs-row"><span class="phex xs"></span><span class="grow"><b>${c.T.checklistInviteFamily}</b><small class="muted">${c.T.checklistInviteBody}</small></span>${btn(c, c.T.hintInviteAction, { by: 'fs-invite', wide: false })}</div>` : ''}
  <div class="fs-row"><span class="phex xs"></span><span class="grow"><b>${c.T.checklistShop}</b><small class="muted">${c.T.listHint}</small></span></div></div>`;

// A card on the list (new): analytics asked after the join, equal buttons, never in front of the list.
export const consentCard = (c) =>
  `<div class="sticker consent-card" data-consent-card><b>${c.T.analyticsConsentTitle}</b><p class="small muted">${c.lang === 'de' ? 'Hilft uns, Snacklist zu verbessern. Keine Listeninhalte, Namen oder E-Mail-Adressen.' : 'Helps us improve Snacklist. Never list contents, names or e-mail addresses.'} <a>${c.lang === 'de' ? 'Was genau?' : 'What exactly?'}</a></p><div class="row2">${btn(c, c.T.analyticsDecline, { by: 'decline' })}${btn(c, c.T.analyticsAccept, { by: 'accept' })}</div></div>`;

// The switcher sheet's household page and its invite page (job 242: invite is a page inside the sheet).
export const switcherSheet = (c, under) =>
  `${under}<div class="scrim"></div><div class="sheet"><div class="handle"></div><div class="sheet-top"><span class="grow"></span><button class="ibtn" aria-label="${c.T.close}">${ic('close')}</button></div>
  <div class="sheet-body"><div class="pad"><b class="title-l">${esc(M(c).ownName)}</b><p class="muted small">${c.T.householdOpenItems(2)}</p></div>
  <div class="pad">${btn(c, c.T.switcherInvite, { icon: 'person_add_outlined', by: 'invite', wide: false })}</div>
  <div class="mrow"><span class="hexface"><span>${ic('group_outlined')}</span></span><span class="grow"><span>${c.T.householdMembers(1)}</span></span>${ic('chevron_right', 'sm')}</div>
  <div class="section-h">${c.T.listsTitle}</div><div class="mrow"><span class="hexface"><span>${ic('shopping_cart_outlined')}</span></span><span class="grow"><span>${c.T.listName}</span></span>${ic('check', 'sm')}</div>
  <div class="mrow">${ic('add')}<span class="grow"><span>${c.T.listNew}</span></span></div></div></div>`;

export const inviteCard = (c, { revoke = true } = {}) =>
  `<div class="sticker inv-card"><small class="muted">${c.T.inviteCodeLabel}</small><b class="code">${CODE}</b><small class="muted">${c.T.inviteLinkLabel}</small><span class="small link">https://${LINK}</span><small class="muted">${c.T.inviteValidUntil}</small>
  <div class="stack">${btn(c, c.T.share, { kind: 'primary', icon: 'ios_share', by: 'share' })}${btn(c, c.T.copyLink, { icon: 'link', by: 'copy-link' })}${btn(c, c.T.copyCode, { icon: 'content_copy', by: 'copy-code' })}${revoke ? btn(c, c.T.inviteRevoke, { kind: 'text', icon: 'block' }) : ''}</div></div>`;

// A QR-looking pattern (mock: not a working code).
export const qr = (size = 112) => {
  const n = 25;
  let seed = 7;
  const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
  const finder = (x, y) => `<rect x="${x}" y="${y}" width="7" height="7" fill="none" stroke="currentColor" stroke-width="1"/><rect x="${x + 2}" y="${y + 2}" width="3" height="3"/>`;
  let cells = '';
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) {
      const inFinder = (x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9);
      if (!inFinder && rnd() > 0.52) cells += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
    }
  return `<svg class="qr" width="${size}" height="${size}" viewBox="-1 -1 ${n + 2} ${n + 2}" shape-rendering="crispEdges" aria-label="QR"><rect x="-1" y="-1" width="${n + 2}" height="${n + 2}" fill="#fff"/><g fill="#0b1024" color="#0b1024">${finder(0.5, 0.5)}${finder(n - 6.5, 0.5)}${finder(0.5, n - 6.5)}${cells}</g></svg>`;
};

export const invitePage = (c, under, { group } = {}) =>
  `${under}<div class="scrim"></div><div class="sheet"><div class="handle"></div><div class="sheet-top"><button class="tbtn back">${ic('arrow_back', 'sm')}<span>${esc(M(c).ownName)}</span></button><span class="grow"></span><button class="ibtn" aria-label="${c.T.close}">${ic('close')}</button></div>
  <div class="sheet-body"><div class="pad"><b class="title-l">${c.T.inviteSheetTitle}</b><p class="muted small">${esc(M(c).ownName)}</p></div><p class="hint pad">${c.T.inviteJoinPageHint}</p>
  <div class="section-h">${c.T.invitePersonTitle}</div><p class="pad small">${c.T.invitePersonBody}</p>${group === 'card' ? `<div class="pad">${inviteCard(c)}</div>` : `<div class="pad">${btn(c, c.T.newInvite, { kind: 'primary', icon: 'person_add_outlined', by: 'new-invite', wide: false })}</div>`}
  <div class="section-h">${c.T.inviteGroupTitle}</div><p class="pad small">${c.T.inviteGroupBody}</p>
  ${group === 'qr' ? `<div class="pad"><div class="sticker inv-card qr-card" data-shared="qr">${qr(150)}<small class="muted">${c.T.inviteGroupUses(0, 50)}</small><b class="code">${CODE}</b></div></div>` : `<div class="pad">${btn(c, c.T.inviteGroupCreate, { icon: 'qr_code_2', by: 'group', wide: false })}</div>`}
  <div class="section-h">${c.T.inviteJoinsTitle}</div><p class="pad small muted">${c.T.inviteJoinsEmpty}</p></div></div>`;

// The system share sheet; picking WhatsApp opens the chat with the text filled in.
export const shareSheet = (c, under) =>
  `${under}<div class="scrim"></div><div class="sheet os-sheet share"><div class="os-top"><b>${c.T.os.shareSheetTitle}</b><button class="ibtn" aria-label="Close" ${act(c, 'close')}>${ic('close', 'sm')}</button></div>
  <div class="apps"><button class="app-ic wa" ${act(c, 'whatsapp')}><i>💬</i><span>WhatsApp</span></button><button class="app-ic msg"><i>✉️</i><span>Messages</span></button><button class="app-ic"><i>📧</i><span>Mail</span></button><button class="app-ic"><i>⋯</i><span>More</span></button></div>
  <div class="os-rows"><div><b>${c.T.os.copy}</b>${ic('content_copy', 'sm')}</div></div></div>`;

// A messenger chat (WhatsApp-like). `from`: who wrote the invite; `mine`: the user is sending it.
export const chat = (c, { text, mine, sent, linkBy = 'link', compose } = {}) => {
  const body = esc(text).replace(/https:\/\/(\S+)/, (m) => `<a class="chat-link" ${act(c, linkBy)}>${m}</a>`);
  return `${statusBar()}<div class="chat-top">${ic('arrow_back', 'sm')}<span class="avatar">${mine ? 'N' : 'M'}</span><b class="grow">${mine ? 'Noah' : `${M(c).inviterFull}`}</b></div>
  <div class="chat-body"><div class="day">${c.T.os.today}</div>${mine && !sent ? '' : `<div class="bubble ${mine ? 'me' : 'them'}">${body}<small>9:41${mine ? ' ✓✓' : ''}</small></div>`}</div>
  <div class="chat-compose">${compose ? `<div class="compose-in">${esc(text)}</div><button class="send" aria-label="Send" ${act(c, 'send')}>${ic('send', 'sm')}</button>` : `<div class="compose-in muted">${c.T.os.typeMsg}</div>`}</div>`;
};

// Someone's phone showing a QR code, seen through the camera; the camera offers the link as a pill.
export const camera = (c, { pill } = {}) =>
  `<div class="camera">${statusBar(true)}<div class="viewfinder"><div class="other-phone"><small>${esc(M(c).ownName === 'x' ? '' : c.lang === 'de' ? 'Mias Handy' : 'Mia’s phone')}</small>${qr(170)}</div><span class="corners"></span></div>
  ${pill ? `<button class="cam-pill" ${act(c)}>${ic('link', 'sm')} ${c.T.os.cameraPill}</button>` : ''}<div class="cam-bar"><span>${c.T.os.camera}</span><i class="shutter"></i></div></div>`;

// The home screen with a few icons; `apps` names the ones that lead on.
export const homeScreen = (c, { snacklist } = {}) =>
  `<div class="home">${statusBar(true)}<div class="home-grid">${[
    ['📷', c.T.os.cameraApp, 'camera'],
    ['🧭', c.T.os.safari, ''],
    ['💬', 'WhatsApp', ''],
    ['🅰️', c.T.os.appStoreApp, 'store'],
    ...(snacklist ? [['snack', 'Snacklist', 'snacklist']] : []),
  ]
    .map(([e, n, by]) => `<button class="home-ic" ${by ? act(c, by) : ''}>${e === 'snack' ? `<span class="mark home-mark"><i>${ic('shopping_cart')}</i></span>` : `<i>${e}</i>`}<span>${n}</span></button>`)
    .join('')}</div></div>`;

// The App Store page; `phase` 'get' or 'open'. `o.banner` shows what the page carried over (an App Clip or a note).
export const appStore = (c, { phase = 'get', note } = {}) =>
  `${statusBar()}<div class="store"><div class="store-top">${ic('arrow_back', 'sm')}<span class="grow"></span>${ic('search', 'sm')}</div>
  <div class="store-head"><span class="mark store-mark"><i>${ic('shopping_cart')}</i></span><div class="grow"><b>Snacklist</b><small class="muted">${c.T.os.storeSub}</small>
  <button class="store-btn" ${act(c)}>${phase === 'get' ? c.T.os.storeGet : c.T.os.storeOpen}</button></div></div>
  <div class="store-meta"><span>${c.T.os.storeRating}</span><span>${c.T.os.storeAge}</span><span>${c.lang === 'de' ? 'Essen & Trinken' : 'Food & Drink'}</span></div>
  ${note ? `<div class="store-note">${note}</div>` : ''}
  <div class="store-shots"><i></i><i></i><i></i></div></div>`;

// Safari around a web page; `url` in the address bar.
export const safari = (c, url, inner) =>
  `${statusBar()}<div class="safari"><div class="web">${inner}</div><div class="addr"><span>${ic('lock_outline', 'xs')} ${esc(url)}</span></div></div>`;

// The static join page as it is today (app/web/join/), or with `o.extra` actions under the code.
export const webJoin = (c, o = {}) => {
  const w = c.T.web;
  return safari(
    c,
    `app.snacklist.app/join/${CODE}`,
    `<header class="wj-top"><span class="mark xs"><i>${ic('shopping_cart')}</i></span><b>Snacklist</b></header>
  <main class="wj"><h1 class="h">${w.invitedBy(M(c).inviter, M(c).household)}</h1><p class="muted">${w.members(facts.members)} · ${w.openItems(facts.open)}</p>
  ${o.top ?? ''}${o.join === false ? '' : btn(c, o.joinLabel ?? w.join, { kind: 'primary', by: 'web-join' })}
  ${o.code === false ? '' : `<section class="wj-code"><small class="lbl">${w.codeLabel}</small><b class="code">${codeDash}</b><small class="muted">${o.codeHint ?? w.codeHint}</small>${btn(c, o.copied ? w.copied : w.copy, { by: 'copy-code', wide: false })}</section>`}
  ${o.extra ?? ''}</main>`,
  );
};

// The Flutter web app in Safari; `bare` content (a whole screen) is used as is, anything else gets a page.
export const webApp = (c, inner, { bare } = {}) => safari(c, 'app.snacklist.app', `<div class="webapp">${bare || /class="(appbar|scroll|web-list)/.test(inner.slice(0, 200)) ? inner : page(inner)}</div>`);

// The new in-app invite landing (prototype): only the join page's disclosed facts, before any account.
export const landing = (c, o = {}) =>
  `${statusBar()}${o.bar ?? ''}<div class="scroll"><div class="pg land" data-landing><div class="center">${o.art ?? `<span class="phex big honey">${ic('group_add_outlined')}</span>`}</div>
  <p class="eyebrow center-t">${o.eyebrow ?? (c.lang === 'de' ? 'Einladung' : 'Invitation')}</p>
  <h1 class="h center-t">${c.T.web.invitedBy(M(c).inviter, M(c).household)}</h1>
  <p class="muted center-t">${c.T.web.members(facts.members)} · ${c.T.web.openItems(facts.open)}</p>
  ${o.body ? `<p class="body center-t">${o.body}</p>` : ''}${o.mid ?? ''}
  <div class="stack">${o.actions}</div>${o.foot ?? ''}</div></div>`;

// The account sheet a joiner sees (prototype): providers, the legal line, the household named once more.
export const accountSheet = (c, under, o = {}) =>
  `${under}<div class="scrim"></div><div class="sheet"><div class="handle"></div><div class="sheet-body pad-top">
  <div class="pad"><b class="title-l">${o.title ?? (c.lang === 'de' ? `Konto erstellen, um „${M(c).household}“ beizutreten` : `Create your account to join “${M(c).household}”`)}</b>${o.sub ? `<p class="small muted">${o.sub}</p>` : ''}</div>
  <div class="pad">${providerButtons(c)}</div><p class="small muted pad center-t">${legalLine(c)}</p></div></div>`;
// No terms to accept exist (the app has none); the account step keeps today's Imprint and Privacy links.
export const legalLine = (c) => `<a>${c.T.imprint}</a> · <a>${c.T.privacy}</a>`;

// A code field with the code typed (or empty with the keyboard up).
export const codeField = (c, { typed, label } = {}) =>
  `<div class="lfield"><label>${label ?? c.T.inviteCode}</label><div class="hexfield ${typed ? '' : 'focus'}"><span class="${typed ? 'code-in' : 'muted'}">${typed ? codeDash : 'XXXX-XXXX'}</span></div></div>`;
export const keyboard = (c, { paste } = {}) =>
  `<div class="kbd">${paste ? `<div class="kbd-sug"><button class="paste-ctl" ${act(c, 'paste-ctl')}>${ic('content_paste', 'sm')} ${c.lang === 'de' ? 'Einsetzen' : 'Paste'}</button></div>` : ''}<div class="kbd-keys">${'QWERTZUIOP ASDFGHJKL YXCVBNM'.split(' ').map((r) => `<div>${[...r].map((k) => `<i>${k}</i>`).join('')}</div>`).join('')}</div></div>`;

export const snack = (text) => `<div class="snack"><span class="grow">${text}</span></div>`;
export { CODE, codeDash, LINK, facts };
