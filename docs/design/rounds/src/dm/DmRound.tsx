import { useEffect, useState } from 'react';
import { FIXTURES, SCENARIOS } from './data';
import type { Fixture, Lang } from './data';
import { MEASURED, QUESTIONS, RECOMMENDATION } from './meta';
import { OPTIONS, OPTION_ORDER } from './options';
import type { OptionId } from './options';
import { MOMENTS, Phone } from './Phone';
import type { Moment } from './Phone';
import './dm.css';

type Theme = 'light' | 'dark';
const SCALES = ['100', '200', '310'] as const;
type Scale = (typeof SCALES)[number];
const KB = ['on', 'off'] as const;
type Kb = (typeof KB)[number];

const MOMENT_LABEL: Record<Moment, string> = {
  closed: 'List',
  typing: 'Match typed',
  after: 'After Enter',
};

function param<T extends string>(name: string, allowed: readonly T[], fallback: T): T {
  const v = new URLSearchParams(window.location.search).get(name);
  return allowed.find((a) => a === v) ?? fallback;
}

function Pills<T extends string>({ label, value, options, onChange, render }: { label: string; value: T; options: readonly T[]; onChange: (v: T) => void; render?: (v: T) => string }) {
  return (
    <div className="dm-pills" role="radiogroup" aria-label={label}>
      <span className="dm-pills-label">{label}</span>
      {options.map((o) => (
        <button key={o} type="button" role="radio" aria-checked={o === value} className={o === value ? 'on' : ''} onClick={() => onChange(o)}>
          {render ? render(o) : o}
        </button>
      ))}
    </div>
  );
}

export function DmRound() {
  const [option, setOption] = useState<OptionId>(() => param('o', OPTION_ORDER, 'dm1'));
  const [fixture, setFixture] = useState<Fixture>(() => param('f', FIXTURES, 'exact'));
  const [moment, setMoment] = useState<Moment>(() => param('m', MOMENTS, 'typing'));
  const [kb, setKb] = useState<Kb>(() => param('kb', KB, 'off'));
  const [theme, setTheme] = useState<Theme>(() => param('theme', ['light', 'dark'] as const, 'light'));
  const [scale, setScale] = useState<Scale>(() => param('text', SCALES, '100'));
  const [lang, setLang] = useState<Lang>(() => param('lang', ['de', 'en'] as const, 'de'));
  const info = OPTIONS[option];

  useEffect(() => {
    document.title = 'Snacklist · Add, merge, tick off · DM1–DM5';
    document.documentElement.lang = lang;
  }, [lang]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    const q = new URLSearchParams({ o: option, f: fixture, m: moment, kb, theme, text: scale, lang });
    window.history.replaceState(null, '', `${window.location.pathname}?${q}`);
  }, [option, fixture, moment, kb, theme, scale, lang]);

  useEffect(() => {
    const w = window as unknown as { dm?: unknown };
    w.dm = {
      set: (s: { o?: OptionId; f?: Fixture; m?: Moment; kb?: Kb; theme?: Theme; text?: Scale; lang?: Lang }) => {
        if (s.o) setOption(s.o);
        if (s.f) setFixture(s.f);
        if (s.m) setMoment(s.m);
        if (s.kb) setKb(s.kb);
        if (s.theme) setTheme(s.theme);
        if (s.text) setScale(s.text);
        if (s.lang) setLang(s.lang);
      },
    };
  }, []);

  const phones: OptionId[] = option === 'today' ? ['today'] : ['today', option];

  return (
    <div className="dm-page">
      <header className="dm-hero">
        <p className="dm-kicker">
          <a href="/">Snacklist prototype rounds</a> · Round DM · 28 November 2026
        </p>
        <h1>Add, merge, tick off</h1>
        <p className="dm-q">
          Peter: “I didn’t even understand that the check-mark ticks off.” When the typed text matches an item already on the list, how should the add sheet say what adding, merging and ticking off each do, and how they relate to the list, so people of any technical affinity can tell?
        </p>
      </header>

      <div className="dm-controls">
        <Pills label="Option" value={option} options={OPTION_ORDER} onChange={setOption} render={(o) => OPTIONS[o].code} />
        <Pills label="Scenario" value={fixture} options={FIXTURES} onChange={setFixture} render={(f) => SCENARIOS[f].label} />
        <Pills label="Moment" value={moment} options={MOMENTS} onChange={setMoment} render={(m) => MOMENT_LABEL[m]} />
        <Pills label="Keyboard" value={kb} options={KB} onChange={setKb} render={(k) => (k === 'on' ? 'Shown' : 'Hidden')} />
        <Pills label="Theme" value={theme} options={['light', 'dark'] as const} onChange={setTheme} render={(t) => (t === 'light' ? 'Light' : 'Dark')} />
        <Pills label="Text" value={scale} options={SCALES} onChange={setScale} render={(s) => `${s} %`} />
        <Pills label="Language" value={lang} options={['de', 'en'] as const} onChange={setLang} render={(l) => l.toUpperCase()} />
      </div>

      <section className="dm-option" aria-live="polite">
        <h2>
          <span className="dm-code">{info.code}</span> {info.name[lang]} <code>{info.slug}</code>
        </h2>
        <p>{info.line[lang]}</p>
        <p className="dm-tip">
          The phones are live: tap the add bar, type (try “Omega 3”, “Omega 3 2”, “Mehl”, “Mehl 1kg”, “Bananen”) and tap an action or press Enter; the list updates. Tap the list or the handle to close. “Scenario” replays a typed line against the mock list; “Moment” shows the list, the match typed, or the result of Enter. Today is always shown next to the chosen option. The page controls stay English; the phone follows the language.
        </p>
      </section>

      <div className="dm-stage">
        {phones.map((o) => (
          <div className="dm-phone-wrap" key={o}>
            <span className="dm-phone-label">
              {OPTIONS[o].code} · {OPTIONS[o].name[lang]}
            </span>
            <div className="dm-phone" data-testid={`phone-${o}`} style={{ ['--ts' as string]: Number(scale) / 100 }}>
              <Phone key={`${o}-${fixture}-${moment}-${kb}-${lang}`} option={o} fixture={fixture} lang={lang} keyboard={kb === 'on'} moment={moment} />
            </div>
          </div>
        ))}
      </div>

      <section className="dm-measure">
        <h2>Measured</h2>
        <p>{MEASURED.method}</p>
        <div className="dm-table-wrap">
          <table data-testid="dm-table">
            <thead>
              <tr>
                {MEASURED.columns.map((col) => (
                  <th key={col}>{col}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {MEASURED.rows.map((r) => (
                <tr key={r[0]} className={r[0] === info.code ? 'dm-tr-on' : ''}>
                  {r.map((cell, i) => (
                    <td key={i}>{cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {MEASURED.notes.map((n) => (
          <p key={n} className="dm-fnote">
            {n}
          </p>
        ))}
      </section>

      <section className="dm-rec">
        <h2>Recommendation</h2>
        {RECOMMENDATION[lang].map((p) => (
          <p key={p}>{p}</p>
        ))}
      </section>

      <section className="dm-questions">
        <h2>Open questions</h2>
        <ol>
          {QUESTIONS.map((q) => (
            <li key={q.id}>
              <b>{q.id}</b> {q[lang]} <span className="dm-default">[{q.default[lang]}]</span>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
