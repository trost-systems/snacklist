// The phone: a fixed app bar and progress bar on top, and a stage below in which only the
// step body transitions. "Today" reproduces the bug: bar + body in a centered column.

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { Dispatch, ReactNode, Ref, SetStateAction } from 'react';
import { COPY, STEP_COUNT } from '../data/onboardingSteps';
import type { FinishKind, Lang, OnboardingState, StepNumber } from '../data/onboardingSteps';
import { MODES, REDUCED_MOTION_MS } from '../data/transitions';
import type { Direction, ModeId, NavEvent, OptionId } from '../data/transitions';
import { Icon } from './Icons';
import { HexButton, OnboardingStepBody } from './OnboardingStepBody';

/* ---------- Fixed chrome ---------- */

function AppBar({ step, lang, onBack, onLeave }: { step: StepNumber; lang: Lang; onBack: () => void; onLeave: () => void }) {
  const c = COPY[lang];
  return (
    <header className="ob-appbar">
      {step > 1 ? (
        <button type="button" className="icon-btn" aria-label={c.back} title={c.back} onClick={onBack}>
          <Icon name="arrow_back" />
        </button>
      ) : (
        <span className="icon-btn-spacer" />
      )}
      <p className="ob-appbar-title">{c.stepOf(step, STEP_COUNT)}</p>
      {step < STEP_COUNT ? (
        <button type="button" className="icon-btn" aria-label={c.leaveSetup} title={c.leaveSetup} onClick={onLeave}>
          <Icon name="close" />
        </button>
      ) : (
        <span className="icon-btn-spacer" />
      )}
    </header>
  );
}

function ProgressBar({ step, lang, ref }: { step: StepNumber; lang: Lang; ref?: Ref<HTMLDivElement> }) {
  return (
    <div className="ob-progress" ref={ref}>
      <div
        className="ob-progress-track"
        role="progressbar"
        aria-label={COPY[lang].progress}
        aria-valuemin={1}
        aria-valuemax={STEP_COUNT}
        aria-valuenow={step}
      >
        <div className="ob-progress-fill" style={{ transform: `scaleX(${step / STEP_COUNT})` }} />
      </div>
      <span className="ob-progress-count">
        {step} / {STEP_COUNT}
      </span>
    </div>
  );
}

/* ---------- Transition engine ---------- */

// A layer is one rendered step. `enter` and `hold` are the start states (incoming and the
// replayed outgoing step), `active` is at rest, `exit` is leaving. Moving between states is
// a plain CSS transition, so a new tap mid-flight retargets from wherever the layer is.
type Phase = 'enter' | 'hold' | 'active' | 'exit';

interface Layer {
  id: number;
  step: StepNumber;
  phase: Phase;
  dir: Direction;
  /** Navigation seq after which this layer may be removed (set when it starts leaving). */
  leaveSeq: number | null;
}

interface StageProps {
  option: OptionId;
  nav: NavEvent;
  reduced: boolean;
  renderStep: (step: StepNumber) => ReactNode;
}

const REMOVE_SLACK_MS = 80;

function TransitionStage({ option, nav, reduced, renderStep }: StageProps) {
  const [layers, setLayers] = useState<Layer[]>(() => [
    { id: 0, step: nav.to, phase: 'active', dir: nav.dir, leaveSeq: null },
  ]);
  const nextId = useRef(1);
  const handledSeq = useRef(nav.seq);
  const stageRef = useRef<HTMLDivElement>(null);
  const pending = useRef<{ frames: Set<number>; timers: Set<number> }>({ frames: new Set(), timers: new Set() });
  const settleMs = reduced ? REDUCED_MOTION_MS : MODES[option].settleMs;

  useLayoutEffect(() => {
    if (nav.seq === handledSeq.current) return;
    handledSeq.current = nav.seq;
    const { seq, to, dir, focus } = nav;
    const incomingId = nextId.current++;
    const replayFrom = nav.fresh ? nav.from : null;
    const holdId = replayFrom !== null ? nextId.current++ : null;

    // Runs before paint: the incoming layer is first painted in its start state.
    setLayers((prev) => {
      let outgoing: Layer[];
      if (nav.fresh) {
        outgoing =
          replayFrom !== null && holdId !== null
            ? [{ id: holdId, step: replayFrom, phase: 'hold', dir, leaveSeq: seq }]
            : [];
      } else {
        // Keep at most two leaving layers when someone taps very fast.
        outgoing = prev
          .map((l): Layer => (l.phase === 'exit' ? l : { ...l, phase: 'exit', dir, leaveSeq: seq }))
          .slice(-2);
      }
      return [...outgoing, { id: incomingId, step: to, phase: 'enter', dir, leaveSeq: null }];
    });

    const { frames, timers } = pending.current;
    const frame = (fn: () => void) => {
      const id = requestAnimationFrame(() => {
        frames.delete(id);
        fn();
      });
      frames.add(id);
    };
    // Two frames guarantee the start state was styled before we flip to the end state.
    frame(() =>
      frame(() => {
        setLayers((ls) =>
          ls.map((l) => {
            if (l.id === incomingId && l.phase === 'enter') return { ...l, phase: 'active' };
            if (l.phase === 'hold') return { ...l, phase: 'exit' };
            return l;
          }),
        );
        if (focus) {
          frame(() => {
            stageRef.current
              ?.querySelector<HTMLElement>(`[data-layer-id="${incomingId}"] [data-step-heading]`)
              ?.focus({ preventScroll: true });
          });
        }
      }),
    );
    const timer = window.setTimeout(() => {
      timers.delete(timer);
      setLayers((ls) => ls.filter((l) => l.leaveSeq === null || l.leaveSeq > seq));
    }, settleMs + REMOVE_SLACK_MS);
    timers.add(timer);
  }, [nav, settleMs]);

  useEffect(() => {
    const { frames, timers } = pending.current;
    return () => {
      frames.forEach((id) => cancelAnimationFrame(id));
      timers.forEach((id) => window.clearTimeout(id));
    };
  }, []);

  const renderLayer = (layer: Layer) => (
    <div
      key={layer.id}
      className="ob-layer"
      data-layer-id={layer.id}
      data-phase={layer.phase}
      data-dir={layer.dir}
      inert={layer.phase === 'exit' || layer.phase === 'hold'}
      aria-hidden={layer.phase === 'exit' || layer.phase === 'hold' ? true : undefined}
    >
      {renderStep(layer.step)}
    </div>
  );

  return (
    <div className="ob-stage" data-t={option} ref={stageRef}>
      {option === 't3' ? (
        <MorphCard currentId={layers[layers.length - 1]?.id ?? 0}>{layers.map(renderLayer)}</MorphCard>
      ) : (
        layers.map(renderLayer)
      )}
    </div>
  );
}

