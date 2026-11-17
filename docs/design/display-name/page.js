import { Phone, NameBus } from './phone.js';
import { personas, derivedName } from './copy.js';

const params = new URLSearchParams(location.search);
const round = document.body.dataset.round;
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ({ 200: 200, 310: 310 })[params.get('ts')] ?? 100,
  persona: personas[params.get('persona')] ? params.get('persona') : (round === 'DE' ? 'email' : 'email'),
  role: params.get('role') === 'join' ? 'join' : 'create',
};
const defaults = { lang: 'en', theme: 'light', ts: '100', persona: 'email', role: 'create' };

const W = {
  en: {
    overview: 'Display name: prototype rounds DN and DE', back: 'Display name overview',
    overviewNote: 'Peter (17 Nov 2026): the app should ask “How should we call you?” during onboarding, and users must be able to change the name later. A household member already asked to change hers. Two rounds, each with five options and today for comparison. The phones are live: tap through them. Mock data only; nothing is sent.',
    DN: 'Round DN: asking for the name in onboarding', DE: 'Round DE: changing the name later',
    DNshort: 'Where and how the guided start (and the join path) asks for the name: a step of its own, a field on an existing step, a confirm after Google or Apple, asked when it first matters, or a skippable first question.',
    DEshort: 'Where a signed-in user changes the name, and where the change shows: Account, the own member tile, a header on More, the invite page, or a name per household.',
    note: {
      DN: 'Five ways to ask for the name, next to today. The first phone of each option is the whole path, live: tap through it (the scenario above sets who signs up and how). Under it, the taps and screens so far, and at the end what Peter and the join page show. The other phones open on the option’s own screen.',
      DE: 'Five ways to change the name later, next to today. The first phone of each option walks from the list to a saved name; save there, and the strip “What others see” below updates (Peter’s member list, his list, the join page of your invite).',
    },
    light: 'Light', dark: 'Dark', text: 'Text', largest: '200 % (Android’s largest)', ios: '310 % (iOS’s largest)', who: 'Scenario', path: 'Path', create: 'Creates the household', join: 'Joins by invite',
    personas: { email: 'E-mail sign-up', google: 'Google: Lea Brandt', appleHidden: 'Apple, name not shared', long: 'Long name', emoji: 'Name with emoji' },
    personasDE: { email: 'Name from e-mail (lea.brandt87)', google: 'Google: Lea Brandt', appleHidden: 'Apple relay (x7k2pq9mzd)', long: 'Long name', emoji: 'Name with emoji' },
    factsTitle: 'Today, from the code',
    facts: {
      DN: [
        'Nobody is asked. The profile trigger copies Google’s or Apple’s full name into profiles.display_name (default_display_name). Without one it stores the e-mail’s local part: an e-mail sign-up is “lea.brandt87” in the member list, an Apple user who hid the e-mail is “x7k2pq9mzd”.',
        'The join page (preview_invite_public) shows the inviter’s first word, but not when the name is the e-mail’s local part: then it says “You’re invited to …”.',
        'A later Google or Apple name (Apple’s first sign-in, a linked Google identity) replaces the profile name whenever it still equals the name derived from the old metadata (handle_user_metadata_update). That is the e-mail prefix, but also the old Google or Apple name: a “Yes, that’s me” written straight to profiles would be overwritten. A name written as display_name in the user’s metadata (updateUser) ranks first and stays (DN-Q4).',
        'Invitees skip the guided start: join page, sign-in, join screen, list. A step inside the guided start never reaches them, and with “Confirm new members” on, the admin decides by the name.',
        'The names show in the member list, join requests, “2 new from Lea” on the list, who took an item, the trip summary, and the report form (job 281).',
      ],
      DE: [
        'There is no way to change the name. Account shows the e-mail, export and delete; the household page lists members as plain text (“lea.brandt87 (you)”).',
        'The server already allows it: authenticated users may update profiles.display_name (1 to 80 characters), and RLS lets household members read each other’s profile.',
        'The name is one per user, shared by all households (profiles). A name per household (DE5) needs a new column on household_members.',
        'The member list and the join page read the name when they load; the list’s “new from” banner and item owners come with the items.',
      ],
    },
    frames: {
      walk: 'Walk it (live)', account: 'Account step', invite: 'Invite step', you: 'The name step', hhname: 'Household name + your name', confirm: 'After sign-in',
      inviteAsk: 'Tap “Invite your partner”', hello: 'First question', whoNamed: 'Next step, named', joinconfirm: 'Join screen', joinAsk: 'Tap “Join household”', list: 'Skipped: on the list',
      more: 'More', accountPage: 'Account', household: 'Household page', sheet: 'Edit', inline: 'Editing in place', invites: 'Invite page', peerHousehold: 'Peter’s member list', peerList: 'Peter’s list', peerJoin: 'Join page of your invite',
    },
    spread: 'What others see', spreadNote: {
      DN: 'Fed by the last walk above that reached the list (at first: today, for this scenario). Peter’s member list and his list show the full name, or “Unnamed” when it is empty; the join page shows the first word, never the e-mail prefix.',
      DE: 'Updates when any phone above saves. In the app the member list and the join page read the name when they open; the list’s banner and the names at items come with the next items (DE-Q4).',
    },
    meter: (p) => `Taps <b>${p.taps}</b> · screens and sheets <b>${p.screens}</b> · typed <b>${p.typed ? 'yes' : 'no'}</b>`,
    sees: (m, j) => `Peter sees <b>${m}</b> · join page: <b>${j}</b>`,
    noName: 'no name', pick: 'Pick', runner: 'Runner-up', jump: 'Recommendation, measured table and open questions',
  },
  de: {
    overview: 'Anzeigename: Prototyp-Runden DN und DE', back: 'Übersicht Anzeigename',
    overviewNote: 'Peter (17. Nov. 2026): Die App soll beim Einrichten fragen „Wie sollen wir dich nennen?“, und man muss den Namen später ändern können. Ein Haushaltsmitglied hat schon gefragt, wie sie ihren ändert. Zwei Runden mit je fünf Optionen und dem heutigen Stand zum Vergleich. Die Telefone sind echt: tipp dich durch. Nur Demodaten; nichts wird gesendet.',
    DN: 'Runde DN: den Namen beim Einrichten erfragen', DE: 'Runde DE: den Namen später ändern',
    DNshort: 'Wo und wie der geführte Start (und der Weg über eine Einladung) nach dem Namen fragt: ein eigener Schritt, ein Feld auf einem bestehenden Schritt, eine Bestätigung nach Google oder Apple, gefragt, wenn es zum ersten Mal zählt, oder eine überspringbare erste Frage.',
    DEshort: 'Wo man angemeldet den Namen ändert und wo die Änderung ankommt: Konto, die eigene Mitgliederzeile, ein Kopf in Mehr, die Einladungsseite oder ein Name je Haushalt.',
    note: {
      DN: 'Fünf Wege, nach dem Namen zu fragen, neben dem heutigen Stand. Das erste Telefon jeder Option ist der ganze Weg, live: tipp dich durch (das Szenario oben legt fest, wer sich wie anmeldet). Darunter die Tipps und Bildschirme bis hier, am Ende, was Peter und die Beitrittsseite zeigen. Die anderen Telefone öffnen auf dem eigenen Bildschirm der Option.',
      DE: 'Fünf Wege, den Namen später zu ändern, neben dem heutigen Stand. Das erste Telefon jeder Option geht von der Liste bis zum gespeicherten Namen; speichere dort, und der Streifen „Was andere sehen“ unten ändert sich mit (Peters Mitgliederliste, seine Liste, die Beitrittsseite deiner Einladung).',
    },
    light: 'Hell', dark: 'Dunkel', text: 'Text', largest: '200 % (größte bei Android)', ios: '310 % (größte bei iOS)', who: 'Szenario', path: 'Weg', create: 'Legt den Haushalt an', join: 'Tritt per Einladung bei',
    personas: { email: 'Anmeldung per E-Mail', google: 'Google: Lea Brandt', appleHidden: 'Apple, Name nicht geteilt', long: 'Langer Name', emoji: 'Name mit Emoji' },
    personasDE: { email: 'Name aus E-Mail (lea.brandt87)', google: 'Google: Lea Brandt', appleHidden: 'Apple-Relay (x7k2pq9mzd)', long: 'Langer Name', emoji: 'Name mit Emoji' },
    factsTitle: 'Heute, laut Code',
    facts: {
      DN: [
        'Niemand wird gefragt. Der Profil-Trigger übernimmt den vollen Namen von Google oder Apple in profiles.display_name (default_display_name). Ohne Namen speichert er den Teil der E-Mail vor dem @: Wer sich per E-Mail anmeldet, heißt in der Mitgliederliste „lea.brandt87“, wer bei Apple die E-Mail verbirgt, „x7k2pq9mzd“.',
        'Die Beitrittsseite (preview_invite_public) zeigt das erste Wort des Namens, aber nicht, wenn der Name der E-Mail-Teil ist: dann steht dort „Du bist zu … eingeladen“.',
        'Ein späterer Name von Google oder Apple (Apples erste Anmeldung, eine verknüpfte Google-Identität) ersetzt den Profilnamen, solange er noch dem aus den alten Metadaten abgeleiteten Namen gleicht (handle_user_metadata_update). Das ist der E-Mail-Teil, aber auch der alte Name von Google oder Apple: Ein „Ja, das bin ich“, direkt in profiles geschrieben, würde überschrieben. Ein Name, der als display_name in die Metadaten der Person geht (updateUser), steht an erster Stelle und bleibt (DN-Q4).',
        'Eingeladene überspringen den geführten Start: Beitrittsseite, Anmeldung, Beitritt, Liste. Ein Schritt im geführten Start erreicht sie nie, und mit „Beitritte bestätigen“ entscheidet der Admin nach dem Namen.',
        'Die Namen stehen in der Mitgliederliste, in Beitrittsanfragen, in „2 neu von Lea“ auf der Liste, bei übernommenen Einträgen, in der Einkaufsübersicht und im Meldeformular (Job 281).',
      ],
      DE: [
        'Ändern geht nicht. Konto zeigt die E-Mail, Export und Löschen; die Haushaltsseite listet Mitglieder als reinen Text („lea.brandt87 (du)“).',
        'Der Server erlaubt es schon: Angemeldete dürfen profiles.display_name ändern (1 bis 80 Zeichen), und RLS lässt Haushaltsmitglieder das Profil der anderen lesen.',
        'Es gibt einen Namen je Person, für alle Haushalte (profiles). Ein Name je Haushalt (DE5) braucht eine neue Spalte in household_members.',
        'Mitgliederliste und Beitrittsseite lesen den Namen beim Öffnen; das „neu von“-Banner und die Namen an Einträgen kommen mit den Einträgen.',
      ],
    },
    frames: {
      walk: 'Durchtippen (live)', account: 'Konto-Schritt', invite: 'Einladen-Schritt', you: 'Der Namensschritt', hhname: 'Haushaltsname + dein Name', confirm: 'Nach der Anmeldung',
      inviteAsk: 'Tipp auf „Partner·in einladen“', hello: 'Erste Frage', whoNamed: 'Nächster Schritt, mit Namen', joinconfirm: 'Beitritt', joinAsk: 'Tipp auf „Haushalt beitreten“', list: 'Übersprungen: auf der Liste',
      more: 'Mehr', accountPage: 'Konto', household: 'Haushaltsseite', sheet: 'Bearbeiten', inline: 'Direkt bearbeiten', invites: 'Einladungsseite', peerHousehold: 'Peters Mitgliederliste', peerList: 'Peters Liste', peerJoin: 'Beitrittsseite deiner Einladung',
    },
    spread: 'Was andere sehen', spreadNote: {
      DN: 'Kommt vom letzten Durchgang oben, der die Liste erreicht hat (zu Beginn: der heutige Stand für dieses Szenario). Peters Mitgliederliste und seine Liste zeigen den vollen Namen oder „Ohne Namen“, wenn er leer ist; die Beitrittsseite das erste Wort, nie den E-Mail-Teil.',
      DE: 'Ändert sich, sobald ein Telefon oben speichert. In der App lesen Mitgliederliste und Beitrittsseite den Namen beim Öffnen; Banner und Namen an Einträgen kommen mit den nächsten Einträgen (DE-Q4).',
    },
    meter: (p) => `Tipps <b>${p.taps}</b> · Bildschirme und Blätter <b>${p.screens}</b> · getippt <b>${p.typed ? 'ja' : 'nein'}</b>`,
    sees: (m, j) => `Peter sieht <b>${m}</b> · Beitrittsseite: <b>${j}</b>`,
    noName: 'kein Name', pick: 'Wahl', runner: 'Zweite Wahl', jump: 'Empfehlung, Messtabelle und offene Fragen',
  },
}[S.lang];

