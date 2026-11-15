// The join page for /join/<code> (job 169b, docs/households/W2.md "Join page"): asks
// preview_invite_public who invites to which household, then offers the browser join
// (/?invite=<code>, the Flutter app's join flow) and the code to type in the app.
import { publishableKey, supabaseUrl } from './config.js';

// Off until the listings are public (site/config/stores.mjs): then the store buttons and the
// Smart App Banner show.
const storeListings = { appStore: false, googlePlay: false };
const appStoreId = '6832756448';
const playPackage = 'com.snacklist.app';

// The alphabet create_invite draws from (app/lib/household/pending_invite.dart).
const codePattern = /^[A-HJ-NP-Z2-9]{8}$/;

const texts = {
  de: {
    title: 'Einladung · Snacklist',
    loading: 'Einladung wird geladen …',
    invitedBy: (inviter, household) => `${inviter} lädt dich zu „${household}“ ein`,
    invited: (household) => `Du bist zu „${household}“ eingeladen`,
    members: (n) => (n === 1 ? '1 Mitglied' : `${n} Mitglieder`),
    openItems: (n) => (n === 1 ? '1 offener Eintrag' : `${n} offene Einträge`),
    premium: 'Premium gilt für alle im Haushalt',
    join: 'Im Browser beitreten',
    enterCode: 'Code im Browser eingeben',
    codeLabel: 'Einladungscode',
    codeHint: 'Schon in der App? Gib den Code dort beim Beitreten ein.',
    copy: 'Code kopieren',
    copied: 'Kopiert',
    copiedStatus: 'Code kopiert',
    copyFailed: 'Kopieren ging nicht. Der Code ist markiert.',
    stores: 'App laden',
    appStore: 'Im App Store laden',
    googlePlay: 'Bei Google Play laden',
    invalid: ['Diese Einladung gilt nicht mehr', 'Sie ist abgelaufen, wurde zurückgezogen oder der Link ist unvollständig. Bitte um eine neue Einladung.'],
    full: ['Diese Einladung ist voll', 'Über diesen Link sind schon alle Plätze vergeben. Bitte um eine neue Einladung.'],
    rate_limited: ['Gerade zu viele Aufrufe', 'Die Einladung lässt sich gleich wieder ansehen. Beitreten geht schon jetzt.'],
    error: ['Einladung nicht geladen', 'Prüf deine Verbindung und lade die Seite neu. Beitreten geht auch direkt.'],
  },
  en: {
    title: 'Invite · Snacklist',
    loading: 'Loading the invite…',
    invitedBy: (inviter, household) => `${inviter} invites you to “${household}”`,
    invited: (household) => `You’re invited to “${household}”`,
    members: (n) => (n === 1 ? '1 member' : `${n} members`),
    openItems: (n) => (n === 1 ? '1 open item' : `${n} open items`),
    premium: 'Premium covers everyone in the household',
    join: 'Join in the browser',
    enterCode: 'Enter a code in the browser',
    codeLabel: 'Invite code',
    codeHint: 'Already in the app? Enter the code there when you join.',
    copy: 'Copy code',
    copied: 'Copied',
    copiedStatus: 'Code copied',
    copyFailed: 'Copying didn’t work. The code is selected.',
    stores: 'Get the app',
    appStore: 'Download on the App Store',
    googlePlay: 'Get it on Google Play',
    invalid: ['This invite no longer works', 'It expired, was withdrawn or the link is incomplete. Ask for a new invite.'],
    full: ['This invite is full', 'All places on this link are taken. Ask for a new invite.'],
    rate_limited: ['Too many requests right now', 'You can view the invite again in a moment. Joining works right away.'],
    error: ['Couldn’t load the invite', 'Check your connection and reload the page. You can also join directly.'],
  },
};

/** The browser's first German or English language, else English, as the app picks. */
function language() {
  const preferred = navigator.languages?.length ? navigator.languages : [navigator.language ?? ''];
  for (const tag of preferred) {
    const code = tag.toLowerCase().split('-')[0];
    if (code === 'de' || code === 'en') return code;
  }
  return 'en';
}

/**
 * The answer of preview_invite_public as one of the page's states:
 * { status: 'ok', household, inviter (null when unnamed), members, openItems, premium }, or
 * { status: 'invalid' | 'full' | 'rate_limited' | 'error' }.
 */
function parsePreview(body) {
  const row = Array.isArray(body) ? body[0] : body;
  const count = (n) => (Number.isInteger(n) && n >= 0 ? n : null);
  switch (row?.status) {
    case 'ok': {
      const members = count(row.members);
      const openItems = count(row.open_items);
      if (typeof row.household !== 'string' || members === null || openItems === null) return { status: 'error' };
      const inviter = typeof row.inviter === 'string' && row.inviter.trim() ? row.inviter.trim() : null;
      return { status: 'ok', household: row.household, inviter, members, openItems, premium: row.premium === true };
    }
    case 'invalid':
    case 'full':
    case 'rate_limited':
      return { status: row.status };
    default:
      return { status: 'error' };
  }
}

