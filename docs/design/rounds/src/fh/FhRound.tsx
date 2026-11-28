import { useEffect, useState } from 'react';
import { Icon } from '../components/Icons';
import { COPY } from './copy';
import type { Lang } from './copy';
import { MEASURED, QUESTIONS, RECOMMENDATION } from './meta';
import { OPTIONS, OPTION_ORDER } from './options';
import type { OptionId } from './options';
import { Painted } from './Painted';
import type { PaintCtx } from './Painted';
import { ListScreen, OnboardingStores, TARGETS, TARGET_LABEL } from './Screens';
import type { Target } from './Screens';
import type { Look } from './shape';
import './fh.css';

type Theme = 'light' | 'dark';
const SCALES = ['100', '200', '310'] as const;
type Scale = (typeof SCALES)[number];

function param<T extends string>(name: string, allowed: readonly T[], fallback: T): T {
  const v = new URLSearchParams(window.location.search).get(name);
  return allowed.find((a) => a === v) ?? fallback;
}

function Pills<T extends string>({ label, value, options, onChange, render }: { label: string; value: T; options: readonly T[]; onChange: (v: T) => void; render?: (v: T) => string }) {
  return (
    <div className="fh-pills" role="radiogroup" aria-label={label}>
      <span className="fh-pills-label">{label}</span>
      {options.map((o) => (
        <button key={o} type="button" role="radio" aria-checked={o === value} className={o === value ? 'on' : ''} onClick={() => onChange(o)}>
          {render ? render(o) : o}
        </button>
      ))}
    </div>
  );
}

function Specimens({ ctx, lang }: { ctx: PaintCtx; lang: Lang }) {
  const c = COPY[lang];
  const gap = OPTIONS[ctx.option].spacing.chips;
  return (
    <div className="fh-specimens" data-testid="specimens">
      <div className="fh-spec-line" style={{ gap }}>
        <Painted ctx={ctx} kind="chip" contourWidth={1} forcedFocus testId="spec-chip-on" className="fh-chip">
          <span className="fh-chip-label">REWE</span>
        </Painted>
        <Painted ctx={ctx} kind="chip" contourWidth={1} forcedFocus={false} testId="spec-chip-off" className="fh-chip">
          <span className="fh-chip-label">PENNY</span>
        </Painted>
        <Painted ctx={ctx} kind="chip" contourWidth={1} honey face="honey" forcedFocus testId="spec-picked-on" className="fh-chip">
          <Icon name="check" />
          <span className="fh-chip-label">EDEKA</span>
        </Painted>
        <Painted ctx={ctx} kind="chip" contourWidth={1} honey face="honey" forcedFocus={false} testId="spec-picked-off" className="fh-chip">
          <Icon name="check" />
          <span className="fh-chip-label">Lidl</span>
        </Painted>
      </div>
      <div className="fh-spec-stack" style={{ gap: OPTIONS[ctx.option].spacing.stack }}>
        <Painted ctx={ctx} kind="field" forcedFocus testId="spec-field-on" className="fh-field">
          <input aria-label={c.storeName} placeholder={c.storeName} defaultValue="Hofladen" />
        </Painted>
        <Painted ctx={ctx} kind="field" forcedFocus={false} testId="spec-field-off" className="fh-field">
          <input aria-label={c.storeName} placeholder={c.storeName} />
        </Painted>
        <Painted ctx={ctx} kind="button" honey face="honey" contour="edge" edge="honey-edge" forcedFocus testId="spec-btn-on" className="fh-btn">
          <span>{c.next}</span>
        </Painted>
        <Painted ctx={ctx} kind="button" face="surface-raised" contour="border" edge="surface-edge" forcedFocus={false} testId="spec-btn-off" className="fh-btn">
          <span>{c.skip}</span>
        </Painted>
      </div>
      <div className="fh-spec-line" style={{ gap }}>
        <Painted ctx={ctx} kind="textButton" face={null} contour={null} forcedFocus testId="spec-text-on" className="fh-textbtn">
          <Icon name="add" />
          <span>{c.addOwn}</span>
        </Painted>
      </div>
      <div className="fh-rows fh-spec-rows">
        {c.rows.slice(0, 3).map((r, i) => (
          <Painted key={r.name} ctx={ctx} kind="row" face="surface" contour={null} forcedFocus={i === 1} testId={`spec-row-${i}`} className="fh-row">
            <span className="fh-row-icon" data-deco aria-hidden="true" />
            <span className="fh-row-text">
              <span className="fh-row-name">{r.name}</span>
            </span>
            {i < 2 && <span className="fh-row-rule" data-deco aria-hidden="true" />}
          </Painted>
        ))}
      </div>
    </div>
  );
}

