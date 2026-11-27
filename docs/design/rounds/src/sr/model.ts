// Round SR: shopping reminders. One reminder is a shopping day, an offset (the day before or on
// the day) and a local time. SR4 groups several shopping days under one rule; every other option
// keeps one day per rule. Times are Europe/Berlin wall-clock minutes, so the mock clock needs no
// zone math.

export type Lang = 'en' | 'de';
export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;
export type Offset = 'before' | 'same';

export interface Rule {
  id: string;
  days: Weekday[];
  offset: Offset;
  /** Minutes after local midnight. */
  time: number;
}

export interface Reminder {
  ruleId: string;
  day: Weekday;
  offset: Offset;
  time: number;
}

export interface Firing extends Reminder {
  at: Date;
  /** The occurrence this week already passed, so this one is a week out. */
  rolledOver: boolean;
}

export type OptionId = 'today' | 'sr1' | 'sr2' | 'sr3' | 'sr4' | 'sr5';
export const OPTION_ORDER: readonly OptionId[] = ['today', 'sr1', 'sr2', 'sr3', 'sr4', 'sr5'];

export type FixtureId = 'none' | 'one' | 'three' | 'passed';

export const WEEKDAYS: readonly Weekday[] = [1, 2, 3, 4, 5, 6, 7];
export const CAP = 14;
export const DEFAULT_TIME = 19 * 60;
export const DEFAULT_OFFSET: Offset = 'before';

const t = (h: number, m = 0) => h * 60 + m;

const FIXTURE_REMINDERS: Record<FixtureId, Omit<Reminder, 'ruleId'>[]> = {
  none: [],
  one: [{ day: 6, offset: 'before', time: t(20) }],
  three: [
    { day: 2, offset: 'before', time: t(18) },
    { day: 6, offset: 'before', time: t(20) },
    { day: 6, offset: 'same', time: t(9, 15) },
  ],
  passed: [
    { day: 2, offset: 'before', time: t(18) },
    { day: 6, offset: 'before', time: t(20) },
    { day: 6, offset: 'same', time: t(9, 15) },
  ],
};

/** Mock "now" per fixture: Thursday 26 Nov 2026, 10:30; the passed case is Saturday 28 Nov, 10:30. */
export const FIXTURE_NOW: Record<FixtureId, Date> = {
  none: wall(2026, 11, 26, t(10, 30)),
  one: wall(2026, 11, 26, t(10, 30)),
  three: wall(2026, 11, 26, t(10, 30)),
  passed: wall(2026, 11, 28, t(10, 30)),
};

export const FIXTURES: readonly { id: FixtureId; code: string; label: string; note: string }[] = [
  { id: 'none', code: '1', label: 'No reminders', note: 'Empty state, reminder off.' },
  { id: 'one', code: '2', label: 'One reminder', note: 'Saturday, day before, 20:00.' },
  {
    id: 'three',
    code: '3·4·6',
    label: 'Three across days',
    note: 'Tue day-before 18:00; Sat day-before 20:00; Sat on-the-day 9:15. Covers day-before vs on-the-day (4) and two on one day (6).',
  },
  {
    id: 'passed',
    code: '5',
    label: 'Time already passed',
    note: 'Same three, now is Saturday 10:30: the 9:15 on-the-day reminder has passed, so it next fires a week later.',
  },
];

/** A Date whose UTC fields hold Berlin wall-clock time. */
export function wall(y: number, mo: number, d: number, minutes: number): Date {
  return new Date(Date.UTC(y, mo - 1, d, 0, minutes));
}

export function isoWeekday(at: Date): Weekday {
  return (((at.getUTCDay() + 6) % 7) + 1) as Weekday;
}

export function minutesOf(at: Date): number {
  return at.getUTCHours() * 60 + at.getUTCMinutes();
}

let seq = 0;
export const newId = () => `r${(seq += 1)}`;

export function fixtureRules(fixture: FixtureId, grouped: boolean): Rule[] {
  const reminders = FIXTURE_REMINDERS[fixture];
  if (!grouped) return reminders.map((r) => ({ id: newId(), days: [r.day], offset: r.offset, time: r.time }));
  const rules: Rule[] = [];
  for (const r of reminders) {
    const same = rules.find((x) => x.offset === r.offset && x.time === r.time);
    if (same) same.days = sortDays([...same.days, r.day]);
    else rules.push({ id: newId(), days: [r.day], offset: r.offset, time: r.time });
  }
  return rules;
}

