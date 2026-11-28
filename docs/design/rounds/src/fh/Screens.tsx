import { useState } from 'react';
import { Icon } from '../components/Icons';
import { CHAINS, COPY } from './copy';
import type { Lang } from './copy';
import { OPTIONS } from './options';
import { Painted } from './Painted';
import type { PaintCtx } from './Painted';

export const TARGETS = ['chip', 'chipPicked', 'addOwn', 'field', 'next', 'skip', 'row'] as const;
export type Target = (typeof TARGETS)[number] | 'none';

export const TARGET_LABEL: Record<Target, string> = {
  none: 'Nothing',
  chip: 'Chip',
  chipPicked: 'Picked chip',
  addOwn: 'Text button',
  field: 'Text field',
  next: 'Button',
  skip: 'Second button',
  row: 'List row',
};

interface ScreenProps {
  ctx: PaintCtx;
  lang: Lang;
  target: Target;
  fieldOpen?: boolean;
}

function StatusBar() {
  return (
    <div className="fh-status" aria-hidden="true">
      <span>9:41</span>
      <span className="fh-status-icons">
        <span className="fh-status-signal" />
        <span className="fh-status-battery" />
      </span>
    </div>
  );
}

function Chip({ ctx, label, picked, focused, onToggle, testId }: { ctx: PaintCtx; label: string; picked: boolean; focused: boolean; onToggle: () => void; testId: string }) {
  return (
    <Painted
      ctx={ctx}
      kind="chip"
      honey={picked}
      face={picked ? 'honey' : 'surface-raised'}
      forcedFocus={focused}
      contourWidth={1}
      testId={testId}
      role="checkbox"
      ariaPressed={picked}
      onActivate={onToggle}
      className="fh-chip"
    >
      {picked && <Icon name="check" />}
      <span className="fh-chip-label">{label}</span>
    </Painted>
  );
}

export function OnboardingStores({ ctx, lang, target, fieldOpen = false }: ScreenProps) {
  const c = COPY[lang];
  const names = [...CHAINS, c.hardware];
  const [picked, setPicked] = useState<string[]>(['EDEKA', 'Lidl']);
  const [naming, setNaming] = useState(false);
  const [typed, setTyped] = useState('');
  const showField = naming || fieldOpen || target === 'field';
  const space = OPTIONS[ctx.option].spacing;
  const toggle = (n: string) => setPicked((p) => (p.includes(n) ? p.filter((x) => x !== n) : [...p, n]));

  return (
    <div className="fh-screen" data-testid="screen-stores">
      <StatusBar />
      <header className="fh-appbar">
        <button type="button" className="fh-icon" aria-label={c.back}>
          <Icon name="arrow_back" />
        </button>
        <p className="fh-appbar-title">{c.progress}</p>
        <button type="button" className="fh-icon" aria-label={c.leave}>
          <Icon name="close" />
        </button>
      </header>
      <div className="fh-progress" aria-hidden="true">
        <div className="fh-progress-fill" style={{ width: `${(4 / 7) * 100}%` }} />
      </div>
      <div className="fh-scroll" data-testid="stores-scroll">
        <div className="fh-body">
          <h1 className="fh-heading">{c.title}</h1>
          <div className="fh-wrap" data-testid="chips" style={{ columnGap: space.chips, rowGap: space.chips }}>
            {names.map((n) => (
              <Chip
                key={n}
                ctx={ctx}
                label={n}
                picked={picked.includes(n)}
                focused={(target === 'chip' && n === 'REWE') || (target === 'chipPicked' && n === 'EDEKA')}
                onToggle={() => toggle(n)}
                testId={`chip-${n}`}
              />
            ))}
            {!showField && (
              <Painted
                ctx={ctx}
                kind="textButton"
                face={null}
                contour={null}
                forcedFocus={target === 'addOwn'}
                testId="add-own"
                onActivate={() => setNaming(true)}
                className="fh-textbtn"
              >
                <Icon name="add" />
                <span>{c.addOwn}</span>
              </Painted>
            )}
          </div>
          {showField && (
            <div className="fh-namerow" style={{ marginTop: space.stack, gap: space.inline }}>
              <Painted ctx={ctx} kind="field" forcedFocus={target === 'field'} testId="field" className="fh-field">
                <input
                  aria-label={c.storeName}
                  placeholder={c.storeName}
                  value={typed}
                  onChange={(e) => setTyped(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') setNaming(false);
                  }}
                />
              </Painted>
              <Painted
                ctx={ctx}
                kind="button"
                honey
                face="honey"
                contour="edge"
                edge="honey-edge"
                forcedFocus={false}
                testId="confirm"
                ariaLabel={c.addOwn}
                className="fh-btn fh-btn--icon"
              >
                <Icon name="check" />
              </Painted>
              <button type="button" className="fh-icon" aria-label={c.cancel} onClick={() => setNaming(false)}>
                <Icon name="close" />
              </button>
            </div>
          )}
        </div>
      </div>
      <footer className="fh-footer" style={{ gap: space.stack }}>
        <Painted
          ctx={ctx}
          kind="button"
          honey
          face="honey"
          contour="edge"
          edge="honey-edge"
          forcedFocus={target === 'next'}
          testId="next"
          className="fh-btn"
        >
          <span>{c.next}</span>
        </Painted>
        <Painted
          ctx={ctx}
          kind="button"
          face="surface-raised"
          contour="border"
          edge="surface-edge"
          forcedFocus={target === 'skip'}
          testId="skip"
          className="fh-btn"
        >
          <span>{c.skip}</span>
        </Painted>
      </footer>
    </div>
  );
}

export function ListScreen({ ctx, lang, target }: ScreenProps) {
  const c = COPY[lang];
  return (
    <div className="fh-screen" data-testid="screen-list">
      <StatusBar />
      <header className="fh-appbar fh-appbar--list">
        <p className="fh-list-title">{c.listTitle}</p>
      </header>
      <div className="fh-scroll" data-testid="list-scroll">
        <p className="fh-section">{c.store}</p>
        <div className="fh-rows" data-testid="rows">
          {c.rows.map((r, i) => (
            <Painted
              key={r.name}
              ctx={ctx}
              kind="row"
              face="surface"
              contour={null}
              forcedFocus={target === 'row' && i === 1}
              testId={`row-${i}`}
              className="fh-row"
            >
              <span className="fh-row-icon" data-deco aria-hidden="true" />
              <span className="fh-row-text">
                <span className="fh-row-name">
                  {r.qty && <b className="fh-row-qty">{r.qty} </b>}
                  {r.name}
                </span>
                {r.detail && <span className="fh-row-detail">{r.detail}</span>}
              </span>
              {i < c.rows.length - 1 && <span className="fh-row-rule" data-deco aria-hidden="true" />}
            </Painted>
          ))}
        </div>
      </div>
      <nav className="fh-tabs" aria-hidden="true">
        {c.tabs.map((t, i) => (
          <span key={t} className={i === 0 ? 'fh-tab fh-tab--on' : 'fh-tab'}>
            {t}
          </span>
        ))}
      </nav>
    </div>
  );
}