export function FhRound() {
  const [option, setOption] = useState<OptionId>(() => param('o', OPTION_ORDER, 'today'));
  const [theme, setTheme] = useState<Theme>(() => param('theme', ['light', 'dark'] as const, 'light'));
  const [look, setLook] = useState<Look>(() => param('look', ['soft', 'hex'] as const, 'soft'));
  const [scale, setScale] = useState<Scale>(() => param('text', SCALES, '100'));
  const [lang, setLang] = useState<Lang>(() => param('lang', ['en', 'de'] as const, 'en'));
  const [target, setTarget] = useState<Target>(() => param('f', ['none', ...TARGETS] as const, 'field'));
  const [open, setOpen] = useState(() => param('open', ['0', '1'] as const, '0') === '1');
  const ctx: PaintCtx = { option, look };
  const info = OPTIONS[option];

  useEffect(() => {
    document.title = 'Snacklist · Focus highlight · FH1–FH5';
    document.documentElement.lang = lang;
  }, [lang]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    const q = new URLSearchParams({ o: option, theme, look, text: scale, lang, f: target });
    window.history.replaceState(null, '', `${window.location.pathname}?${q}`);
  }, [option, theme, look, scale, lang, target]);

  useEffect(() => {
    const w = window as unknown as { fh?: unknown };
    w.fh = {
      set: (s: { o?: OptionId; theme?: Theme; look?: Look; text?: Scale; lang?: Lang; f?: Target; open?: boolean }) => {
        if (s.o) setOption(s.o);
        if (s.theme) setTheme(s.theme);
        if (s.look) setLook(s.look);
        if (s.text) setScale(s.text);
        if (s.lang) setLang(s.lang);
        if (s.f) setTarget(s.f);
        if (s.open !== undefined) setOpen(s.open);
      },
    };
  }, []);

  const key = `${option}-${look}-${lang}`;

  return (
    <div className="fh-page">
      <header className="fh-hero">
        <p className="fh-kicker">
          <a href="/">Snacklist prototype rounds</a> · Round FH · 27 November 2026
        </p>
        <h1>Focus highlight</h1>
        <p className="fh-q">
          How should Snacklist show the focused element (keyboard, switch or screen-reader focus, and the active text field) without the ring making the spacing to its neighbours look off?
        </p>
      </header>

      <div className="fh-controls">
        <Pills label="Option" value={option} options={OPTION_ORDER} onChange={setOption} render={(o) => OPTIONS[o].code} />
        <Pills label="Focused" value={target} options={['none', ...TARGETS] as const} onChange={setTarget} render={(t) => TARGET_LABEL[t]} />
        <Pills label="Theme" value={theme} options={['light', 'dark'] as const} onChange={setTheme} render={(t) => (t === 'light' ? 'Light' : 'Dark')} />
        <Pills label="Shapes" value={look} options={['soft', 'hex'] as const} onChange={setLook} render={(l) => (l === 'soft' ? 'Soft (live, RD1)' : 'Hexagon')} />
        <Pills label="Text" value={scale} options={SCALES} onChange={setScale} render={(s) => `${s} %`} />
        <Pills label="Language" value={lang} options={['en', 'de'] as const} onChange={setLang} render={(l) => l.toUpperCase()} />
      </div>

      <section className="fh-option" aria-live="polite">
        <h2>
          <span className="fh-code">{info.code}</span> {info.name[lang]} <code>{info.slug}</code>
        </h2>
        <p>{info.line[lang]}</p>
        <p className="fh-tip">Press Tab inside a phone to move the real keyboard focus; the “Focused” pills force one element. At 200 and 310 % the step scrolls inside the phone: scroll down to the field, or see the sheet on the right.</p>
      </section>

      <div className="fh-stage">
        <div className="fh-phone" data-testid="phone-stores" style={{ ['--ts' as string]: Number(scale) / 100 }}>
          <OnboardingStores key={key} ctx={ctx} lang={lang} target={target} fieldOpen={open} />
        </div>
        <div className="fh-phone" data-testid="phone-list" style={{ ['--ts' as string]: Number(scale) / 100 }}>
          <ListScreen key={key} ctx={ctx} lang={lang} target={target} />
        </div>
        <div className="fh-sheet" style={{ ['--ts' as string]: Number(scale) / 100 }}>
          <h3>Every control, focused next to unfocused</h3>
          <Specimens key={key} ctx={ctx} lang={lang} />
        </div>
      </div>

      <section className="fh-measure">
        <h2>Measured</h2>
        <p>{MEASURED.method}</p>
        <div className="fh-table-wrap">
          <table>
            <thead>
              <tr>
                {MEASURED.columns.map((col) => (
                  <th key={col}>{col}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {MEASURED.rows.map((r) => (
                <tr key={r[0]}>
                  {r.map((cell, i) => (
                    <td key={i}>{cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {MEASURED.notes.map((n) => (
          <p key={n} className="fh-note">
            {n}
          </p>
        ))}
      </section>

      <section className="fh-rec">
        <h2>Recommendation</h2>
        {RECOMMENDATION[lang].map((p) => (
          <p key={p}>{p}</p>
        ))}
      </section>

      <section className="fh-questions">
        <h2>Open questions</h2>
        <ol>
          {QUESTIONS.map((q) => (
            <li key={q.id}>
              <b>{q.id}</b> {q[lang]} <span className="fh-default">[{q.default[lang]}]</span>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
