import { useCallback, useEffect, useState, useSyncExternalStore } from 'react';
import { COPY, INITIAL_STATE, STEP_COUNT, toStep } from './data/onboardingSteps';
import type { FinishKind, Lang, OnboardingState, StepNumber } from './data/onboardingSteps';
import { METRICS, MODES, OPTION_IDS, TOUR_STEP_MS } from './data/transitions';
import type { ModeId, NavEvent } from './data/transitions';
import { Icon } from './components/Icons';
import { OnboardingPhone } from './components/OnboardingPhone';
import { HexButton } from './components/OnboardingStepBody';

type ThemeChoice = 'system' | 'light' | 'dark';
type TextScale = 100 | 140;

interface BarReading {
  mode: ModeId;
  y: number | null;
  delta: number | null;
  maxJump: number;
}

const MODE_ORDER: readonly ModeId[] = [...OPTION_IDS, 'today'];
const INITIAL_NAV: NavEvent = { seq: 0, from: null, to: 1, dir: 'fwd', fresh: false, focus: false };
const NOTICE_MS = 2800;

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

export function App() {
  const [mode, setMode] = useState<ModeId>('t1');
  const [reduceToggle, setReduceToggle] = useState(false);
  const [themeChoice, setThemeChoice] = useState<ThemeChoice>('system');
  const [textScale, setTextScale] = useState<TextScale>(100);
  const [lang, setLang] = useState<Lang>('en');
  const [nav, setNav] = useState<NavEvent>(INITIAL_NAV);
  const [ob, setOb] = useState<OnboardingState>(INITIAL_STATE);
  const [done, setDone] = useState<FinishKind | null>(null);
  const [notice, setNotice] = useState<{ id: number; text: string } | null>(null);
  const [touring, setTouring] = useState(false);
  const [bar, setBar] = useState<BarReading>({ mode: 't1', y: null, delta: null, maxJump: 0 });

  const systemReduced = useMediaQuery('(prefers-reduced-motion: reduce)');
  const systemDark = useMediaQuery('(prefers-color-scheme: dark)');
  const reduced = reduceToggle || systemReduced;
  const dark = themeChoice === 'dark' || (themeChoice === 'system' && systemDark);
  const step = nav.to;
  const info = MODES[mode];

  useEffect(() => {
    document.title = 'Snacklist · Onboarding Transitions · T1–T5';
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    if (themeChoice === 'system') root.removeAttribute('data-theme');
    else root.dataset.theme = themeChoice;
    root.dataset.reducedMotion = String(reduced);
    root.dataset.textScale = String(textScale);
  }, [themeChoice, reduced, textScale]);

  useEffect(() => {
    if (!notice) return;
    const t = window.setTimeout(() => setNotice(null), NOTICE_MS);
    return () => window.clearTimeout(t);
  }, [notice]);

  const showNotice = useCallback((text: string) => setNotice({ id: Date.now(), text }), []);

  const go = useCallback((to: StepNumber, focus = false) => {
    setDone(null);
    setNav((n) =>
      n.to === to ? n : { seq: n.seq + 1, from: n.to, to, dir: to > n.to ? 'fwd' : 'back', fresh: false, focus },
    );
  }, []);

  const goManual = useCallback(
    (to: StepNumber, focus = false) => {
      setTouring(false);
      go(to, focus);
    },
    [go],
  );

  // Replay rebuilds N-1 → N from scratch (or Step 1's entrance from nothing), so it always runs.
  const replay = useCallback(() => {
    setTouring(false);
    setDone(null);
    setNav((n) => ({
      seq: n.seq + 1,
      from: n.to > 1 ? toStep(n.to - 1) : null,
      to: n.to,
      dir: 'fwd',
      fresh: true,
      focus: false,
    }));
  }, []);

  const restart = useCallback(() => {
    setTouring(false);
    setOb(INITIAL_STATE);
    go(1);
  }, [go]);

  // Auto-Tour: Step 1's entrance, then 1 → 2 → 3 → 4, one step every TOUR_STEP_MS.
  const toggleTour = () => {
    if (touring) {
      setTouring(false);
      return;
    }
    setDone(null);
    setNav((n) => ({ seq: n.seq + 1, from: null, to: 1, dir: 'fwd', fresh: true, focus: false }));
    setTouring(true);
  };

  useEffect(() => {
    if (!touring) return;
    let reached = 1;
    const id = window.setInterval(() => {
      if (reached >= 4) {
        setTouring(false);
        return;
      }
      reached += 1;
      const to = toStep(reached);
      setNav((n) => ({ seq: n.seq + 1, from: n.to, to, dir: 'fwd', fresh: false, focus: false }));
    }, TOUR_STEP_MS);
    return () => window.clearInterval(id);
  }, [touring]);

  // Arrow keys step, R replays (outside text fields).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) return;
      if (e.key === 'ArrowRight') goManual(toStep(step + 1));
      else if (e.key === 'ArrowLeft') goManual(toStep(step - 1));
      else if (e.key === 'r' || e.key === 'R') replay();
      else return;
      e.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [step, goManual, replay]);

  const onBarMeasure = useCallback((m: ModeId, rawY: number) => {
    const y = Math.round(rawY);
    setBar((prev) => {
      if (prev.mode !== m || prev.y === null) return { mode: m, y, delta: null, maxJump: 0 };
      const delta = y - prev.y;
      return { mode: m, y, delta, maxJump: Math.max(prev.maxJump, Math.abs(delta)) };
    });
  }, []);

  const switchMode = (m: ModeId) => {
    setTouring(false);
    setMode(m);
  };

  const barLive = bar.mode === mode;
  const shift = barLive && bar.delta !== null ? bar.delta : null;
  const shiftText = shift === null ? '–' : `${shift > 0 ? '+' : ''}${shift} px`;
  const barJumped = barLive && bar.maxJump > 0;

  return (
    <div className="app">
      <header className="topbar">
        <div className="topbar-row">
          <div className="topbar-heading">
            <a className="topbar-back" href="/">
              All rounds
            </a>
            <h1 className="topbar-title">
              Onboarding Transitions <span className="topbar-title-sub">· T1–T5</span>
            </h1>
            <p className="topbar-question">How should onboarding move between steps?</p>
          </div>
          <div className="toggles" role="group" aria-label="Display settings">
            <button
              type="button"
              className="toggle"
              aria-pressed={reduced}
              disabled={systemReduced}
              title={systemReduced ? 'Your system asks for reduced motion' : undefined}
              onClick={() => setReduceToggle((v) => !v)}
            >
              <span className="switch" aria-hidden="true" />
              <span>Reduce motion{systemReduced ? ' (system)' : ''}</span>
            </button>
            <button
              type="button"
              className="toggle"
              aria-label={dark ? 'Theme: dark. Switch to light' : 'Theme: light. Switch to dark'}
              onClick={() => setThemeChoice(dark ? 'light' : 'dark')}
            >
              <Icon name={dark ? 'dark_mode' : 'light_mode'} />
              <span>{dark ? 'Dark' : 'Light'}</span>
            </button>
            <button
              type="button"
              className="toggle"
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
        <nav className="modes" aria-label="Transition option">
          {MODE_ORDER.map((id) => {
            const m = MODES[id];
            return (
              <button
                key={id}
                type="button"
                className={id === 'today' ? 'hx mode-pill mode-pill--bug' : 'hx mode-pill'}
                data-option={m.code}
                aria-pressed={mode === id}
                onClick={() => switchMode(id)}
              >
                {id === 'today' ? (
                  <span className="hx-label">{m.pill}</span>
                ) : (
                  <span className="hx-label">
                    <b>{m.code}</b> <span className="pill-name">{m.pill}</span>
                  </span>
                )}
              </button>
            );
          })}
        </nav>
      </header>

      <main className="layout">
        <div className="caption">
          <p className="caption-kicker">{mode === 'today' ? 'Baseline' : 'Option'}</p>
          <h2 className="caption-title">
            {info.code} · {info.name}
          </h2>
          <p className="caption-spec">{info.spec}</p>
          <ul className="caption-dirs">
            <li>
              <Icon name="chevron_right" />
              <span>{info.next}</span>
            </li>
            <li>
              <Icon name="chevron_left" />
              <span>{info.back}</span>
            </li>
          </ul>
          {reduced && mode !== 'today' && (
            <p className="rm-badge" role="status">
              Reduced motion active: zero-displacement fade (120ms)
            </p>
          )}
        </div>

        <section className="playground" aria-label="Interactive prototype">
          <OnboardingPhone
            mode={mode}
            nav={nav}
            reduced={reduced}
            lang={lang}
            state={ob}
            setState={setOb}
            done={done}
            notice={notice}
            onBack={() => goManual(toStep(step - 1), true)}
            onLeave={() => {
              showNotice(COPY[lang].notices.leave);
              restart();
            }}
            onAdvance={() => goManual(toStep(step + 1), true)}
            onFinish={(kind) => {
              setTouring(false);
              setDone(kind);
            }}
            onRestart={restart}
            onNotice={showNotice}
            onBarMeasure={onBarMeasure}
          />

          <div className="transport" role="group" aria-label="Transition controls">
            <div className="transport-row">
              <HexButton
                size="s"
                icon={<Icon name="chevron_left" />}
                disabled={step === 1}
                onClick={() => goManual(toStep(step - 1))}
              >
                Back
              </HexButton>
              <p className="transport-step" aria-live="polite">
                Step <b>{step}</b> / {STEP_COUNT}
              </p>
              <HexButton
                size="s"
                tone="primary"
                className="btn--icon-end"
                icon={<Icon name="chevron_right" />}
                disabled={step === STEP_COUNT}
                onClick={() => goManual(toStep(step + 1))}
              >
                Next
              </HexButton>
            </div>
            <div className="transport-row">
              <HexButton size="s" icon={<Icon name="replay" />} onClick={replay}>
                Replay
              </HexButton>
              <HexButton
                size="s"
                icon={<Icon name={touring ? 'stop' : 'play_arrow'} />}
                aria-pressed={touring}
                onClick={toggleTour}
              >
                {touring ? 'Stop tour' : 'Auto-Tour (1→4)'}
              </HexButton>
            </div>
            <p className={barJumped ? 'bar-readout bar-readout--bad' : 'bar-readout'}>
              Progress bar shift (last step): <b>{shiftText}</b>
              <span className="bar-readout-max">
                {' '}
                · max this session: {barLive ? `${bar.maxJump} px` : '–'}
              </span>
            </p>
          </div>
        </section>

        <aside className="analysis">
          <section className="panel" aria-labelledby="cmp-title">
            <h2 id="cmp-title" className="panel-title">
              Measured comparison
            </h2>
            <p className="panel-lead">
              All five options keep the app bar and progress bar outside the switching region, so the bar moves{' '}
              <b>0 px</b> on every step (the live readout under the phone measures it). Today’s centered column moves it
              ~140–210 px on a full-height phone; in this shorter frame the readout shows a smaller but real jump.
              Timings are design recommendations built on M3 tokens, not benchmarks of other apps.
            </p>
            <div className="table-wrap">
              <table className="cmp-table">
                <thead>
                  <tr>
                    <th scope="col">Criterion</th>
                    {MODE_ORDER.map((id) => (
                      <th key={id} scope="col" className={id === mode ? 'is-current' : undefined}>
                        {MODES[id].code}
                        <span className="cmp-name">{MODES[id].name}</span>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {METRICS.map((metric) => (
                    <tr key={metric.key}>
                      <th scope="row">{metric.label}</th>
                      {MODE_ORDER.map((id) => (
                        <td
                          key={id}
                          className={[
                            id === mode ? 'is-current' : '',
                            metric.key === 'barJump' ? (id === 'today' ? 'is-bad' : 'is-good') : '',
                          ]
                            .filter(Boolean)
                            .join(' ') || undefined}
                        >
                          {MODES[id].metrics[metric.key]}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="cmp-cards">
              {MODE_ORDER.map((id) => (
                <article key={id} className={id === mode ? 'cmp-card is-current' : 'cmp-card'}>
                  <h3 className="cmp-card-title">
                    {MODES[id].code} · {MODES[id].name}
                  </h3>
                  <dl>
                    {METRICS.map((metric) => (
                      <div key={metric.key} className="cmp-card-row">
                        <dt>{metric.label}</dt>
                        <dd
                          className={
                            metric.key === 'barJump' ? (id === 'today' ? 'is-bad' : 'is-good') : undefined
                          }
                        >
                          {MODES[id].metrics[metric.key]}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </article>
              ))}
            </div>
          </section>

          <section className="panel" aria-labelledby="rec-title">
            <h2 id="rec-title" className="panel-title">
              Recommendation
            </h2>
            <ol className="rec-list">
              <li>
                <b>Default: T1 · Shared-Axis Slide.</b> It gives the clearest forward/back model for a linear 7-step
                wizard, finishes in 300 ms (inside the 0.3 s “feels direct” budget), and ships as{' '}
                <code>SharedAxisTransition</code> in the <code>animations</code> package, which is low risk on Flutter
                Web.
              </li>
              <li>
                <b>Runner-up and reduced-motion path: T2 · Fade-Through Stage.</b> Same 300 ms budget with zero
                displacement. When <code>MediaQuery.disableAnimations || MediaQuery.reduceMotion</code> is set, T1 drops
                to a 120 ms dissolve and the progress fill tweens without overshoot.
              </li>
              <li>
                <b>Not the default: T3 · Morphing Card.</b> It is the most cohesive on chip steps (2, 4 and 5), but on
                Steps 3 and 5 the height animation fights the keyboard’s viewport resize and moves the CTA. T4 is
                keyboard-friendly, but Back reads oddly. T5 is the most tactile, but bounce on the consent and account
                steps feels wrong, and it needs a full alternate path under Reduce Motion.
              </li>
              <li>
                <b>Fix regardless of option:</b> move the app bar and progress bar out of the centered{' '}
                <code>ListView(shrinkWrap: true)</code>, top-align the body in an <code>Expanded</code> region, and key
                only the body.
              </li>
            </ol>
            <pre className="code">
              <code>{FLUTTER_SNIPPET}</code>
            </pre>
          </section>

          <section className="panel" aria-labelledby="oq-title">
            <h2 id="oq-title" className="panel-title">
              Open questions
            </h2>
            <ol className="oq-list">
              <li>
                <b>OB-Q1 · Keyboard on Steps 3 and 5.</b> Should Continue dismiss the keyboard before the step
                transition? <i>Default:</i> yes. Unfocus on Continue, start T1 in the same frame, and never autofocus the
                next step’s field, including on Back.
              </li>
              <li>
                <b>OB-Q2 · Back gesture.</b> Should an iOS edge swipe scrub T1 interactively?{' '}
                <i>Default:</i> no for v1. Back (button, Android system back, iOS swipe) runs the mirrored 300 ms
                transition; revisit after device testing.
              </li>
              <li>
                <b>OB-Q3 · Which flags mean “reduce”?</b> <i>Default:</i> honor both{' '}
                <code>disableAnimations</code> (Android “Remove animations”) and <code>reduceMotion</code> (iOS) with
                the 120 ms dissolve, keep the progress fill moving (120 ms, linear), and move focus to the new step
                heading.
              </li>
            </ol>
          </section>
        </aside>
      </main>
    </div>
  );
}

const FLUTTER_SNIPPET = `final reduce = mq.disableAnimations || mq.reduceMotion;

Column(children: [
  OnboardingAppBar(step: step),   // fixed, never re-mounts
  OnboardingProgress(step: step), // fixed, fill tweens 300 ms
  Expanded(
    child: PageTransitionSwitcher(
      reverse: isBack,
      duration: Duration(milliseconds: reduce ? 120 : 300),
      transitionBuilder: (child, primary, secondary) => reduce
          ? FadeTransition(opacity: primary, child: child)
          : SharedAxisTransition(
              animation: primary,
              secondaryAnimation: secondary,
              transitionType: SharedAxisTransitionType.horizontal,
              child: child,
            ),
      child: KeyedSubtree(key: ValueKey(step), child: stepBody(step)),
    ),
  ),
]);`;