export const optionText = {
  en: {
    DN: {
      today: ['Today (main)', 'Nobody is asked. Google and Apple names are copied; an e-mail sign-up shows as its e-mail prefix (“lea.brandt87”) in the member list, and the join page then shows no inviter.'],
      DN1: ['DN1 A step of its own', '“How should we call you?” as step 3 of 8, right after “Who do you shop with?”, required, before the account. Google and Apple users type it too, because their name is not known before sign-in; the typed name wins over theirs. Joiners get the same screen after sign-in, prefilled from Google or Apple.'],
      DN2: ['DN2 A field on the household-name step', '“Your name” sits above “Household name” on the same screen, optional. No new screen; one tap into the field. Joiners get the field on the join screen, prefilled from Google or Apple. Left empty, today’s fallback stays.'],
      DN3: ['DN3 Confirm after sign-in', 'Right after the account, one screen asks. With a Google or Apple name it shows the name with “Yes, that’s me” (one tap) and “Change name”; without one, an empty field. Required. The same screen for creators and joiners, because every path passes the sign-in.'],
      DN4: ['DN4 Asked when it first matters', 'No new step. Tapping “Invite your partner” (or “Join household”) without a real name opens a sheet that asks, with the reason; “Not now” goes on without. With a Google or Apple name, the invite step shows “Your partner sees you as …” with Change instead. Solo users are never asked: nobody sees their name.'],
      DN5: ['DN5 The first question, skippable', '“Hi! What should we call you?” opens the guided start (step 2 of 8) with Skip. The next steps use the first name (“Lea, who do you shop with?”). Joiners get it after sign-in, prefilled. A joiner who skipped sees a card on the list: “Peter sees you as lea.brandt87”.'],
    },
    DE: {
      today: ['Today (main)', 'No way to change the name. Account has the e-mail, export and delete; the household page lists the members as text.'],
      DE1: ['DE1 Account › Your name', 'The first row on the Account page shows the name with a pencil; a tap opens a sheet with the field. One place, for all households. Where people look for “my profile”.'],
      DE2: ['DE2 Your own member tile', 'On the household page your own tile, “Lea (you)”, gets a pencil; a tap opens the same sheet. Other members’ tiles stay as they are. You change it where you see it among the others.'],
      DE3: ['DE3 A profile header on More', 'A card at the top of More with your initial, name and e-mail. The pencil turns it into a field in place; Done saves. Two taps to the field, at the cost of a card above every row of More.'],
      DE4: ['DE4 Where your invite shows it', 'The invite page shows “Your invite shows: “Lea invites you to …”” with “Change name”. You fix the name at the moment someone will see it, but only while inviting.'],
      DE5: ['DE5 A name per household', 'The own member tile edits your name in this household only (“Mama” in Familie Brandt, “Peter” in the club), with “Use this name in all my households”. Needs a column on household_members and a choice for each new household.'],
    },
  },
  de: {
    DN: {
      today: ['Heute (main)', 'Niemand wird gefragt. Namen von Google und Apple werden übernommen; wer sich per E-Mail anmeldet, steht als E-Mail-Teil („lea.brandt87“) in der Mitgliederliste, und die Beitrittsseite zeigt dann niemanden als Absender.'],
      DN1: ['DN1 Ein eigener Schritt', '„Wie sollen wir dich nennen?“ als Schritt 3 von 8, direkt nach „Mit wem kaufst du ein?“, Pflicht, vor dem Konto. Auch wer Google oder Apple nutzt, tippt ihn, weil deren Name vor der Anmeldung nicht bekannt ist; der getippte Name gewinnt. Eingeladene bekommen denselben Bildschirm nach der Anmeldung, vorausgefüllt von Google oder Apple.'],
      DN2: ['DN2 Ein Feld beim Haushaltsnamen', '„Dein Name“ steht über „Name des Haushalts“ auf demselben Bildschirm, freiwillig. Kein neuer Bildschirm; ein Tipp ins Feld. Eingeladene bekommen das Feld beim Beitritt, vorausgefüllt von Google oder Apple. Bleibt es leer, gilt der heutige Ersatz.'],
      DN3: ['DN3 Bestätigen nach der Anmeldung', 'Direkt nach dem Konto fragt ein Bildschirm. Mit einem Namen von Google oder Apple zeigt er ihn mit „Ja, das bin ich“ (ein Tipp) und „Namen ändern“; ohne Namen ein leeres Feld. Pflicht. Derselbe Bildschirm für alle, die anlegen oder beitreten, weil jeder Weg über die Anmeldung führt.'],
      DN4: ['DN4 Gefragt, wenn es zählt', 'Kein neuer Schritt. Ein Tipp auf „Partner·in einladen“ (oder „Haushalt beitreten“) ohne echten Namen öffnet ein Blatt, das fragt und sagt, warum; „Jetzt nicht“ geht ohne weiter. Mit einem Namen von Google oder Apple zeigt der Einladen-Schritt stattdessen „Dein·e Partner·in sieht dich als …“ mit Ändern. Wer allein einkauft, wird nie gefragt: niemand sieht den Namen.'],
      DN5: ['DN5 Die erste Frage, überspringbar', '„Hallo! Wie sollen wir dich nennen?“ eröffnet den geführten Start (Schritt 2 von 8), mit Überspringen. Die nächsten Schritte nutzen den Vornamen („Lea, mit wem kaufst du ein?“). Eingeladene bekommen die Frage nach der Anmeldung, vorausgefüllt. Wer beim Beitritt übersprungen hat, sieht auf der Liste eine Karte: „Peter sieht dich als lea.brandt87“.'],
    },
    DE: {
      today: ['Heute (main)', 'Den Namen ändern geht nicht. Konto hat E-Mail, Export und Löschen; die Haushaltsseite listet die Mitglieder als Text.'],
      DE1: ['DE1 Konto › Dein Name', 'Die erste Zeile auf der Konto-Seite zeigt den Namen mit einem Stift; ein Tipp öffnet ein Blatt mit dem Feld. Ein Ort, für alle Haushalte. Dort, wo man „mein Profil“ sucht.'],
      DE2: ['DE2 Die eigene Mitgliederzeile', 'Auf der Haushaltsseite bekommt die eigene Zeile „Lea (du)“ einen Stift; ein Tipp öffnet dasselbe Blatt. Die Zeilen der anderen bleiben, wie sie sind. Man ändert ihn dort, wo man ihn zwischen den anderen sieht.'],
      DE3: ['DE3 Ein Profilkopf in Mehr', 'Eine Karte oben in Mehr mit Initiale, Name und E-Mail. Der Stift macht daraus ein Feld an Ort und Stelle; Fertig speichert. Zwei Tipps bis zum Feld, um den Preis einer Karte über allen Zeilen von Mehr.'],
      DE4: ['DE4 Wo deine Einladung ihn zeigt', 'Die Einladungsseite zeigt „Deine Einladung zeigt: „Lea lädt dich zu … ein““ mit „Namen ändern“. Man korrigiert den Namen dann, wenn ihn jemand sehen wird, aber nur beim Einladen.'],
      DE5: ['DE5 Ein Name je Haushalt', 'Die eigene Mitgliederzeile ändert den Namen nur in diesem Haushalt („Mama“ in Familie Brandt, „Peter“ im Verein), mit „Diesen Namen in allen meinen Haushalten nutzen“. Braucht eine Spalte in household_members und eine Entscheidung für jeden neuen Haushalt.'],
    },
  },
}[S.lang];

