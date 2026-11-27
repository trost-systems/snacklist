import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import { FIXTURES, FIXTURE_NOW, OPTION_ORDER, dateShort, fixtureDays, fixtureRules, hhmm, isoWeekday, minutesOf, wall } from './model';
import type { FixtureId, Lang, OptionId, Rule, Weekday } from './model';
import { HEIGHTS, OPTIONS, TAPS, VIEWPORT } from './meta';
import { SrPhone } from './SrPhone';
import type { Fit } from './SrPhone';
import './sr.css';

type ThemeChoice = 'system' | 'light' | 'dark';
type TextScale = 100 | 140;

function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener('change', onChange);
      return () => mql.removeEventListener('change', onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

function param<T extends string>(name: string, allowed: readonly T[], fallback: T): T {
  const v = new URLSearchParams(window.location.search).get(name);
  return allowed.find((a) => a === v) ?? fallback;
}

const FIXTURE_IDS = FIXTURES.map((f) => f.id);
const WEEK: readonly { day: number; wd: Weekday }[] = [23, 24, 25, 26, 27, 28, 29].map((day, i) => ({ day, wd: (i + 1) as Weekday }));

function seed(fixture: FixtureId): Record<OptionId, Rule[]> {
  return {
    today: [],
    sr1: fixtureRules(fixture, false),
    sr2: fixtureRules(fixture, false),
    sr3: fixtureRules(fixture, false),
    sr4: fixtureRules(fixture, true),
    sr5: fixtureRules(fixture, false),
  };
}

export function SrRound() {
  const [option, setOption] = useState<OptionId>(() => param('o', OPTION_ORDER, 'sr1'));
  const [fixture, setFixture] = useState<FixtureId>(() => param('f', FIXTURE_IDS, 'three'));
  const [lang, setLang] = useState<Lang>(() => param('lang', ['en', 'de'] as const, 'en'));
  const [themeChoice, setThemeChoice] = useState<ThemeChoice>(() => param('theme', ['system', 'light', 'dark'] as const, 'light'));
  const [textScale, setTextScale] = useState<TextScale>(() => (param('text', ['100', '140'] as const, '100') === '140' ? 140 : 100));
  const [now, setNow] = useState<Date>(() => FIXTURE_NOW[fixture]);
  const [rules, setRules] = useState(() => seed(fixture));
  const [days, setDays] = useState(() => fixtureDays(fixture));
  const [fit, setFit] = useState<Fit | null>(null);

  const systemDark = useMediaQuery('(prefers-color-scheme: dark)');
  const dark = themeChoice === 'dark' || (themeChoice === 'system' && systemDark);
  const info = OPTIONS[option];

  useEffect(() => {
    document.title = 'Snacklist · Shopping reminders · SR1–SR5';
    document.documentElement.lang = lang;
  }, [lang]);

  useEffect(() => {
    const root = document.documentElement;
    if (themeChoice === 'system') root.removeAttribute('data-theme');
    else root.dataset.theme = themeChoice;
    root.dataset.textScale = String(textScale);
  }, [themeChoice, textScale]);

  useEffect(() => {
    const q = new URLSearchParams({ o: option, f: fixture, lang, theme: themeChoice, text: String(textScale) });
    window.history.replaceState(null, '', `${window.location.pathname}?${q}`);
  }, [option, fixture, lang, themeChoice, textScale]);

  const loadFixture = (f: FixtureId) => {
    setFixture(f);
    setNow(FIXTURE_NOW[f]);
    setRules(seed(f));
    setDays(fixtureDays(f));
  };

  const onFit = useCallback((f: Fit) => {
    setFit((prev) => (prev && prev.content === f.content && prev.viewport === f.viewport && prev.section === f.section ? prev : f));
  }, []);

  const setOptionRules = useCallback((r: Rule[]) => setRules((all) => ({ ...all, [option]: r })), [option]);

  const nowWd = isoWeekday(now);
  const nowMin = minutesOf(now);
  const nowLabel = `${dateShort('en', now)} ${hhmm(nowMin)}`;
  const overflow = fit ? fit.content - fit.viewport : 0;

  const recRows = useMemo(() => OPTION_ORDER, []);

  return (
    <div className="app sr-page">
      <header className="topbar">
        <div className="topbar-row">
          <div className="topbar-heading">
            <a className="topbar-back" href="/">
              All rounds
            </a>
            <h1 className="topbar-title">
              Shopping reminders <span className="topbar-title-sub">· SR1–SR5</span>
            </h1>
            <p className="topbar-question">
              How should a person add and manage several shopping reminders, each with its own day and time?
            </p>
          </div>
          <div className="toggles" role="group" aria-label="Display settings">
            <button
              type="button"
              className="toggle"
              data-testid="toggle-theme"
              aria-label={dark ? 'Theme: dark. Switch to light' : 'Theme: light. Switch to dark'}
              onClick={() => setThemeChoice(dark ? 'light' : 'dark')}
            >
              <span className="toggle-glyph" aria-hidden="true">
                {dark ? '☾' : '☀'}
              </span>
              <span>{dark ? 'Dark' : 'Light'}</span>
            </button>
            <button
              type="button"
              className="toggle"
              data-testid="toggle-text"
              aria-label={`Text size ${textScale}%. Switch to ${textScale === 100 ? 140 : 100}%`}
              onClick={() => setTextScale((t) => (t === 100 ? 140 : 100))}
            >
              <span className="toggle-glyph" aria-hidden="true">
                Aa
              </span>
              <span>{textScale}%</span>
            </button>
            <button
              type="button"
              className="toggle"
              data-testid="toggle-lang"
              aria-label={`Language ${lang === 'en' ? 'English' : 'Deutsch'}. Switch`}
              onClick={() => setLang((l) => (l === 'en' ? 'de' : 'en'))}
            >
              <span className="toggle-glyph" aria-hidden="true">
                {lang === 'en' ? 'EN' : 'DE'}
              </span>
              <span className="toggle-extra">{lang === 'en' ? 'English' : 'Deutsch'}</span>
            </button>
          </div>
        </div>
        <nav className="modes" aria-label="Option">
          {OPTION_ORDER.map((id) => (
            <button
              key={id}
              type="button"
              className="hx mode-pill"
              data-option={OPTIONS[id].code}
              aria-pressed={option === id}
              onClick={() => setOption(id)}
            >
              <span className="hx-label">
                <b>{OPTIONS[id].code}</b>
                {id !== 'today' && <span className="pill-name"> {OPTIONS[id].name}</span>}
              </span>
            </button>
          ))}
        </nav>
        <div className="sr-fixtures" role="group" aria-label="Fixture">
          <span className="sr-chrome-label">Fixture</span>
          {FIXTURES.map((f) => (
            <button
              key={f.id}
              type="button"
              className="toggle"
              data-fixture={f.id}
              aria-pressed={fixture === f.id}
              title={f.note}
              onClick={() => loadFixture(f.id)}
            >
              <b>{f.code}</b> {f.label}
            </button>
          ))}
          <label className="sr-now">
            <span className="sr-chrome-label">Now</span>
            <select
              aria-label="Mock day"
              value={nowWd}
              onChange={(e) => {
                const w = WEEK.find((x) => x.wd === Number(e.target.value));
                if (w) setNow(wall(2026, 11, w.day, nowMin));
              }}
            >
              {WEEK.map((w) => (
                <option key={w.wd} value={w.wd}>
                  {dateShort('en', wall(2026, 11, w.day, 0))}
                </option>
              ))}
            </select>
            <input
              type="time"
              aria-label="Mock time"
              step={300}
              value={`${String(Math.floor(nowMin / 60)).padStart(2, '0')}:${String(nowMin % 60).padStart(2, '0')}`}
              onChange={(e) => {
                const [h, m] = e.target.value.split(':').map(Number);
                if (h !== undefined && m !== undefined && !Number.isNaN(h) && !Number.isNaN(m)) {
                  setNow(wall(now.getUTCFullYear(), now.getUTCMonth() + 1, now.getUTCDate(), h * 60 + m));
                }
              }}
            />
            <span className="sr-now-tz">Europe/Berlin</span>
          </label>
        </div>
      </header>

      <main className="layout sr-layout">
        <div className="caption">
          <p className="caption-kicker">{option === 'today' ? 'Baseline' : 'Option'}</p>
          <h2 className="caption-title">
            {info.code} · {info.name}
          </h2>
          <p className="sr-slug">
            <code>{info.slug}</code>
          </p>
          <p className="caption-spec">{info.spec}</p>
          <p className="caption-spec">
            <b>Peter’s cases.</b> {info.cases}
          </p>
          <p className="caption-spec sr-fixture-note">
            <b>Fixture {FIXTURES.find((f) => f.id === fixture)?.code}.</b> {FIXTURES.find((f) => f.id === fixture)?.note}{' '}
            Now: {nowLabel}.
          </p>
        </div>

        <section className="playground" aria-label="Interactive prototype">
          <SrPhone
            key={`${option}-${fixture}`}
            option={option}
            lang={lang}
            now={now}
            rules={rules[option]}
            setRules={setOptionRules}
            days={days}
            setDays={setDays}
            onFit={onFit}
          />
          {fit && (
            <p className={overflow > 0 ? 'bar-readout bar-readout--bad' : 'bar-readout'} data-testid="fit-readout" data-content={fit.content} data-viewport={fit.viewport} data-section={fit.section}>
              Content <b>{fit.content} px</b> in a {fit.viewport} px viewport ·{' '}
              {overflow > 0 ? <>scrolls by <b>{overflow} px</b></> : <b>fits</b>} · reminder section {fit.section} px
            </p>
          )}
        </section>

        <aside className="analysis">
          <section className="panel" aria-labelledby="cmp-title">
            <h2 id="cmp-title" className="panel-title">
              Measured
            </h2>
            <p className="panel-lead">
              Taps start on Mitteilungen with no shopping reminders (fixture 1) and end with the reminder saved; the
              second reminder starts from that state. Heights are the Mitteilungen content (below the app bar, above the
              tab bar) in the three-reminder state (fixture 3), phone 390×844, viewport {VIEWPORT} px, no sheet open. All
              numbers come from <code>scripts/verify-sr.mjs</code>, which clicks every path and fails when one drifts.
            </p>
            <div className="table-wrap">
              <table className="cmp-table sr-table" data-testid="measure-table">
                <thead>
                  <tr>
                    <th scope="col">Option</th>
                    <th scope="col">Taps: Sat, day before, 20:00</th>
                    <th scope="col">Taps: + Sat, on the day, 9:15</th>
                    <th scope="col">Reminder section, 100 %</th>
                    <th scope="col">Screen content, 100 % EN</th>
                    <th scope="col">Fits 390×844?</th>
                    <th scope="col">100 % DE</th>
                    <th scope="col">140 % EN</th>
                  </tr>
                </thead>
                <tbody>
                  {recRows.map((id) => {
                    const t = TAPS[id];
                    const h = HEIGHTS[id];
                    const over140 = h.h140 - VIEWPORT;
                    return (
                      <tr key={id} className={id === option ? 'is-current' : undefined} data-row={id}>
                        <th scope="row">
                          {OPTIONS[id].code}
                          <span className="cmp-name">{OPTIONS[id].slug}</span>
                        </th>
                        <td data-taps-first={t.first ?? ''} title={t.path1}>
                          {t.first ?? '–'}
                          <span className="sr-path">{t.path1}</span>
                        </td>
                        <td data-taps-second={t.second ?? ''} title={t.path2}>
                          {t.second ?? '–'}
                          <span className="sr-path">{t.path2}</span>
                        </td>
                        <td data-section100={h.section100}>{h.section100} px</td>
                        <td data-h100={h.h100}>{h.h100} px</td>
                        <td className={h.h100 <= VIEWPORT ? 'is-good' : 'is-bad'}>
                          {h.h100 <= VIEWPORT ? `yes, ${VIEWPORT - h.h100} px spare` : `no, scrolls ${h.h100 - VIEWPORT} px`}
                        </td>
                        <td data-h100de={h.h100de} className={h.h100de <= VIEWPORT ? 'is-good' : 'is-bad'}>
                          {h.h100de} px · {h.h100de <= VIEWPORT ? 'fits' : `scrolls ${h.h100de - VIEWPORT} px`}
                        </td>
                        <td data-h140={h.h140} className={over140 > 0 ? 'is-bad' : 'is-good'}>
                          {h.h140} px · {over140 > 0 ? `scrolls ${over140} px` : 'fits'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          <section className="panel" aria-labelledby="rec-title">
            <h2 id="rec-title" className="panel-title">
              Recommendation
            </h2>
            <Recommendation />
          </section>

          <section className="panel" aria-labelledby="oq-title">
            <h2 id="oq-title" className="panel-title">
              Open questions
            </h2>
            <OpenQuestions />
          </section>

          <section className="panel" aria-labelledby="be-title">
            <h2 id="be-title" className="panel-title">
              Backend and scheduling the build would need (flagged, not in this PR)
            </h2>
            <Backend />
          </section>
        </aside>
      </main>
    </div>
  );
}

function Recommendation() {
  return (
    <ol className="rec-list" data-testid="recommendation">
      <li>
        <b>Pick: SR2 · Week map (week-map).</b> 3 taps for “Saturday, day before, 20:00” and 5 for the second
        Saturday reminder, the fewest of the options that stay compact (reminder section 341 px with three
        reminders). Both Saturday reminders sit under Saturday as two labelled chips, moon “Day before · 20:00” and
        sun “On the day · 9:15”, so the offset and the two-per-day case need no explanation.
      </li>
      <li>
        <b>Runner-up: SR1 · Reminder list + add sheet (reminder-list-sheet).</b> The most compact (297 px; the whole
        screen is 649 px, 6 px over the 643 px viewport) and the most familiar pattern, at one tap more per reminder
        (4 and 6) and with the day repeated in each row.
      </li>
      <li>
        <b>Worth grafting onto SR2.</b> SR3’s three preset times as one-tap chips above SR2’s time grid would make
        Peter’s typical times 3 taps without the custom path (not built or measured here). SR3 itself is the fastest
        (2 and 1 taps) but the tallest (620 px section, screen 972 px); SR4 splits Saturday’s two reminders into two
        rules; SR5 shows the schedule best but costs 404 px and a FAB over the list.
      </li>
      <li>
        <b>Fit at 390×844.</b> With the household-add switches and their hints above (352 px), only Today fits
        (589 px). At 140 % text every option scrolls; SR1 and SR4 least (1003 and 1054 px), SR2 1107 px.
      </li>
    </ol>
  );
}

const QUESTIONS: readonly { id: string; title: string; text: string; dflt: string }[] = [
  {
    id: 'SR-Q1',
    title: 'Per household or per person',
    text: 'Today the weekday row is per person. Shopping times are personal (18:00 vs 20:00). Per household would need: who is notified, who may edit, and what happens when members shop on different days.',
    dflt: 'Keep per person: each person sets and receives their own reminders.',
  },
  {
    id: 'SR-Q2',
    title: 'Server and scheduling',
    text: 'Custom times, “on the day” and several reminders per person need a different shape than one row with a weekday set, one last_sent_on and a cron window at 19:00–19:29 (see the backend panel). The mcp freeze blocks supabase/functions, and this job changes no backend.',
    dflt: 'Flag all of it for a later production job; no backend in this PR. Legal reviews the new fields and copy.',
  },
  {
    id: 'SR-Q3',
    title: 'Default for a new reminder',
    text: 'What the composer starts at before the person changes anything.',
    dflt: 'Day before at 19:00, matching today’s send. Every option here starts there.',
  },
  {
    id: 'SR-Q4',
    title: 'Source of truth',
    text: 'Peter asked to make this “more generic”. A separate shopping-day chip list next to reminders would be two things to keep in step.',
    dflt: 'Reminders are the source of truth; deleting the last one turns the feature off. SR3’s day chips only pick days for the next preset, they store nothing.',
  },
  {
    id: 'SR-Q5',
    title: 'Migrating today’s weekday rows',
    text: 'People who picked days today should keep their reminder.',
    dflt: 'Yes, automatically: each saved weekday becomes one reminder, day before at 19:00; no new opt-in.',
  },
  {
    id: 'SR-Q6',
    title: 'Two reminders on the same day',
    text: 'Saturday day-before 20:00 and Saturday on-the-day 9:15.',
    dflt: 'Both fire; no merging. Exact duplicates (same day, offset and time) are refused with “You already have that reminder”.',
  },
  {
    id: 'SR-Q7',
    title: 'Time already passed when saving',
    text: 'Saved on Saturday at 10:30, “Saturday on the day 9:15” has passed for this week.',
    dflt: 'Skip today; the first firing is the next occurrence (next week). The saved snackbar says so: “First reminder: Sat 5 Dec, 9:15 (today’s 9:15 has passed)”.',
  },
  {
    id: 'SR-Q8',
    title: 'Notification copy',
    text: 'The title names the day, not the time.',
    dflt: 'Day before stays „Morgen ist Einkaufstag“ / “Shopping day tomorrow”; on the day is „Heute ist Einkaufstag“ / “Shopping day today”; body unchanged (open-item count). New copy needs Legal before production.',
  },
  {
    id: 'SR-Q9',
    title: 'Cap',
    text: 'How many reminders one person may have.',
    dflt: '14 (two times on each weekday). At the cap the add control is disabled and a line says why.',
  },
  {
    id: 'SR-Q10',
    title: 'Time picker in Flutter',
    text: 'These prototypes use an hour grid and 5-minute chips (one tap each). Flutter’s showTimePicker dial needs an OK tap and more precision work; a Cupertino wheel needs scrolling.',
    dflt: 'An inline hour + minute chip grid in the composer, 5-minute steps, 24 h in German and the device’s 12/24 h setting in English.',
  },
  {
    id: 'SR-Q11',
    title: '“Day before” for late shoppers',
    text: 'A day-before reminder at 00:15 fires the night before, close to the day itself; the label still says “day before”.',
    dflt: 'Allow any time; the next-firing line shows the real date, so nothing is hidden.',
  },
  {
    id: 'SR-Q12',
    title: 'Push permission',
    text: 'Today the OS prompt comes on the first weekday pick.',
    dflt: 'Ask on the first Save of a reminder (after the person has chosen a time), never on opening the screen; blocked keeps today’s snackbar.',
  },
];

function OpenQuestions() {
  return (
    <ol className="oq-list" data-testid="open-questions">
      {QUESTIONS.map((q) => (
        <li key={q.id}>
          <b>
            {q.id} · {q.title}.
          </b>{' '}
          {q.text} <i>Default:</i> {q.dflt}
        </li>
      ))}
    </ol>
  );
}

function Backend() {
  return (
    <ul className="rec-list sr-backend">
      <li>
        <b>Data shape.</b> Replace the one row per person (<code>shopping_day_reminders</code>: weekdays, zone,
        language, <code>last_sent_on</code>) with one row per reminder: shopping weekday, offset (day before / on the
        day), local time, zone, language and its own <code>last_sent_on</code>. RLS by user as today, plus a pgTAP case.
      </li>
      <li>
        <b>RPCs.</b> <code>set_shopping_day_reminder(p_weekdays…)</code> becomes add / update / delete reminder (or one
        set-all call taking an array), with the cap of 14 enforced on the server. Old app builds keep calling the old
        RPC, so it stays and writes 19:00 day-before rows (squawk compat).
      </li>
      <li>
        <b>Cron.</b> <code>shopping_day_run</code> fires only in the 19:00–19:29 window. It needs to find any reminder
        whose local time fell in the last run interval (every 10 minutes, with a catch-up window), per reminder, across
        DST.
      </li>
      <li>
        <b>Saved after the time.</b> Generalize “saved at or after 19:00 counts as sent” to “saved after this
        reminder’s local time on its firing day counts as sent”.
      </li>
      <li>
        <b>Copy.</b> New on-the-day title „Heute ist Einkaufstag“ / “Shopping day today”; Legal reviews the new fields
        and copy before production.
      </li>
      <li>
        <b>Migration.</b> Each saved weekday becomes one reminder, day before at 19:00 (SR-Q5).
      </li>
      <li>
        <b>Freeze.</b> All of the above touches <code>supabase/</code> (functions, migrations, cron), which the mcp
        freeze blocks; none of it is in this PR.
      </li>
    </ul>
  );
}
