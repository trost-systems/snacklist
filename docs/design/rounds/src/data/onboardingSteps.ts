// Real Snacklist onboarding content (7 steps), EN + DE, plus the state the steps edit.
// Wording follows the production ARB strings (analyticsConsent*, onboardingJoin, invite*),
// shortened where the prototype only needs the gist.

export type Lang = 'en' | 'de';

export type StepNumber = 1 | 2 | 3 | 4 | 5 | 6 | 7;
export const STEP_COUNT = 7;

export type StepId = 'usage' | 'who' | 'name' | 'stores' | 'need' | 'account' | 'invite';
export const STEP_IDS: Record<StepNumber, StepId> = {
  1: 'usage',
  2: 'who',
  3: 'name',
  4: 'stores',
  5: 'need',
  6: 'account',
  7: 'invite',
};

export function toStep(n: number): StepNumber {
  return Math.min(STEP_COUNT, Math.max(1, Math.round(n))) as StepNumber;
}

export const WHO_IDS = ['partner', 'family', 'flatmates', 'club', 'me', 'other'] as const;
export type WhoId = (typeof WHO_IDS)[number];

export const PRESET_STORE_IDS = [
  'edeka',
  'rewe',
  'lidl',
  'aldiSued',
  'aldiNord',
  'kaufland',
  'netto',
  'penny',
  'dm',
  'rossmann',
  'hardware',
] as const;
export type PresetStoreId = (typeof PRESET_STORE_IDS)[number];

export const STAPLE_IDS = [
  'milk',
  'bread',
  'eggs',
  'butter',
  'cheese',
  'bananas',
  'apples',
  'tomatoes',
  'pasta',
  'coffee',
  'yogurt',
  'toiletPaper',
] as const;
export type StapleId = (typeof STAPLE_IDS)[number];

export type StoreRef = { kind: 'preset'; id: PresetStoreId } | { kind: 'custom'; name: string };
export type ListItem = { kind: 'staple'; id: StapleId } | { kind: 'custom'; text: string };
export type AnalyticsChoice = 'allowed' | 'declined';
export type SignInMethod = 'google' | 'apple' | 'email';
export type FinishKind = 'invited' | 'later';

export interface OnboardingState {
  analytics: AnalyticsChoice | null;
  who: WhoId[];
  whoOther: string;
  /** null until the user edits the field; until then the name follows Step 2. */
  householdName: string | null;
  stores: StoreRef[];
  storeFieldOpen: boolean;
  storeDraft: string;
  items: ListItem[];
  itemDraft: string;
  signIn: SignInMethod | null;
}

export const INITIAL_STATE: OnboardingState = {
  analytics: null,
  who: [],
  whoOther: '',
  householdName: null,
  stores: [],
  storeFieldOpen: false,
  storeDraft: '',
  items: [],
  itemDraft: '',
  signIn: null,
};

export function storeKey(store: StoreRef): string {
  return store.kind === 'preset' ? `preset:${store.id}` : `custom:${store.name.toLowerCase()}`;
}

export function itemKey(item: ListItem): string {
  return item.kind === 'staple' ? `staple:${item.id}` : `custom:${item.text.toLowerCase()}`;
}

/** Who the invite on Step 7 is for. Drives the household name and the invite copy. */
export type Audience = 'partner' | 'family' | 'flatmates' | 'club' | 'other' | 'me' | 'anyone';

export function audienceOf(who: readonly WhoId[]): Audience {
  const order: readonly Exclude<WhoId, 'me'>[] = ['partner', 'family', 'flatmates', 'club', 'other'];
  const first = order.find((id) => who.includes(id));
  if (first) return first;
  return who.includes('me') ? 'me' : 'anyone';
}

/** "Just me" excludes everyone else, and picking anyone else clears "Just me". */
export function toggleWho(who: readonly WhoId[], id: WhoId): WhoId[] {
  if (who.includes(id)) return who.filter((w) => w !== id);
  if (id === 'me') return ['me'];
  return [...who.filter((w) => w !== 'me'), id];
}

export function householdNameFor(state: OnboardingState, lang: Lang): string {
  return state.householdName ?? COPY[lang].name.suggestions[audienceOf(state.who)];
}

export function storeLabel(store: StoreRef, lang: Lang): string {
  return store.kind === 'preset' ? COPY[lang].stores.names[store.id] : store.name;
}