const signed = { signedIn: true, kind: 'partner', needs: [0, 1] };
export const boards = {
  DN: {
    create: {
      today: [['walk', {}], ['account', { screen: 'account', kind: 'partner' }], ['invite', { screen: 'invite', ...signed }]],
      DN1: [['walk', {}], ['you', { screen: 'you', kind: 'partner' }]],
      DN2: [['walk', {}], ['hhname', { screen: 'hhname', kind: 'partner' }]],
      DN3: [['walk', {}], ['confirm', { screen: 'confirm', ...signed }]],
      DN4: [['walk', {}], ['inviteAsk', { screen: 'invite', ...signed, then: 'askIfDerived' }]],
      DN5: [['walk', {}], ['hello', { screen: 'hello' }], ['whoNamed', { screen: 'who', draftName: 'Lea' }]],
    },
    join: {
      today: [['walk', {}], ['joinconfirm', { screen: 'joinconfirm', signedIn: true }]],
      DN1: [['walk', {}], ['you', { screen: 'you', signedIn: true }]],
      DN2: [['walk', {}], ['joinconfirm', { screen: 'joinconfirm', signedIn: true }]],
      DN3: [['walk', {}], ['confirm', { screen: 'confirm', signedIn: true }]],
      DN4: [['walk', {}], ['joinAsk', { screen: 'joinconfirm', signedIn: true, then: 'askIfDerived' }]],
      DN5: [['walk', {}], ['hello', { screen: 'hello', signedIn: true }], ['list', { screen: 'list', signedIn: true }]],
    },
  },
  DE: {
    today: [['more', { screen: 'more' }], ['accountPage', { screen: 'accountPage' }], ['household', { screen: 'household' }]],
    DE1: [['walk', {}], ['accountPage', { screen: 'accountPage' }], ['sheet', { screen: 'accountPage', then: 'edit' }]],
    DE2: [['walk', {}], ['household', { screen: 'household' }], ['sheet', { screen: 'household', then: 'edit' }]],
    DE3: [['walk', {}], ['more', { screen: 'more' }], ['inline', { screen: 'more', then: 'editInline' }]],
    DE4: [['walk', {}], ['invites', { screen: 'invites' }], ['sheet', { screen: 'invites', then: 'edit' }]],
    DE5: [['walk', {}], ['household', { screen: 'household' }], ['sheet', { screen: 'household', then: 'edit' }]],
  },
};
export const OPTIONS = { DN: ['DN1', 'DN2', 'DN3', 'DN4', 'DN5', 'today'], DE: ['DE1', 'DE2', 'DE3', 'DE4', 'DE5', 'today'] };