/**
 * T3's single persistent card. Its height follows the newest layer through a ResizeObserver
 * (no per-frame reads), so it also animates when content grows inside a step, e.g. "Other".
 */
function MorphCard({ currentId, children }: { currentId: number; children: ReactNode }) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState<number | null>(null);

  useLayoutEffect(() => {
    const el = cardRef.current?.querySelector<HTMLElement>(`:scope > [data-layer-id="${currentId}"]`);
    if (!el) return;
    setHeight(el.offsetHeight);
    const ro = new ResizeObserver((entries) => {
      const box = entries[0]?.borderBoxSize[0];
      setHeight(Math.ceil(box ? box.blockSize : el.offsetHeight));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [currentId]);

  return (
    <div
      className="morph-card"
      ref={cardRef}
      style={height === null ? undefined : { height: `calc(${height}px + 2 * var(--hl-border-width))` }}
    >
      {children}
    </div>
  );
}

/* ---------- Phone ---------- */

export interface OnboardingPhoneProps {
  mode: ModeId;
  nav: NavEvent;
  reduced: boolean;
  lang: Lang;
  state: OnboardingState;
  setState: Dispatch<SetStateAction<OnboardingState>>;
  done: FinishKind | null;
  notice: { id: number; text: string } | null;
  onBack: () => void;
  onLeave: () => void;
  onAdvance: () => void;
  onFinish: (kind: FinishKind) => void;
  onRestart: () => void;
  onNotice: (text: string) => void;
  onBarMeasure: (mode: ModeId, y: number) => void;
}

export function OnboardingPhone(props: OnboardingPhoneProps) {
  const { mode, nav, reduced, lang, state, setState, done, notice } = props;
  const { onBack, onLeave, onAdvance, onFinish, onRestart, onNotice, onBarMeasure } = props;
  const step = nav.to;
  const screenRef = useRef<HTMLDivElement>(null);
  const barRef = useRef<HTMLDivElement>(null);

  // Measure where the progress bar sits after every navigation: the number the bug is about.
  useLayoutEffect(() => {
    const screen = screenRef.current;
    const bar = barRef.current;
    if (!screen || !bar) return;
    onBarMeasure(mode, bar.getBoundingClientRect().top - screen.getBoundingClientRect().top);
  }, [mode, nav.seq, onBarMeasure]);

  const renderStep = (s: StepNumber) => (
    <OnboardingStepBody
      step={s}
      lang={lang}
      state={state}
      setState={setState}
      onAdvance={onAdvance}
      onFinish={onFinish}
      onNotice={onNotice}
    />
  );

  const c = COPY[lang];
  return (
    <div className="phone" data-mode={mode}>
      <div className="phone-screen" ref={screenRef} lang={lang}>
        <div className="phone-status" aria-hidden="true">
          <span>9:41</span>
          <span className="phone-status-dots">
            <i />
            <i />
            <i />
          </span>
        </div>
        <AppBar step={step} lang={lang} onBack={onBack} onLeave={onLeave} />
        {mode === 'today' ? (
          <div className="today-scroll">
            {/* Keyed by seq: the whole column re-mounts on every step, like today. */}
            <div className="today-center" key={nav.seq}>
              <ProgressBar step={step} lang={lang} ref={barRef} />
              {renderStep(step)}
            </div>
          </div>
        ) : (
          <>
            <ProgressBar step={step} lang={lang} ref={barRef} />
            <TransitionStage key={mode} option={mode} nav={nav} reduced={reduced} renderStep={renderStep} />
          </>
        )}
        {done && (
          <div className="ob-done" role="status">
            <div className="ob-done-row">
              <span className="ob-done-icon" aria-hidden="true">
                <Icon name="check" />
              </span>
              <p>{done === 'invited' ? c.done.invited : c.done.later}</p>
            </div>
            <HexButton block icon={<Icon name="replay" />} onClick={onRestart}>
              {c.done.restart}
            </HexButton>
          </div>
        )}
        {notice && (
          <p className="phone-snack" role="status" key={notice.id}>
            {notice.text}
          </p>
        )}
      </div>
    </div>
  );
}
