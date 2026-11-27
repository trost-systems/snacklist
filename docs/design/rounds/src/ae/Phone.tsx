import { Fragment, useEffect, useLayoutEffect, useReducer, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { COPY, STORES, fixtureItems, scriptFor } from './data';
import type { Fixture, Item, Lang, StoreId } from './data';
import { AeIcon } from './icons';
import { defaultRow, initialState, landingAfter, qtyLabel, raisedQty, reduce, rowsFor, sectionsOf } from './model';
import type { Row, State } from './model';
import { OPTIONS } from './options';
import type { OptionId, OptionSpec } from './options';

export const MOMENTS = ['closed', 'open', 'typing', 'added'] as const;
export type Moment = (typeof MOMENTS)[number];

type C = (typeof COPY)[Lang];

interface PhoneProps {
  option: OptionId;
  fixture: Fixture;
  lang: Lang;
  keyboard: boolean;
  moment: Moment;
}

const storeName = (id: StoreId, lang: Lang) => STORES.find((s) => s.id === id)?.name[lang] ?? id;
const storeTint = (id: StoreId) => STORES.find((s) => s.id === id)?.tint ?? 'var(--hl-color-divider)';
const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function takeText(state: State, text: string, lang: Lang, spec: OptionSpec): State {
  const typed = reduce(state, { type: 'text', text });
  const row = defaultRow(rowsFor(typed, lang), spec.dup);
  return row ? reduce(typed, { type: 'take', row, lang }) : typed;
}

/** Replays the scripted moment so every screenshot and every visit starts from the same state. */
function scripted(fixture: Fixture, moment: Moment, lang: Lang, spec: OptionSpec): State {
  const script = scriptFor(fixture);
  let s = initialState(fixtureItems(fixture));
  if (moment === 'closed') return s;
  s = reduce(s, { type: 'open' });
  if (moment === 'typing') return reduce(s, { type: 'text', text: script.typing[lang] });
  if (moment === 'added') for (const a of script.adds) s = takeText(s, a[lang], lang, spec);
  return { ...s, flash: null };
}

function StatusBar({ dim }: { dim: boolean }) {
  return (
    <div className={dim ? 'ae-status ae-status--dim' : 'ae-status'} aria-hidden="true">
      <span>9:41</span>
      <span className="ae-status-icons">
        <span className="ae-status-signal" />
        <span className="ae-status-battery" />
      </span>
    </div>
  );
}

function Header({ c, hidden }: { c: C; hidden: boolean }) {
  return (
    <header className={hidden ? 'ae-header ae-header--away' : 'ae-header'} aria-hidden={hidden}>
      <button type="button" className="ae-switcher" tabIndex={hidden ? -1 : 0}>
        <span className="ae-switcher-text">
          <span className="ae-switcher-household">{c.household}</span>
          <span className="ae-switcher-list">{c.list}</span>
        </span>
        <AeIcon name="unfold" />
      </button>
      <span className="ae-header-gap" />
      <button type="button" className="ae-outlined" tabIndex={hidden ? -1 : 0}>
        <span data-text>{c.edit}</span>
      </button>
    </header>
  );
}

function SectionHeader({ store, count, lang }: { store: StoreId; count: number; lang: Lang }) {
  const c = COPY[lang];
  return (
    <div className="ae-section" data-store={store}>
      <span className="ae-section-name" data-text>
        {storeName(store, lang)}
      </span>
      <span className="ae-section-rule" style={{ background: storeTint(store) }} />
      <span className="ae-section-count" data-text>
        <b>{count}</b> {c.items(count)}
      </span>
      <AeIcon name="expand" />
    </div>
  );
}

type Mark = 'new' | 'match' | 'merged' | null;

type Place = 'list' | 'summary' | 'card';

function ItemRow({ item, lang, mark, lifted, dim, tag, existing, last, place }: { item: Item; lang: Lang; mark?: Mark; lifted?: boolean; dim?: boolean; tag?: ReactNode; existing: boolean; last?: boolean; place: Place }) {
  const q = qtyLabel(item);
  const cls = ['ae-row', mark ? `ae-row--${mark}` : '', lifted ? 'ae-row--lift' : '', dim ? 'ae-row--dim' : '', last ? 'ae-row--last' : ''].filter(Boolean).join(' ');
  return (
    <div className={cls} data-ae-row={existing ? 'existing' : 'new'} data-ae-place={place} data-id={item.id} data-qty={item.qty ?? ''} data-name={item.name[lang]} data-dim={dim ? '1' : undefined} role="checkbox" aria-checked="false" aria-label={`${item.name[lang]}${q ? ` ${q}` : ''}`}>
      <span className="ae-row-emoji" aria-hidden="true">
        {item.emoji || <span className="ae-row-placeholder" />}
      </span>
      <span className="ae-row-name" data-text>
        {q && <b className="ae-row-qty">{q} </b>}
        {item.name[lang]}
      </span>
      {tag}
    </div>
  );
}

function ListBody({
  state,
  lang,
  marks,
  lifted = null,
  matchTag = false,
  dim,
  composer,
  composerStore,
  composerAfter = null,
  bottomPad,
}: {
  state: State;
  lang: Lang;
  marks: Record<string, Mark>;
  lifted?: string | null;
  /** The tag on a row an Enter would raise: “+1 → 7×”. */
  matchTag?: boolean;
  dim?: boolean;
  composer?: ReactNode;
  composerStore?: StoreId;
  /** AE3: the field sits right after the last add, else at the end of its store. */
  composerAfter?: string | null;
  bottomPad: number;
}) {
  const c = COPY[lang];
  const sections = sectionsOf(state.items);
  const base = new Set(state.items.filter((it) => !it.id.startsWith('new-')).map((it) => it.id));
  const hasComposerSection = composer && sections.some((s) => s.store === composerStore || s.items.some((it) => it.id === composerAfter));
  return (
    <div className="ae-list-body" style={{ paddingBottom: bottomPad }}>
      {sections.length === 0 && !composer && (
        <p className="ae-empty" data-text>
          {c.emptyList}
        </p>
      )}
      {composer && !hasComposerSection && <div className="ae-composer-solo">{composer}</div>}
      {sections.map((s) => (
        <section key={s.store} className="ae-store">
          <SectionHeader store={s.store} count={s.items.length} lang={lang} />
          {s.items.map((it, n) => {
            const mark = marks[it.id] ?? null;
            const here = composer && composerAfter === it.id;
            const atEnd = composer && !composerAfter && composerStore === s.store && n === s.items.length - 1;
            return (
              <Fragment key={it.id}>
              <ItemRow
                item={it}
                lang={lang}
                mark={mark}
                lifted={lifted === it.id}
                dim={dim && lifted !== it.id && mark !== 'match'}
                existing={base.has(it.id)}
                place="list"
                last={(n === s.items.length - 1 && !atEnd) || Boolean(here)}
                tag={
                  mark === 'new' ? (
                    <span className="ae-tag" data-text>
                      {c.newTag}
                    </span>
                  ) : mark === 'merged' ? (
                    <span className="ae-tag ae-tag--brand" data-text>
                      +1
                    </span>
                  ) : mark === 'match' && matchTag ? (
                    <span className="ae-tag ae-tag--brand" data-text>
                      {c.plusOne(raisedQty(it))}
                    </span>
                  ) : null
                }
              />
              {(here || atEnd) && composer}
              </Fragment>
            );
          })}
        </section>
      ))}
    </div>
  );
}

function SuggestionRow({ row, lang, isDefault, explain, onTake, items }: { row: Row; lang: Lang; isDefault: boolean; explain: boolean; onTake: () => void; items: Item[] }) {
  const c = COPY[lang];
  const match = row.match ? items.find((it) => it.id === row.match?.id) ?? row.match : null;
  let icon: ReactNode = row.emoji ? <span className="ae-sug-emoji">{row.emoji}</span> : <span className="ae-row-placeholder" />;
  let title: ReactNode = row.name;
  let sub: string | null = row.kind === 'typed' ? c.asTyped : row.kind === 'catalog' ? c.catalog : null;
  if (row.kind === 'merge' && match) {
    icon = <AeIcon name="merge" />;
    title = `${raisedQty(match)} ${row.name}`;
    if (explain) sub = c.ae1MergeSub;
  }
  if (row.kind === 'tick') {
    icon = <AeIcon name="checkCircle" />;
    title = <s>{row.name}</s>;
    if (explain) sub = c.ae1TickSub;
  }
  if (row.kind === 'typed' && row.match) {
    icon = <AeIcon name="add" className="ae-ic--brand" />;
    if (explain) sub = c.ae1SecondSub(row.name);
  }
  const cls = ['ae-sug', `ae-sug--${row.kind}`, isDefault ? 'ae-sug--default' : ''].filter(Boolean).join(' ');
  return (
    <button type="button" className={cls} onClick={onTake} data-kind={row.kind} data-default={isDefault ? '1' : undefined}>
      <span className="ae-sug-icon">{icon}</span>
      <span className="ae-sug-text">
        <span className="ae-sug-name" data-text>
          {title}
        </span>
        {sub && (
          <span className="ae-sug-sub" data-text>
            {sub}
          </span>
        )}
      </span>
    </button>
  );
}

function Chips({ c, store }: { c: C; store: string }) {
  return (
    <div className="ae-chips">
      <span className="ae-stepper">
        <button type="button" aria-label="−" disabled>
          <AeIcon name="remove" />
        </button>
        <span className="ae-stepper-n" data-text>
          1
        </span>
        <button type="button" aria-label="+">
          <AeIcon name="add" />
        </button>
      </span>
      <button type="button" className="ae-chip" aria-label={c.storeChip(store)}>
        <span data-text>{store}</span>
      </button>
      <button type="button" className="ae-chip ae-chip--icon" aria-label={c.details}>
        <AeIcon name="notes" />
      </button>
    </div>
  );
}

const KEYS: Record<Lang, string[]> = {
  en: ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'],
  de: ['qwertzuiopü', 'asdfghjklöä', 'yxcvbnm'],
};

function Keyboard({ lang, onKey, onSend }: { lang: Lang; onKey: (k: string) => void; onSend: () => void }) {
  const c = COPY[lang];
  const [rowA = '', rowB = '', rowC = ''] = KEYS[lang];
  const keys = (s: string) =>
    [...s].map((k) => (
      <button key={k} type="button" className="ae-key" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey(k)}>
        {k}
      </button>
    ));
  return (
    <div className="ae-keyboard" data-ae-keyboard data-ae-cover aria-label="Keyboard">
      <div className="ae-keys">{keys(rowA)}</div>
      <div className="ae-keys">{keys(rowB)}</div>
      <div className="ae-keys">
        <span className="ae-key ae-key--wide" aria-hidden="true">
          ⇧
        </span>
        {keys(rowC)}
        <button type="button" className="ae-key ae-key--wide" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey('\b')} aria-label="Backspace">
          ⌫
        </button>
      </div>
      <div className="ae-keys">
        <span className="ae-key ae-key--wide" aria-hidden="true">
          123
        </span>
        <button type="button" className="ae-key ae-key--space" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey(' ')}>
          {c.space}
        </button>
        <button type="button" className="ae-key ae-key--send" data-ae-send onMouseDown={(e) => e.preventDefault()} onClick={onSend}>
          {c.send}
        </button>
      </div>
    </div>
  );
}