export function fixtureDays(fixture: FixtureId): Set<Weekday> {
  return new Set(FIXTURE_REMINDERS[fixture].map((r) => r.day));
}

export const sortDays = (days: Weekday[]): Weekday[] => [...new Set(days)].sort((a, b) => a - b);

export function explode(rules: Rule[]): Reminder[] {
  return rules.flatMap((r) => r.days.map((day) => ({ ruleId: r.id, day, offset: r.offset, time: r.time })));
}

export const reminderCount = (rules: Rule[]) => explode(rules).length;

/** The weekday a reminder fires on. */
export function fireWeekday(day: Weekday, offset: Offset): Weekday {
  return offset === 'same' ? day : (((day + 5) % 7) + 1) as Weekday;
}

const DAY = 1440;

/** The next firing strictly after [now]; a time already passed today goes to next week (SR-Q7). */
export function nextFiring(r: Reminder, now: Date): Firing {
  const fire = fireWeekday(r.day, r.offset);
  let delta = ((fire - isoWeekday(now) + 7) % 7) * DAY + r.time - minutesOf(now);
  const rolledOver = delta <= 0 && delta > -DAY && fire === isoWeekday(now);
  if (delta <= 0) delta += 7 * DAY;
  return { ...r, at: new Date(now.getTime() + delta * 60_000), rolledOver };
}

export function upcoming(rules: Rule[], now: Date): Firing[] {
  return explode(rules)
    .map((r) => nextFiring(r, now))
    .sort((a, b) => a.at.getTime() - b.at.getTime());
}

/** Shopping-day order: by day, then the firing that comes first in that day's run-up. */
export function byShoppingDay(a: Reminder, b: Reminder): number {
  if (a.day !== b.day) return a.day - b.day;
  const rank = (r: Reminder) => (r.offset === 'before' ? 0 : DAY) + r.time;
  return rank(a) - rank(b);
}

export const sameReminder = (a: Omit<Reminder, 'ruleId'>, b: Omit<Reminder, 'ruleId'>) =>
  a.day === b.day && a.offset === b.offset && a.time === b.time;

/** Adds single-day rules for [days], skipping exact duplicates and stopping at the cap. */
export function addSingles(rules: Rule[], days: Weekday[], offset: Offset, time: number): { rules: Rule[]; added: Reminder[]; capped: boolean } {
  const existing = explode(rules);
  const next = [...rules];
  const added: Reminder[] = [];
  let capped = false;
  for (const day of days) {
    if (existing.some((e) => sameReminder(e, { day, offset, time }))) continue;
    if (existing.length + added.length >= CAP) {
      capped = true;
      break;
    }
    const rule = { id: newId(), days: [day], offset, time };
    next.push(rule);
    added.push({ ruleId: rule.id, day, offset, time });
  }
  return { rules: next, added, capped };
}

/* ---------- Copy ---------- */

const pad = (n: number) => String(n).padStart(2, '0');
export const hhmm = (minutes: number) => `${Math.floor(minutes / 60)}:${pad(minutes % 60)}`;

const DAY_LONG: Record<Lang, string[]> = {
  en: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  de: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
};
const DAY_SHORT: Record<Lang, string[]> = {
  en: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  de: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
};
const MONTH: Record<Lang, string[]> = {
  en: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  de: ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'],
};

export const dayLong = (lang: Lang, d: Weekday) => DAY_LONG[lang][d - 1] ?? '';
export const dayShort = (lang: Lang, d: Weekday) => DAY_SHORT[lang][d - 1] ?? '';

export function dateShort(lang: Lang, at: Date): string {
  const wd = dayShort(lang, isoWeekday(at));
  const month = MONTH[lang][at.getUTCMonth()] ?? '';
  return lang === 'en' ? `${wd} ${at.getUTCDate()} ${month}` : `${wd}, ${at.getUTCDate()}. ${month}`;
}