// The profile a DE scenario starts with: what the trigger stored, or a chosen name with an emoji.
export function startProfile(key) {
  const p = personas[key];
  if (key === 'emoji') return { name: 'Lea 🌻', source: 'chosen' };
  return p.social ? { name: p.social, source: 'social' } : { name: derivedName(p.email), source: 'derived' };
}

async function themeCss() {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
}

// RECOMMENDATION.md (or .de.md) is one source for the page and the PR.
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

const recOf = async (path) => {
  const src = await (await fetch(path)).text();
  return { src, pick: src.match(/<!-- pick: (\w+) -->/)?.[1], runner: src.match(/<!-- runner-up: (\w+) -->/)?.[1] };
};
const btn = (k, v, label) => `<button data-set="${k}=${v}" aria-pressed="${String(S[k]) === String(v)}">${label}</button>`;
const baseControls = () => `<span class="lbl">Lang</span>${btn('lang', 'en', 'English')}${btn('lang', 'de', 'Deutsch')}<span class="sep"></span>${btn('theme', 'light', W.light)}${btn('theme', 'dark', W.dark)}<span class="sep"></span>${btn('ts', 100, `${W.text} 100 %`)}${btn('ts', 200, `${W.text} ${W.largest}`)}${btn('ts', 310, `${W.text} ${W.ios}`)}`;
const qs = (extra = {}) => { const q = new URLSearchParams(location.search); for (const [k, v] of Object.entries(extra)) q.set(k, v); const s = q.toString(); return s ? `?${s}` : ''; };