export function Phone({ option, fixture, lang, keyboard, moment }: PhoneProps) {
  const spec = OPTIONS[option];
  const c = COPY[lang];
  const [state, dispatch] = useReducer(reduce, undefined, () => scripted(fixture, moment, lang, spec));
  const screenRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [lift, setLift] = useState<string | null>(null);

  const open = state.phase === 'open';
  const rows = open ? rowsFor(state, lang) : [];
  const dflt = defaultRow(rows, spec.dup);
  const showKeyboard = open && keyboard;
  const lastAdded = state.session.length ? state.items.find((it) => it.id === state.session[state.session.length - 1]) ?? null : null;
  const total = state.items.length;

  const take = (row: Row | null) => {
    if (!row) {
      dispatch({ type: 'close' });
      return;
    }
    dispatch({ type: 'take', row, lang });
  };
  const submit = () => take(state.text.trim() ? dflt : null);
  const typeKey = (k: string) => dispatch({ type: 'text', text: k === '\b' ? state.text.slice(0, -1) : state.text + k });

  const flash = state.flash;
  const typedMatch = rows.find((r) => r.match)?.match ?? null;

  useEffect(() => {
    if (open) inputRef.current?.focus({ preventScroll: true });
  }, [open, option, state.session.length, spec.behind === 'inline' ? typedMatch?.id : null]);


  // AE2 and AE3 keep the changed or matching row in view; AE5 scrolls it into view and flies the add there.
  useLayoutEffect(() => {
    const scroller = scrollRef.current;
    if (!scroller || !open) return;
    const id = flash?.id ?? typedMatch?.id ?? lastAdded?.id;
    if (spec.behind === 'inline') {
      const box = scroller.querySelector<HTMLElement>('[data-ae-composer]');
      if (!box) return;
      const header = scroller.querySelector<HTMLElement>('.ae-header')?.offsetHeight ?? 0;
      const room = scroller.clientHeight - header - 8;
      const top = box.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
      // The field first: when the field and its suggestions do not fit, the suggestions scroll, not the field.
      scroller.scrollTop += box.offsetHeight > room ? top - header - 8 : top + box.offsetHeight - scroller.clientHeight;
      return;
    }
    if (!id || (spec.behind !== 'list' && spec.behind !== 'dimmedList')) return;
    const row = scroller.querySelector<HTMLElement>(`[data-id="${id}"]`);
    row?.scrollIntoView({ block: spec.behind === 'dimmedList' ? 'center' : 'nearest' });
  }, [flash?.seq, typedMatch?.id, open, spec.behind, state.text, keyboard]);

  useEffect(() => {
    if (!spec.motion || !flash) return;
    const screen = screenRef.current;
    const row = screen?.querySelector<HTMLElement>(`[data-id="${flash.id}"]`);
    const from = inputRef.current;
    setLift(flash.id);
    const done = window.setTimeout(() => setLift(null), 1400);
    if (!screen || !row || !from || reducedMotion()) return () => window.clearTimeout(done);
    const s = screen.getBoundingClientRect();
    const a = from.getBoundingClientRect();
    const b = row.getBoundingClientRect();
    const ghost = document.createElement('div');
    ghost.className = 'ae-flight';
    ghost.dataset.aeFlight = '1';
    ghost.textContent = row.querySelector('.ae-row-name')?.textContent ?? '';
    ghost.style.left = `${a.left - s.left + 16}px`;
    ghost.style.top = `${a.top - s.top + 8}px`;
    screen.appendChild(ghost);
    const dx = b.left - a.left + 28;
    const dy = b.top - a.top;
    const anim = ghost.animate(
      [
        { transform: 'translate(0, 0) scale(1)', opacity: 1 },
        { transform: `translate(${dx}px, ${dy}px) scale(0.94)`, opacity: 1, offset: 0.85 },
        { transform: `translate(${dx}px, ${dy}px) scale(0.94)`, opacity: 0 },
      ],
      { duration: 520, easing: 'cubic-bezier(0.2, 0, 0, 1)' },
    );
    anim.onfinish = () => ghost.remove();
    return () => {
      window.clearTimeout(done);
      ghost.remove();
    };
  }, [flash?.seq]);

  const fresh = (id: string) => id.startsWith('new-');
  const marks: Record<string, Mark> = {};
  if (open && (spec.behind === 'list' || spec.behind === 'inline')) for (const id of state.session) marks[id] = fresh(id) ? 'new' : 'merged';
  if (open && spec.behind === 'dimmedList' && lift) marks[lift] = fresh(lift) ? 'new' : 'merged';
  if (open && typedMatch && spec.behind !== 'lastTwo' && spec.behind !== 'landing') marks[typedMatch.id] = 'match';

  const field = (
    <div className={open ? 'ae-field ae-field--open' : 'ae-field'} data-ae-field>
      <input
        ref={inputRef}
        aria-label={c.fieldHint}
        placeholder={c.fieldHint}
        value={state.text}
        inputMode={showKeyboard ? 'none' : 'text'}
        enterKeyHint="send"
        autoComplete="off"
        onFocus={() => {
          if (!open) dispatch({ type: 'open' });
        }}
        onChange={(e) => dispatch({ type: 'text', text: e.target.value })}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            submit();
          }
          if (e.key === 'Escape') dispatch({ type: 'close' });
        }}
      />
      {open && state.text && (
        <button type="button" className="ae-field-btn" aria-label={c.clear} onClick={() => dispatch({ type: 'text', text: '' })}>
          <AeIcon name="close" />
        </button>
      )}
      <span className="ae-field-btn ae-field-mic" aria-hidden="true">
        <AeIcon name="mic" />
      </span>
    </div>
  );

  const sugRows = rows.map((r, n) => (
    <SuggestionRow key={`${r.kind}-${r.name}-${n}`} row={r} lang={lang} isDefault={r === dflt} explain={spec.explain} onTake={() => take(r)} items={state.items} />
  ));

  const dupNote =
    spec.explain && typedMatch ? (
      <p className="ae-note" data-text>
        {c.ae1DupNote(typedMatch.name[lang], qtyLabel(state.items.find((it) => it.id === typedMatch.id) ?? typedMatch) ?? '')}
      </p>
    ) : null;
  const secondNote =
    spec.explain && !state.text && state.secondOf ? (
      <p className="ae-note" data-text>
        {c.ae1SecondDone(state.items.find((it) => it.id === state.secondOf)?.name[lang] ?? '')}
      </p>
    ) : null;

  const sheetBody = state.text.trim() ? (
    <>
      {dupNote}
      <div className="ae-sug-list" style={{ ['--ae-rows' as string]: spec.sheetRows }}>
        {sugRows}
      </div>
    </>
  ) : lastAdded ? (
    <>
      {secondNote}
      <Chips c={c} store={storeName(lastAdded.store, lang)} />
    </>
  ) : (
    <p className="ae-type-to" data-text>
      {spec.explain ? c.ae1Lands(c.list) : c.typeToSuggest}
    </p>
  );

  const sheet = (
    <div className="ae-sheet" data-ae-sheet data-ae-cover>
      <button type="button" className="ae-grab" aria-label={c.close} onClick={() => dispatch({ type: 'close' })}>
        <span className="ae-grab-handle" />
      </button>
      {sheetBody}
    </div>
  );

  const bottomBand = showKeyboard ? (
    <Keyboard lang={lang} onKey={typeKey} onSend={submit} />
  ) : (
    <div className="ae-hint-band" data-ae-hint data-ae-cover>
      <span data-text>{spec.explain ? c.ae1HintLine : c.sheetHint}</span>
    </div>
  );

  const composerStore: StoreId = lastAdded?.store ?? sectionsOf(state.items)[0]?.store ?? 'rewe';
  const composer =
    open && spec.behind === 'inline' ? (
      <div className="ae-composer" data-ae-composer data-ae-cover>
        <div className="ae-composer-row">
          {field}
          <button type="button" className="ae-done" onClick={() => dispatch({ type: 'close' })}>
            <AeIcon name="check" />
            <span data-text>{c.done}</span>
          </button>
        </div>
        {state.text.trim() ? (
          <div className="ae-composer-sugs">
            {dflt && dflt.kind !== 'merge' && dflt.store !== composerStore && (
              <p className="ae-note ae-note--inline" data-text>
                {c.landsIn(storeName(dflt.store, lang))}
              </p>
            )}
            {sugRows}
          </div>
        ) : lastAdded ? (
          <Chips c={c} store={storeName(lastAdded.store, lang)} />
        ) : null}
      </div>
    ) : null;

  let behind: ReactNode = null;
  if (open && (spec.behind === 'lastTwo' || spec.behind === 'landing')) {
    const lastTwo = state.session
      .slice(-2)
      .map((id) => state.items.find((it) => it.id === id))
      .filter((it): it is Item => Boolean(it));
    behind = (
      <div className="ae-behind" data-ae-behind>
        {spec.explain && (
          <button type="button" className="ae-explain" data-ae-explain data-ae-cover onClick={() => dispatch({ type: 'close' })}>
            <span className="ae-explain-title" data-text>
              {c.ae1Behind(total)}
            </span>
            {total > 0 && (
              <span className="ae-explain-sub" data-text>
                {c.ae1BehindSub}
              </span>
            )}
          </button>
        )}
        <div className="ae-behind-spacer" />
        {spec.behind === 'landing' ? (
          <LandingCard state={state} lang={lang} row={dflt} lastAdded={lastAdded} />
        ) : (
          <>
            {spec.explain && lastTwo.length > 0 && (
              <p className="ae-just" data-text>
                {c.ae1Just(state.session.length, total)}
              </p>
            )}
            <div className="ae-last-two">
              {lastTwo.map((it) => (
                <ItemRow
                  key={it.id}
                  item={it}
                  lang={lang}
                  existing={false}
                  place="summary"
                  tag={spec.explain ? <span className="ae-row-store" data-text>{c.ae1Onto(storeName(it.store, lang))}</span> : null}
                />
              ))}
            </div>
          </>
        )}
      </div>
    );
  }

  const showList = !open || spec.behind === 'list' || spec.behind === 'inline' || spec.behind === 'dimmedList';
  const dimList = open && spec.behind === 'dimmedList';
  const screenCls = ['ae-screen', open ? 'ae-screen--open' : '', spec.scrim && open ? 'ae-screen--scrim' : '', `ae-screen--${spec.behind}`].filter(Boolean).join(' ');

  return (
    <div className={screenCls} ref={screenRef} data-testid="ae-screen" data-option={option} data-phase={state.phase}>
      <div className="ae-top">
        <StatusBar dim={dimList} />
        <div
          className={dimList ? 'ae-viewport ae-viewport--dim' : 'ae-viewport'}
          data-ae-viewport
          onClick={open && spec.behind === 'list' ? () => dispatch({ type: 'close' }) : undefined}
        >
          {showList && (
            <div className="ae-scroll" ref={scrollRef} data-ae-scroll>
              <Header c={c} hidden={open && spec.behind !== 'list' && spec.behind !== 'inline'} />
              <ListBody
                state={state}
                lang={lang}
                marks={marks}
                lifted={spec.behind === 'dimmedList' ? lift : null}
                matchTag={spec.dup === 'merge'}
                dim={dimList}
                composer={composer}
                composerStore={composerStore}
                composerAfter={spec.behind === 'inline' ? (typedMatch?.id ?? lastAdded?.id ?? null) : null}
                bottomPad={open ? 16 : 150}
              />
            </div>
          )}
          {behind}
        </div>
        {spec.scrim && open && spec.behind !== 'dimmedList' && <div className="ae-scrim" data-ae-scrim onClick={() => dispatch({ type: 'close' })} />}
      </div>
      {open && spec.behind !== 'inline' && sheet}
      {open && spec.behind !== 'inline' && (
        <div className="ae-bar ae-bar--open" data-ae-bar data-ae-cover>
          {field}
        </div>
      )}
      {open && bottomBand}
      {!open && (
        <div className="ae-dock">
          <div className="ae-bar" data-ae-bar>
            {field}
          </div>
          <nav className="ae-pill" aria-label="Tabs">
            <span className="ae-tab ae-tab--on">
              <AeIcon name="cart" />
              <span data-text>{c.tabs[0]}</span>
            </span>
            <span className="ae-tab">
              <AeIcon name="menu" />
              <span data-text>{c.tabs[1]}</span>
            </span>
          </nav>
        </div>
      )}
    </div>
  );
}