/** "Today", "Tomorrow" or the short date, relative to [now]. */
export function relativeDay(lang: Lang, at: Date, now: Date): string {
  const days = Math.round((startOfDay(at) - startOfDay(now)) / 86_400_000);
  if (days === 0) return C[lang].today;
  if (days === 1) return C[lang].tomorrow;
  return dateShort(lang, at);
}

const startOfDay = (d: Date) => Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());

export const C = {
  en: {
    appBar: 'Notifications',
    back: 'Back',
    tabs: ['List', 'History', 'More'],
    householdAdd: 'When someone adds something',
    householdAddHint:
      'A notification with the name and the item, e.g. “Lea added milk”. For items from a pharmacy or drugstore, no item name, e.g. “Lea added something to the list”. Several in a short time come as one.',
    nameHidden: 'Leave my name out of notifications',
    nameHiddenHint: 'Others then see “Someone added milk”, even if you have not turned notifications on yourself.',
    todayTitle: 'Shopping-day reminder',
    todayHint:
      "Pick your shopping days. The evening before, at 7 pm in your device's time zone, Snacklist sends a reminder to your phone.",
    title: 'Shopping reminders',
    before: 'Day before',
    same: 'On the day',
    beforeLower: 'day before',
    sameLower: 'on the day',
    eveningBefore: 'Evening before',
    morningOf: 'Morning of',
    today: 'Today',
    tomorrow: 'Tomorrow',
    next: 'Next',
    nextWeek: 'next week',
    passedToday: (time: string) => `today’s ${time} has passed`,
    addReminder: 'Add reminder',
    newReminder: 'New reminder',
    editReminder: 'Edit reminder',
    shoppingDay: 'Shopping day',
    shoppingDays: 'Shopping days',
    when: 'When',
    time: 'Time',
    hour: 'Hour',
    minute: 'Minute',
    save: 'Save',
    cancel: 'Cancel',
    delete: 'Delete',
    add: 'Add',
    empty: 'No reminders yet. Add one for each time you want a nudge before you shop.',
    forShop: (day: string) => `for ${day}’s shop`,
    savedFirst: (when: string) => `Saved. First reminder: ${when}`,
    deleted: 'Reminder deleted',
    capReached: `That’s ${CAP} reminders, the most you can have. Delete one to add another.`,
    duplicate: 'You already have that reminder',
    pickDayFirst: 'Pick a shopping day first',
    notifBefore: 'Shopping day tomorrow',
    notifSame: 'Shopping day today',
    notifBody: '7 items on the list. Have a quick look.',
    fires: 'Sends',
    // SR2
    weekHint: 'Tap the day you shop to add a reminder.',
    addTo: (day: string) => `Add a reminder for ${day}`,
    editFor: (day: string) => `Reminder for ${day}`,
    // SR3
    quickHint: 'Pick your shopping days, then tap when you want the reminder.',
    customTime: 'Custom time…',
    yourReminders: 'Your reminders',
    added: (what: string) => `Added: ${what}`,
    // SR4
    rulesHint: 'One rule covers every day you shop at the same time.',
    firstRule: 'Your first rule',
    newRule: 'New rule',
    editRule: 'Edit rule',
    saveRule: 'Save rule',
    ruleSentence: (offset: Offset, time: string) =>
      offset === 'before' ? `The day before, at ${time}` : `On the day, at ${time}`,
    onDays: 'On',
    // SR5
    nextUp: 'Next reminder',
    upcomingWeek: 'Coming up',
    noneYet: 'No reminders yet',
    noneYetHint: 'Add one and you’ll see here when it comes.',
  },
  de: {
    appBar: 'Mitteilungen',
    back: 'Zurück',
    tabs: ['Liste', 'Verlauf', 'Mehr'],
    householdAdd: 'Wenn jemand etwas hinzufügt',
    householdAddHint:
      'Mitteilung mit Name und Eintrag, z. B. „Lea hat Milch hinzugefügt“. Bei Artikeln aus der Apotheke oder Drogerie ohne Artikelnamen, etwa „Lea hat etwas zur Liste hinzugefügt“. Mehrere kurz nacheinander kommen zusammen.',
    nameHidden: 'Meinen Namen in Mitteilungen weglassen',
    nameHiddenHint: 'Andere sehen dann „Jemand hat Milch hinzugefügt“, auch wenn du selbst keine Mitteilungen eingeschaltet hast.',
    todayTitle: 'Einkaufstag-Erinnerung',
    todayHint:
      'Wähle deine Einkaufstage. Am Abend davor um 19 Uhr in der Zeitzone deines Geräts schickt Snacklist dir einen Hinweis aufs Handy.',
    title: 'Einkaufs-Erinnerungen',
    before: 'Am Vortag',
    same: 'Am Einkaufstag',
    beforeLower: 'am Vortag',
    sameLower: 'am Einkaufstag',
    eveningBefore: 'Am Vorabend',
    morningOf: 'Am Morgen',
    today: 'Heute',
    tomorrow: 'Morgen',
    next: 'Nächste',
    nextWeek: 'nächste Woche',
    passedToday: (time: string) => `heute ${time} ist schon vorbei`,
    addReminder: 'Erinnerung hinzufügen',
    newReminder: 'Neue Erinnerung',
    editReminder: 'Erinnerung bearbeiten',
    shoppingDay: 'Einkaufstag',
    shoppingDays: 'Einkaufstage',
    when: 'Wann',
    time: 'Uhrzeit',
    hour: 'Stunde',
    minute: 'Minute',
    save: 'Speichern',
    cancel: 'Abbrechen',
    delete: 'Löschen',
    add: 'Hinzufügen',
    empty: 'Noch keine Erinnerung. Leg für jede Uhrzeit, zu der du vor dem Einkauf erinnert werden willst, eine an.',
    forShop: (day: string) => `für den Einkauf am ${day}`,
    savedFirst: (when: string) => `Gespeichert. Erste Erinnerung: ${when}`,
    deleted: 'Erinnerung gelöscht',
    capReached: `Das sind ${CAP} Erinnerungen, mehr geht nicht. Lösch eine, um eine neue anzulegen.`,
    duplicate: 'Diese Erinnerung hast du schon',
    pickDayFirst: 'Wähl zuerst einen Einkaufstag',
    notifBefore: 'Morgen ist Einkaufstag',
    notifSame: 'Heute ist Einkaufstag',
    notifBody: '7 Artikel stehen auf der Liste. Schau kurz rein.',
    fires: 'Kommt',
    weekHint: 'Tipp auf deinen Einkaufstag, um eine Erinnerung anzulegen.',
    addTo: (day: string) => `Erinnerung für ${day}`,
    editFor: (day: string) => `Erinnerung für ${day}`,
    quickHint: 'Wähl deine Einkaufstage, dann tipp, wann du erinnert werden willst.',
    customTime: 'Andere Uhrzeit …',
    yourReminders: 'Deine Erinnerungen',
    added: (what: string) => `Hinzugefügt: ${what}`,
    rulesHint: 'Eine Regel gilt für alle Tage, an denen du zur selben Zeit einkaufst.',
    firstRule: 'Deine erste Regel',
    newRule: 'Neue Regel',
    editRule: 'Regel bearbeiten',
    saveRule: 'Regel speichern',
    ruleSentence: (offset: Offset, time: string) =>
      offset === 'before' ? `Am Vortag um ${time}` : `Am Einkaufstag um ${time}`,
    onDays: 'An',
    nextUp: 'Nächste Erinnerung',
    upcomingWeek: 'Als Nächstes',
    noneYet: 'Noch keine Erinnerung',
    noneYetHint: 'Leg eine an, dann siehst du hier, wann sie kommt.',
  },
} as const;

export type Copy = (typeof C)['en'] | (typeof C)['de'];

export const offsetLabel = (lang: Lang, o: Offset) => (o === 'before' ? C[lang].before : C[lang].same);
export const offsetLower = (lang: Lang, o: Offset) => (o === 'before' ? C[lang].beforeLower : C[lang].sameLower);

/** "Saturday · day before · 20:00" */
export const reminderLine = (lang: Lang, r: Omit<Reminder, 'ruleId'>) =>
  `${dayLong(lang, r.day)} · ${offsetLower(lang, r.offset)} · ${hhmm(r.time)}`;

/** "Fri 27 Nov, 20:00" or "Tomorrow, 20:00" */
export const firingWhen = (lang: Lang, f: Firing, now: Date) => `${relativeDay(lang, f.at, now)}, ${hhmm(f.time)}`;