export function itemLabel(item: ListItem, lang: Lang): string {
  return item.kind === 'staple' ? COPY[lang].need.staples[item.id] : item.text;
}

export interface OnboardingCopy {
  stepOf: (step: number, total: number) => string;
  back: string;
  leaveSetup: string;
  progress: string;
  usage: {
    title: string;
    bodyBeforeLink: string;
    link: string;
    bodyAfterLink: string;
    decline: string;
    allow: string;
  };
  who: {
    title: string;
    lead: string;
    options: Record<WhoId, string>;
    otherLabel: string;
    otherPlaceholder: string;
    continue: string;
    skip: string;
  };
  name: {
    title: string;
    lead: string;
    label: string;
    suggestions: Record<Audience, string>;
    continue: string;
    join: string;
  };
  stores: {
    title: string;
    lead: string;
    names: Record<PresetStoreId, string>;
    addOwn: string;
    fieldLabel: string;
    fieldPlaceholder: string;
    add: string;
    orderLabel: string;
    continue: string;
    skip: string;
  };
  need: {
    title: string;
    lead: string;
    staples: Record<StapleId, string>;
    fieldLabel: string;
    fieldPlaceholder: string;
    add: string;
    onList: (n: number) => string;
    remove: (label: string) => string;
    continue: string;
    continueWith: (n: number) => string;
  };
  account: {
    title: string;
    lead: string;
    google: string;
    apple: string;
    email: string;
    legalBefore: string;
    terms: string;
    legalMiddle: string;
    privacy: string;
    legalAfter: string;
  };
  invite: {
    titles: Record<Audience, string>;
    body: string;
    bodyMe: string;
    inviteSomeone: string;
    waiting: (n: number) => string;
    later: string;
    goToList: string;
  };
  done: {
    invited: string;
    later: string;
    restart: string;
  };
  notices: {
    privacy: string;
    terms: string;
    join: string;
    leave: string;
  };
}

