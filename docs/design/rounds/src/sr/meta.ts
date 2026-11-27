import type { OptionId } from './model';

export interface OptionMeta {
  code: string;
  slug: string;
  name: string;
  spec: string;
  cases: string;
}

export const OPTIONS: Record<OptionId, OptionMeta> = {
  today: {
    code: 'Today',
    slug: 'today-fixed-19',
    name: 'Weekday chips, fixed 19:00 the evening before',
    spec: 'Production since job 378. Seven weekday chips; the server always sends at 19:00 local the evening before each picked day.',
    cases:
      'Covers only “several shopping days”. There is no time, no “on the day” and no second reminder for a day, so 20:00, 18:00 and 9:15 cannot be set. Fixtures 2, 3 and 5 show the days only.',
  },
  sr1: {
    code: 'SR1',
    slug: 'reminder-list-sheet',
    name: 'Reminder list + add sheet',
    spec: 'One row per reminder (“Saturday · day before · 20:00”) with its next firing under it. “Add reminder” opens a sheet: one shopping day, Day before / On the day, the time, Save. Tap a row to edit or delete it.',
    cases: 'Every case is one more row. Two reminders on Saturday are two rows next to each other.',
  },
  sr2: {
    code: 'SR2',
    slug: 'week-map',
    name: 'Week map',
    spec: 'A Mon–Sun strip is the control. Tap the day you shop: a composer opens under the strip with Day before / On the day and the time. Each shopping day lists its times as labelled chips (moon “Day before · 20:00”, sun “On the day · 9:15”).',
    cases: 'The day is picked by the same tap that opens the composer. Several days and two times on one day stay grouped under the shopping day.',
  },
  sr3: {
    code: 'SR3',
    slug: 'presets-first',
    name: 'Presets first',
    spec: 'Pick shopping days (several at once), then one tap on a recipe: “Evening before · 20:00”, “Evening before · 18:00”, “Morning of · 9:15”, or “Custom time…”. Saved reminders are a short list below with × to delete.',
    cases: 'Peter’s three times are the presets. The picked days stay picked, so a second recipe for the same day is one tap.',
  },
  sr4: {
    code: 'SR4',
    slug: 'multi-day-rules',
    name: 'Multi-day rules',
    spec: 'A reminder is a rule: offset, time and several days (“The day before, at 18:00 · Tue, Fri”). With no rules the composer is the screen; after that, “New rule” opens it. Two times on one day are two rules.',
    cases: 'Fewest rows for a regular multi-day shopper. Saturday’s two reminders sit in two different rules, which you have to read to see.',
  },
  sr5: {
    code: 'SR5',
    slug: 'next-up-timeline',
    name: 'Next-up timeline',
    spec: 'The first thing is what fires next (“Tomorrow, 20:00, for Saturday’s shop”) with the notification it sends, then the coming firings in time order. A floating “Add reminder” opens the same sheet as SR1. Tap any firing to edit it.',
    cases: 'A time that already passed today shows as next week with “today’s 9:15 has passed”, never as overdue.',
  },
};

/** Measured by scripts/verify-sr.mjs, which clicks each path and fails when these drift. */
export const TAPS: Record<OptionId, { first: number | null; second: number | null; path1: string; path2: string }> = {
  today: { first: null, second: null, path1: 'Not possible: 19:00 only (Sat chip = 1 tap gives Fri 19:00)', path2: 'Not possible' },
  sr1: { first: 4, second: 6, path1: 'Add · Sat · 20 · Save', path2: 'Add · Sat · On the day · 09 · :15 · Save' },
  sr2: { first: 3, second: 5, path1: 'Sat · 20 · Add', path2: 'Sat · On the day · 09 · :15 · Add' },
  sr3: { first: 2, second: 1, path1: 'Sat · “Evening before · 20:00”', path2: '“Morning of · 9:15” (Sat still picked)' },
  sr4: { first: 3, second: 6, path1: 'Sat · 20 · Save rule', path2: 'New rule · On the day · 09 · :15 · Sat · Save rule' },
  sr5: { first: 4, second: 6, path1: 'Add · Sat · 20 · Save', path2: 'Add · Sat · On the day · 09 · :15 · Save' },
};

/**
 * Mitteilungen content height (below the app bar, above the tab bar) in the three-reminder state at
 * 390×844, measured by scripts/verify-sr.mjs in Chromium. The viewport is 643 px. Every option
 * carries the same household-add block above it (352 px in EN at 100 %), so section100, the
 * reminder section alone, is what tells the options apart.
 */
export const HEIGHTS: Record<OptionId, { h100: number; h100de: number; h140: number; section100: number }> = {
  today: { h100: 589, h100de: 649, h140: 897, section100: 237 },
  sr1: { h100: 649, h100de: 687, h140: 1003, section100: 297 },
  sr2: { h100: 693, h100de: 772, h140: 1107, section100: 341 },
  sr3: { h100: 972, h100de: 1030, h140: 1429, section100: 620 },
  sr4: { h100: 649, h100de: 687, h140: 1054, section100: 297 },
  sr5: { h100: 820, h100de: 896, h140: 1178, section100: 404 },
};

export const VIEWPORT = 643;