function LandingCard({ state, lang, row, lastAdded }: { state: State; lang: Lang; row: Row | null; lastAdded: Item | null }) {
  const c = COPY[lang];
  const sections = sectionsOf(state.items);
  const typing = Boolean(state.text.trim() && row);

  if (!typing && !lastAdded) {
    return (
      <div className="ae-landing" data-ae-landing data-ae-cover>
        <p className="ae-landing-title" data-text>
          {c.list} · <b>{state.items.length}</b> {c.items(state.items.length)}
        </p>
        {sections.length > 0 ? (
          <div className="ae-landing-stores">
            {sections.map((s) => (
              <span key={s.store} className="ae-landing-store" data-text>
                <span className="ae-landing-dot" style={{ background: storeTint(s.store) }} />
                {storeName(s.store, lang)} <b>{s.items.length}</b>
              </span>
            ))}
          </div>
        ) : null}
        <p className="ae-landing-hint" data-text>
          {sections.length ? c.landingHint : c.ae1Behind(0)}
        </p>
      </div>
    );
  }

  if (typing && row) {
    const store = row.match ? row.match.store : row.store;
    const inStore = sections.find((s) => s.store === store)?.items ?? [];
    if (row.kind === 'merge' && row.match) {
      const current = state.items.find((it) => it.id === row.match?.id) ?? row.match;
      const at = inStore.findIndex((it) => it.id === current.id);
      return (
        <div className="ae-landing" data-ae-landing data-ae-cover>
          <SectionHeader store={store} count={inStore.length} lang={lang} />
          {inStore[at - 1] && <ItemRow item={inStore[at - 1] as Item} lang={lang} existing place="card" />}
          <ItemRow item={current} lang={lang} existing place="card" mark="match" tag={<span className="ae-tag ae-tag--brand" data-text>{c.plusOne(raisedQty(current))}</span>} />
          {inStore[at + 1] && <ItemRow item={inStore[at + 1] as Item} lang={lang} existing last place="card" />}
        </div>
      );
    }
    const after = landingAfter(state.items, store, row.cat);
    const at = after ? inStore.findIndex((it) => it.id === after.id) : -1;
    const next = inStore[at + 1] ?? null;
    const ghost: Item = { id: 'ghost', name: { en: row.name, de: row.name }, emoji: row.emoji, qty: null, store, cat: row.cat };
    return (
      <div className="ae-landing" data-ae-landing data-ae-cover>
        <SectionHeader store={store} count={inStore.length} lang={lang} />
        {after && <ItemRow item={after} lang={lang} existing place="card" />}
        <div className="ae-ghost" data-ae-ghost>
          <ItemRow item={ghost} lang={lang} existing={false} place="card" tag={<span className="ae-tag ae-tag--ghost" data-text>{c.landsHere}</span>} />
        </div>
        {next && <ItemRow item={next} lang={lang} existing last place="card" />}
      </div>
    );
  }

  const added = lastAdded as Item;
  const inStore = sections.find((s) => s.store === added.store)?.items ?? [];
  const at = inStore.findIndex((it) => it.id === added.id);
  return (
    <div className="ae-landing" data-ae-landing data-ae-cover>
      <SectionHeader store={added.store} count={inStore.length} lang={lang} />
      {inStore[at - 1] && <ItemRow item={inStore[at - 1] as Item} lang={lang} existing place="card" />}
      <ItemRow item={added} lang={lang} existing={false} place="card" mark="new" tag={<span className="ae-tag" data-text>{c.newTag}</span>} />
      {inStore[at + 1] && <ItemRow item={inStore[at + 1] as Item} lang={lang} existing last place="card" />}
    </div>
  );
}