async function fetchPreview(code) {
  try {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/preview_invite_public`, {
      method: 'POST',
      headers: { apikey: publishableKey, 'content-type': 'application/json' },
      body: JSON.stringify({ p_code: code }),
      signal: AbortSignal.timeout(15_000),
    });
    return response.ok ? parsePreview(await response.json()) : { status: 'error' };
  } catch {
    return { status: 'error' };
  }
}

const byId = (id) => document.getElementById(id);
const formatCode = (code) => `${code.slice(0, 4)}-${code.slice(4)}`;

function show(id, text) {
  const element = byId(id);
  element.hidden = text === null;
  if (text !== null) element.textContent = text;
}

function render(t, code, preview) {
  const ok = preview.status === 'ok';
  const main = document.querySelector('main');
  main.dataset.state = preview.status;
  main.removeAttribute('aria-busy');

  const [title, body] = ok
    ? [preview.inviter ? t.invitedBy(preview.inviter, preview.household) : t.invited(preview.household), null]
    : t[preview.status];
  show('title', title);
  show('body', body);
  show('facts', ok ? `${t.members(preview.members)} · ${t.openItems(preview.openItems)}` : null);
  byId('premium').hidden = !(ok && preview.premium);
  byId('premium-text').textContent = t.premium;

  const join = byId('join');
  join.hidden = false;
  join.href = code ? `/?invite=${code}` : '/';
  const usable = ok || preview.status === 'rate_limited' || preview.status === 'error';
  join.querySelector('.face').textContent = usable ? t.join : t.enterCode;

  byId('code').hidden = !(code && usable);
  if (code) {
    byId('code-label').textContent = t.codeLabel;
    byId('code-value').textContent = formatCode(code);
    byId('code-hint').textContent = t.codeHint;
    byId('copy').querySelector('.face').textContent = t.copy;
  }
  if (code && usable) renderStores(t);
}

function renderStores(t) {
  const links = [];
  if (storeListings.appStore) links.push([t.appStore, `https://apps.apple.com/app/id${appStoreId}`]);
  if (storeListings.googlePlay) {
    links.push([t.googlePlay, `https://play.google.com/store/apps/details?id=${playPackage}`]);
  }
  if (links.length === 0) return;
  byId('stores-label').textContent = t.stores;
  byId('stores').querySelector('.stores__row').replaceChildren(...links.map(([label, href]) => {
    const link = document.createElement('a');
    link.className = 'hex hex--small hex--quiet';
    link.href = href;
    const face = document.createElement('span');
    face.className = 'face';
    face.textContent = label;
    link.append(face);
    return link;
  }));
  byId('stores').hidden = false;
}

function addSmartAppBanner(code) {
  if (!storeListings.appStore || !code) return;
  const meta = document.createElement('meta');
  meta.name = 'apple-itunes-app';
  meta.content = `app-id=${appStoreId}, app-argument=${location.origin}/join/${code}`;
  document.head.append(meta);
}

function wireCopy(t, code) {
  const button = byId('copy');
  const label = button.querySelector('.face');
  const status = byId('copy-status');
  let reset;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code);
      label.textContent = t.copied;
      status.textContent = t.copiedStatus;
      clearTimeout(reset);
      reset = setTimeout(() => {
        label.textContent = t.copy;
        status.textContent = '';
      }, 2_000);
    } catch {
      getSelection()?.selectAllChildren(byId('code-value'));
      status.textContent = t.copyFailed;
    }
  });
}

/** The invite code in /join/<code>, or null when the segment cannot be one. */
function codeFromPath(pathname) {
  let segment;
  try {
    segment = decodeURIComponent(pathname.split('/')[2] ?? '');
  } catch {
    return null;
  }
  const raw = segment.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return codePattern.test(raw) ? raw : null;
}

async function main() {
  const code = codeFromPath(location.pathname);

  // Query or fragment on a join link belong to the app: an OAuth or email sign-in that started on
  // /join/<code> comes back here with its code or tokens. The app reads them at /?invite=<code>.
  if (location.search || location.hash) {
    const params = new URLSearchParams(location.search);
    if (code) params.set('invite', code);
    location.replace(`/?${params}${location.hash}`);
    return;
  }

  const lang = language();
  const t = texts[lang];
  document.documentElement.lang = lang;
  document.title = t.title;
  document.getElementById('title').textContent = t.loading;
  addSmartAppBanner(code);
  wireCopy(t, code ?? '');
  render(t, code, code ? await fetchPreview(code) : { status: 'invalid' });
}

main();
