import { useEffect, useState } from 'react';
import { FIXTURES, FIXTURE_LABEL } from './data';
import type { Fixture, Lang } from './data';
import { MEASURED, QUESTIONS, RECOMMENDATION } from './meta';
import { OPTIONS, OPTION_ORDER } from './options';
import type { OptionId } from './options';
import { MOMENTS, Phone } from './Phone';
import type { Moment } from './Phone';
import './ae.css';

type Theme = 'light' | 'dark';
const SCALES = ['100', '200', '310'] as const;
type Scale = (typeof SCALES)[number];
const KB = ['on', 'off'] as const;
type Kb = (typeof KB)[number];

const MOMENT_LABEL: Record<Moment, string> = {
  closed: 'List',
  open: 'Add opened',
  typing: 'Typing',
  added: 'After 2 adds',
};

function param<T extends string>(name: string, allowed: readonly T[], fallback: T): T {
  const v = new URLSearchParams(window.location.search).get(name);
  return allowed.find((a) => a === v) ?? fallback;
}

function Pills<T extends string>({ label, value, options, onChange, render }: { label: string; value: T; options: readonly T[]; onChange: (v: T) => void; render?: (v: T) => string }) {
  return (
    <div className="ae-pills" role="radiogroup" aria-label={label}>
      <span className="ae-pills-label">{label}</span>
      {options.map((o) => (
        <button key={o} type="button" role="radio" aria-checked={o === value} className={o === value ? 'on' : ''} onClick={() => onChange(o)}>
          {render ? render(o) : o}
        </button>
      ))}
    </div>
  );
}

export function AeRound() {
  const [option, setOption] = useState<OptionId>(() => param('o', OPTION_ORDER, 'ae2'));
  const [fixture, setFixture] = useState<Fixture>(() => param('f', FIXTURES, 'many'));
  const [moment, setMoment] = useState<Moment>(() => param('m', MOMENTS, 'open'));
  const [kb, setKb] = useState<Kb>(() => param('kb', KB, 'on'));
  const [theme, setTheme] = useState<Theme>(() => param('theme', ['light', 'dark'] as const, 'light'));
  const [scale, setScale] = useState<Scale>(() => param('text', SCALES, '100'));
  const [lang, setLang] = useState<Lang>(() => param('lang', ['en', 'de'] as const, 'en'));
  const info = OPTIONS[option];

  useEffect(() => {
    document.title = 'Snacklist · Adding with the list in view · AE1–AE5';
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
    const w = window as unknown as { ae?: unknown };
    w.ae = {
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
    <div className="ae-page">
      <header className="ae-hero">
        <p className="ae-kicker">
          <a href="/">Snacklist prototype rounds</a> · Round AE · 27 November 2026
        </p>
        <h1>Adding, with the list in view</h1>
        <p className="ae-q">
          A user found it confusing that the list is empty while adding. How should the add state show what is happening and how the add sheet relates to the list: that the list is still there, where a new item lands, and what happens to an item already on the list?
        </p>
      </header>

      <div className="ae-controls">
        <Pills label="Option" value={option} options={OPTION_ORDER} onChange={setOption} render={(o) => OPTIONS[o].code} />
        <Pills label="List" value={fixture} options={FIXTURES} onChange={setFixture} render={(f) => FIXTURE_LABEL[f]} />
        <Pills label="Moment" value={moment} options={MOMENTS} onChange={setMoment} render={(m) => MOMENT_LABEL[m]} />
        <Pills label="Keyboard" value={kb} options={KB} onChange={setKb} render={(k) => (k === 'on' ? 'Shown' : 'Hidden')} />
        <Pills label="Theme" value={theme} options={['light', 'dark'] as const} onChange={setTheme} render={(t) => (t === 'light' ? 'Light' : 'Dark')} />
        <Pills label="Text" value={scale} options={SCALES} onChange={setScale} render={(s) => `${s} %`} />
        <Pills label="Language" value={lang} options={['en', 'de'] as const} onChange={setLang} render={(l) => l.toUpperCase()} />
      </div>

      <section className="ae-option" aria-live="polite">
        <h2>
          <span className="ae-code">{info.code}</span> {info.name[lang]} <code>{info.slug}</code>
        </h2>
        <p>{info.line[lang]}</p>
        <p className="ae-tip">
          The phones are live: tap the add bar, type (or tap the keyboard in the phone) and send; tap a suggestion; send an empty field or tap the handle to close. “Moment” replays a scripted state. Typed in the fixtures: “Milk” / “Milch”, then Milk and Eggs (Milch, Eier); with “Already on the list”, Bananas (Bananen), which is on the list as 6×.
        </p>
      </section>

      <div className="ae-stage">
        {phones.map((o) => (
          <div className="ae-phone-wrap" key={o}>
            <span className="ae-phone-label">
              {OPTIONS[o].code} · {OPTIONS[o].name[lang]}
            </span>
            <div className="ae-phone" data-testid={`phone-${o}`} style={{ ['--ts' as string]: Number(scale) / 100 }}>
              <Phone key={`${o}-${fixture}-${moment}-${kb}-${lang}`} option={o} fixture={fixture} lang={lang} keyboard={kb === 'on'} moment={moment} />
            </div>
          </div>
        ))}
      </div>

      <section className="ae-measure">
        <h2>Measured</h2>
        <p>{MEASURED.method}</p>
        <div className="ae-table-wrap">
          <table data-testid="ae-table">
            <thead>
              <tr>
                {MEASURED.columns.map((col) => (
                  <th key={col}>{col}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {MEASURED.rows.map((r) => (
                <tr key={r[0]} className={r[0] === info.code ? 'ae-tr-on' : ''}>
                  {r.map((cell, i) => (
                    <td key={i}>{cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {MEASURED.notes.map((n) => (
          <p key={n} className="ae-fnote">
            {n}
          </p>
        ))}
      </section>

      <section className="ae-rec">
        <h2>Recommendation</h2>
        {RECOMMENDATION[lang].map((p) => (
          <p key={p}>{p}</p>
        ))}
      </section>

      <section className="ae-questions">
        <h2>Open questions</h2>
        <ol>
          {QUESTIONS.map((q) => (
            <li key={q.id}>
              <b>{q.id}</b> {q[lang]} <span className="ae-default">[{q.default[lang]}]</span>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