async function overviewPage(app) {
  const [dn, de] = await Promise.all([recOf(`dn/${S.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md'}`), recOf(`de/${S.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md'}`)]);
  const card = (r, id) => `<a class="ocard" href="${id.toLowerCase()}/${qs()}" data-round-link="${id}"><h2>${W[id]}</h2><p>${W[`${id}short`]}</p><p>${(r.src.split('\n').find((l) => l.startsWith('**')) ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')}</p><p><span class="tag pick">${W.pick}</span> ${optionText[id][r.pick]?.[0] ?? ''}</p><p><span class="tag runner">${W.runner}</span> ${optionText[id][r.runner]?.[0] ?? ''}</p></a>`;
  app.innerHTML = `<header class="page-head"><div class="title-row"><h1>${W.overview}</h1></div><p class="note">${W.overviewNote}</p><div class="controls">${baseControls()}</div></header>
    <div class="view"><div class="cards">${card(dn, 'DN')}${card(de, 'DE')}</div></div>`;
}

async function roundPage(app) {
  const rec = await recOf(S.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md');
  const names = round === 'DE' ? W.personasDE : W.personas;
  const tag = (id) => (id === rec.pick ? `<span class="tag pick">${W.pick}</span>` : id === rec.runner ? `<span class="tag runner">${W.runner}</span>` : '');
  const bd = round === 'DE' ? boards.DE : boards.DN[S.role];
  const texts = optionText[round];
  const phoneCell = (id, f, i) => `<figure class="cell"><figcaption>${W.frames[f]}</figcaption><div class="phone" data-frame="${id}:${f}" data-option="${id}" data-i="${i}"></div>${f === 'walk' ? `<p class="meter" data-meter="${id}"></p>` : ''}</figure>`;
  const section = (id) => `<section class="option" id="${id}" data-option="${id}"><h2>${texts[id][0]}${tag(id)}</h2><p>${texts[id][1]}</p><div class="frames">${bd[id].map(([f], i) => phoneCell(id, f, i)).join('')}</div></section>`;
  const peers = ['peerHousehold', 'peerList', 'peerJoin'];
  app.innerHTML = `<header class="page-head">
      <div class="title-row"><h1>${W[round]}</h1><a class="back-link" href="../${qs()}">← ${W.back}</a></div>
      <p class="note">${W.note[round]}</p>
      <div class="controls">${baseControls()}</div>
      <div class="controls"><span class="lbl">${W.who}</span>${Object.entries(names).map(([k, v]) => btn('persona', k, v)).join('')}${round === 'DN' ? `<span class="sep"></span><span class="lbl">${W.path}</span>${btn('role', 'create', W.create)}${btn('role', 'join', W.join)}` : ''}</div>
      <p class="note"><b>${W.pick}: ${texts[rec.pick]?.[0] ?? ''}</b> · ${W.runner}: ${texts[rec.runner]?.[0] ?? ''} · <a href="#rec">${W.jump} ↓</a></p>
    </header>
    <div class="view">
      <section class="facts"><h2>${W.factsTitle}</h2><ul>${W.facts[round].map((x) => `<li>${x}</li>`).join('')}</ul></section>
      ${OPTIONS[round].map(section).join('')}
      <section class="spread" id="spread"><h2>${W.spread}</h2><p>${W.spreadNote[round]}</p><div class="frames">${peers.map((f) => `<figure class="cell"><figcaption>${W.frames[f]}</figcaption><div class="phone" data-peer="${f}"></div></figure>`).join('')}</div></section>
      <section class="rec" id="rec">${md(rec.src)}</section>
    </div>`;
  const bus = new NameBus();
  const persona = S.persona;
  const base = round === 'DE' ? startProfile(persona) : (() => { const p = personas[persona]; return p.social ? { name: p.social, source: 'social' } : { name: derivedName(p.email), source: 'derived' }; })();
  bus.profile = base;
  const meter = (ph) => {
    const m = app.querySelector(`[data-meter="${ph.o.option}"]`);
    if (!m) return;
    const screens = ph.trail.filter((x, i, a) => x !== a[i - 1]).length;
    const seen = ph.seen();
    const done = round === 'DN' ? ph.finished : ph.saved || ph.everSaved;
    m.innerHTML = `${W.meter({ taps: ph.taps, screens, typed: ph.typed })}${done || round === 'DN' && ph.finished ? `<br>${W.sees(seen.member, seen.join ?? W.noName)}` : ''}`;
  };
  for (const el of app.querySelectorAll('.phone[data-frame]')) {
    const [id, f] = el.dataset.frame.split(':');
    const state = structuredClone(bd[id][+el.dataset.i][1]);
    if (S.ts !== 100) el.classList.add(`ts${S.ts}`);
    if (round === 'DE') state.profile = base;
    const then = state.then;
    delete state.then;
    const ph = new Phone(el, {
      round, option: id, lang: S.lang, persona, role: S.role, state, bus: round === 'DE' ? bus : null, interactive: f === 'walk',
      onChange: (p) => {
        if (round === 'DE' && p.s.snack) p.everSaved = true;
        meter(p);
        if (round === 'DN' && p.finished && f === 'walk') bus.set(p.s.profile);
      },
    });
    el.phone = ph;
    if (then === 'askIfDerived') { if (ph.s.profile.source === 'derived') { ph.s.field.ask = ''; ph.sheet('ask'); } } else if (then) ph.act(then);
    ph.trail = [ph.s.screen];
    ph.taps = 0;
    meter(ph);
  }
  for (const el of app.querySelectorAll('.phone[data-peer]')) {
    if (S.ts !== 100) el.classList.add(`ts${S.ts}`);
    const ph = new Phone(el, { round: 'peer', option: 'peer', lang: S.lang, persona, role: 'create', state: { screen: el.dataset.peer, signedIn: true }, bus });
    el.phone = ph;
    bus.subs.add(() => ph.render());
  }
  bus.fresh = false;
  document.title = W[round];
}

async function main() {
  await themeCss();
  document.documentElement.className = `th-${S.theme}`;
  document.documentElement.lang = S.lang;
  const app = document.getElementById('app');
  if (round === 'overview') { document.title = W.overview; await overviewPage(app); } else await roundPage(app);
  app.querySelectorAll('[data-set]').forEach((b) => b.addEventListener('click', () => {
    const [k, v] = b.dataset.set.split('=');
    const q = new URLSearchParams(location.search);
    if (v === defaults[k]) q.delete(k); else q.set(k, v);
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