export const COPY: Record<Lang, OnboardingCopy> = {
  en: {
    stepOf: (step, total) => `Step ${step} of ${total}`,
    back: 'Back',
    leaveSetup: 'Leave setup',
    progress: 'Setup progress',
    usage: {
      title: 'May Snacklist collect usage data?',
      bodyBeforeLink:
        'Peter Trost, who runs Snacklist, wants to see which features get used and find bugs. With your permission, Snacklist sends pseudonymous usage data and error reports to PostHog (servers in the EU). Item names, list contents, names and email addresses are never sent. Without your permission nothing is stored or sent. You can change this any time under More → Usage data. More in the ',
      link: 'privacy policy',
      bodyAfterLink: '.',
      decline: 'Don’t allow',
      allow: 'Allow',
    },
    who: {
      title: 'Who do you shop with?',
      lead: 'Pick all that apply. We use this for the name, the invite and your first tips.',
      options: {
        partner: 'Partner',
        family: 'Family',
        flatmates: 'Flatmates',
        club: 'Club or team',
        me: 'Just me',
        other: 'Other',
      },
      otherLabel: 'Who else?',
      otherPlaceholder: 'e.g. my neighbours',
      continue: 'Continue',
      skip: 'Skip',
    },
    name: {
      title: 'What should your household be called?',
      lead: 'Everyone you invite sees this name. You can change it later.',
      label: 'Household name',
      suggestions: {
        partner: 'Our home',
        family: 'Our family',
        flatmates: 'Our flat',
        club: 'Our team',
        other: 'Our household',
        me: 'My list',
        anyone: 'Our household',
      },
      continue: 'Continue',
      join: 'Join with an invite',
    },
    stores: {
      title: 'Where do you shop?',
      lead: 'Pick the stores you shop at. Your list shows them in this order.',
      names: {
        edeka: 'EDEKA',
        rewe: 'REWE',
        lidl: 'Lidl',
        aldiSued: 'Aldi Süd',
        aldiNord: 'Aldi Nord',
        kaufland: 'Kaufland',
        netto: 'Netto',
        penny: 'Penny',
        dm: 'dm',
        rossmann: 'Rossmann',
        hardware: 'Hardware store',
      },
      addOwn: 'Add your own store',
      fieldLabel: 'Store name',
      fieldPlaceholder: 'e.g. Market hall',
      add: 'Add store',
      orderLabel: 'Your list order',
      continue: 'Continue',
      skip: 'Skip',
    },
    need: {
      title: 'What do you need right now?',
      lead: 'Tap what should go on the list, or type it below.',
      staples: {
        milk: 'Milk',
        bread: 'Bread',
        eggs: 'Eggs',
        butter: 'Butter',
        cheese: 'Cheese',
        bananas: 'Bananas',
        apples: 'Apples',
        tomatoes: 'Tomatoes',
        pasta: 'Pasta',
        coffee: 'Coffee',
        yogurt: 'Yogurt',
        toiletPaper: 'Toilet paper',
      },
      fieldLabel: 'Anything else?',
      fieldPlaceholder: 'e.g. 2 cucumbers',
      add: 'Add to list',
      onList: (n) => `On your list (${n})`,
      remove: (label) => `Remove ${label}`,
      continue: 'Continue',
      continueWith: (n) => (n === 1 ? 'Continue with 1 item' : `Continue with ${n} items`),
    },
    account: {
      title: 'Create your account',
      lead: 'Almost done. Create an account to save your list and invite someone.',
      google: 'Continue with Google',
      apple: 'Continue with Apple',
      email: 'Continue with email',
      legalBefore: 'By continuing you accept the ',
      terms: 'Terms of Use',
      legalMiddle: '. How we handle your data is explained in the ',
      privacy: 'Privacy policy',
      legalAfter: '.',
    },
    invite: {
      titles: {
        partner: 'Invite your partner',
        family: 'Invite your family',
        flatmates: 'Invite your flatmates',
        club: 'Invite your team',
        other: 'Invite someone',
        me: 'Your list is ready',
        anyone: 'Invite someone',
      },
      body: 'Share the link with the person you shop with. Each invite works for one person and is valid for 7 days.',
      bodyMe: 'Shopping with someone after all? You can invite them any time from the list menu.',
      inviteSomeone: 'Invite someone',
      waiting: (n) => (n === 1 ? '1 item is waiting for your list.' : `${n} items are waiting for your list.`),
      later: 'Later',
      goToList: 'Go to the list',
    },
    done: {
      invited: 'Invite link ready. In the app the share sheet opens and your list follows.',
      later: 'Setup complete. In the app your list opens now.',
      restart: 'Restart Step 1',
    },
    notices: {
      privacy: 'Prototype: the privacy policy opens in the browser.',
      terms: 'Prototype: the Terms of Use open in the browser.',
      join: 'Prototype: the invite code screen opens here.',
      leave: 'Prototype: leaving setup returns to the welcome screen. Restarted at Step 1.',
    },
  },
  de: {
    stepOf: (step, total) => `Schritt ${step} von ${total}`,
    back: 'Zurück',
    leaveSetup: 'Einrichtung verlassen',
    progress: 'Fortschritt der Einrichtung',
    usage: {
      title: 'Darf Snacklist Nutzungsdaten erfassen?',
      bodyBeforeLink:
        'Peter Trost, der Snacklist betreibt, möchte sehen, welche Funktionen genutzt werden, und Fehler finden. Mit deiner Erlaubnis sendet Snacklist pseudonyme Nutzungsdaten und Fehlerberichte an PostHog (Server in der EU). Artikelnamen, Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Ohne Erlaubnis wird nichts gespeichert oder gesendet. Du kannst das jederzeit unter Mehr → Nutzungsdaten ändern. Mehr in der ',
      link: 'Datenschutzerklärung',
      bodyAfterLink: '.',
      decline: 'Nicht erlauben',
      allow: 'Erlauben',
    },
    who: {
      title: 'Mit wem kaufst du ein?',
      lead: 'Wähle alles Passende. Wir nutzen das für den Namen, die Einladung und deine ersten Tipps.',
      options: {
        partner: 'Partner',
        family: 'Familie',
        flatmates: 'WG',
        club: 'Verein oder Team',
        me: 'Nur ich',
        other: 'Andere',
      },
      otherLabel: 'Wer noch?',
      otherPlaceholder: 'z. B. meine Nachbarn',
      continue: 'Weiter',
      skip: 'Überspringen',
    },
    name: {
      title: 'Wie soll dein Haushalt heißen?',
      lead: 'Alle, die du einlädst, sehen diesen Namen. Du kannst ihn später ändern.',
      label: 'Name des Haushalts',
      suggestions: {
        partner: 'Unser Zuhause',
        family: 'Unsere Familie',
        flatmates: 'Unsere WG',
        club: 'Unser Team',
        other: 'Unser Haushalt',
        me: 'Meine Liste',
        anyone: 'Unser Haushalt',
      },
      continue: 'Weiter',
      join: 'Mit Einladung beitreten',
    },
    stores: {
      title: 'Wo kaufst du ein?',
      lead: 'Wähle die Läden, in denen du einkaufst. Deine Liste zeigt sie in dieser Reihenfolge.',
      names: {
        edeka: 'EDEKA',
        rewe: 'REWE',
        lidl: 'Lidl',
        aldiSued: 'Aldi Süd',
        aldiNord: 'Aldi Nord',
        kaufland: 'Kaufland',
        netto: 'Netto',
        penny: 'Penny',
        dm: 'dm',
        rossmann: 'Rossmann',
        hardware: 'Baumarkt',
      },
      addOwn: 'Eigenen Laden hinzufügen',
      fieldLabel: 'Name des Ladens',
      fieldPlaceholder: 'z. B. Markthalle',
      add: 'Laden hinzufügen',
      orderLabel: 'Reihenfolge deiner Liste',
      continue: 'Weiter',
      skip: 'Überspringen',
    },
    need: {
      title: 'Was brauchst du gerade?',
      lead: 'Tippe an, was auf die Liste soll, oder schreib es unten hin.',
      staples: {
        milk: 'Milch',
        bread: 'Brot',
        eggs: 'Eier',
        butter: 'Butter',
        cheese: 'Käse',
        bananas: 'Bananen',
        apples: 'Äpfel',
        tomatoes: 'Tomaten',
        pasta: 'Nudeln',
        coffee: 'Kaffee',
        yogurt: 'Joghurt',
        toiletPaper: 'Klopapier',
      },
      fieldLabel: 'Sonst noch was?',
      fieldPlaceholder: 'z. B. 2 Gurken',
      add: 'Zur Liste hinzufügen',
      onList: (n) => `Auf deiner Liste (${n})`,
      remove: (label) => `${label} entfernen`,
      continue: 'Weiter',
      continueWith: (n) => (n === 1 ? 'Weiter mit 1 Artikel' : `Weiter mit ${n} Artikeln`),
    },
    account: {
      title: 'Erstelle dein Konto',
      lead: 'Fast geschafft. Erstelle ein Konto, um deine Liste zu speichern und jemanden einzuladen.',
      google: 'Weiter mit Google',
      apple: 'Weiter mit Apple',
      email: 'Weiter mit E-Mail',
      legalBefore: 'Mit dem Fortfahren akzeptierst du die ',
      terms: 'Nutzungsbedingungen',
      legalMiddle: '. Wie wir mit deinen Daten umgehen, steht in der ',
      privacy: 'Datenschutzerklärung',
      legalAfter: '.',
    },
    invite: {
      titles: {
        partner: 'Lade deinen Partner ein',
        family: 'Lade deine Familie ein',
        flatmates: 'Lade deine WG ein',
        club: 'Lade dein Team ein',
        other: 'Lade jemanden ein',
        me: 'Deine Liste ist fertig',
        anyone: 'Lade jemanden ein',
      },
      body: 'Teile den Link mit der Person, mit der du einkaufst. Jede Einladung gilt für eine Person und 7 Tage.',
      bodyMe: 'Doch nicht allein? Du kannst jederzeit über das Listenmenü jemanden einladen.',
      inviteSomeone: 'Jemanden einladen',
      waiting: (n) => (n === 1 ? '1 Artikel wartet auf deine Liste.' : `${n} Artikel warten auf deine Liste.`),
      later: 'Später',
      goToList: 'Zur Liste',
    },
    done: {
      invited: 'Einladungslink bereit. In der App öffnet sich das Teilen-Menü, danach deine Liste.',
      later: 'Einrichtung fertig. In der App öffnet sich jetzt deine Liste.',
      restart: 'Neu ab Schritt 1',
    },
    notices: {
      privacy: 'Prototyp: Die Datenschutzerklärung öffnet sich im Browser.',
      terms: 'Prototyp: Die Nutzungsbedingungen öffnen sich im Browser.',
      join: 'Prototyp: Hier öffnet sich die Eingabe des Einladungscodes.',
      leave: 'Prototyp: Verlassen führt zum Willkommensbildschirm. Neustart bei Schritt 1.',
    },
  },
};
