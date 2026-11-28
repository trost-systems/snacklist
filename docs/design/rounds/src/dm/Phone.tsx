import { Fragment, useEffect, useLayoutEffect, useReducer, useRef } from 'react';
import type { ReactNode } from 'react';
import { COPY, SCENARIOS, STORES } from './data';
import type { Fixture, Item, Lang, StoreId } from './data';
import { DmIcon } from './icons';
import { catalogRows, initialState, knownNames, matchOf, mergedQty, parseTyped, qtyLabel, reduce, sectionsOf, stepOf, stepsIn, times } from './model';
import type { Action, MatchInfo, State } from './model';
import { OPTIONS } from './options';
import type { OptionId } from './options';

export const MOMENTS = ['closed', 'typing', 'after'] as const;
export type Moment = (typeof MOMENTS)[number];

type C = (typeof COPY)[Lang];

const storeName = (id: StoreId, lang: Lang) => STORES.find((s) => s.id === id)?.name[lang] ?? id;
const storeTint = (id: StoreId) => STORES.find((s) => s.id === id)?.tint ?? 'var(--hl-color-divider)';
const withQty = (qty: string | null, name: string) => [qtyLabel(qty), name].filter(Boolean).join(' ');

/** Everything one option offers for the typed line: the merge it would do, the new entry, and what Enter takes. */
interface Offer {
  match: MatchInfo | null;
  /** DM1's chips; one entry elsewhere. */
  amounts: string[];
  /** The Menge after the default merge. */
  result: string;
  newName: string;
  newQty: string | null;
}

function offerFor(option: OptionId, state: State, lang: Lang): Offer {
  const spec = OPTIONS[option];
  const match = matchOf(state.text, state.items, lang, spec.smart);
  const typed = parseTyped(state.text, knownNames(state.items, lang));
  if (!match) return { match, amounts: [], result: '', newName: typed.name, newQty: typed.qty };
  const unit = stepOf(match.item.qty);
  let amounts = [match.step];
  if (option === 'dm1') amounts = [...new Set([match.step, unit, times(unit, 2)])].slice(0, 2);
  if (option === 'dm5') amounts = [times(unit, state.k || stepsIn(match.step, unit))];
  const first = amounts[0] ?? '';
  return {
    match,
    amounts,
    result: mergedQty(match.item, first),
    newName: spec.smart ? match.item.name[lang] : typed.name,
    newQty: spec.smart ? match.typedQty : typed.qty,
  };
}

function act(kind: 'merge' | 'tick' | 'new', offer: Offer, lang: Lang, amount?: string): Action | null {
  const c = COPY[lang];
  const item = offer.match?.item;
  if (kind === 'merge' && item) {
    const qty = mergedQty(item, amount ?? offer.amounts[0] ?? '');
    return { type: 'merge', id: item.id, qty, note: c.merged(withQty(qty, item.name[lang])) };
  }
  if (kind === 'tick' && item) return { type: 'tick', id: item.id, note: c.ticked(item.name[lang]) };
  if (kind === 'new' && offer.newName) return { type: 'add', name: offer.newName, qty: offer.newQty, lang, note: c.added(withQty(offer.newQty, offer.newName)) };
  return null;
}

/** Replays the scripted moment so every screenshot and every visit starts from the same state. */
function scripted(option: OptionId, fixture: Fixture, moment: Moment, lang: Lang): State {
  let s = initialState(SCENARIOS[fixture].items());
  if (moment === 'closed') return s;
  s = reduce(reduce(s, { type: 'open' }), { type: 'text', text: SCENARIOS[fixture].typed[lang] });
  if (moment === 'typing') return s;
  const offer = offerFor(option, s, lang);
  const a = act(offer.match ? 'merge' : 'new', offer, lang);
  return a ? reduce(s, a) : s;
}

function StatusBar() {
  return (
    <div className="dm-status" aria-hidden="true">
      <span>9:41</span>
      <span className="dm-status-icons">
        <span className="dm-status-signal" />
        <span className="dm-status-battery" />
      </span>
    </div>
  );
}

function Header({ c }: { c: C }) {
  return (
    <header className="dm-header">
      <button type="button" className="dm-switcher">
        <span className="dm-switcher-text">
          <span className="dm-switcher-household">{c.household}</span>
          <span className="dm-switcher-list">{c.list}</span>
        </span>
        <DmIcon name="unfold" />
      </button>
      <span className="dm-header-gap" />
      <button type="button" className="dm-outlined">
        <span data-text>{c.edit}</span>
      </button>
    </header>
  );
}

function SectionHeader({ store, count, lang }: { store: StoreId; count: number; lang: Lang }) {
  const c = COPY[lang];
  return (
    <div className="dm-section" data-store={store}>
      <span className="dm-section-name" data-text>
        {storeName(store, lang)}
      </span>
      <span className="dm-section-rule" style={{ background: storeTint(store) }} />
      <span className="dm-section-count" data-text>
        <b>{count}</b> {c.items(count)}
      </span>
      <DmIcon name="expand" />
      <span className="dm-section-open" aria-hidden="true">
        <DmIcon name="openStore" />
      </span>
    </div>
  );
}

function ItemRow({ item, lang, cls, tag, place = 'list' }: { item: Item; lang: Lang; cls?: string; tag?: ReactNode; place?: 'list' | 'card' }) {
  const q = qtyLabel(item.qty);
  return (
    <div className={['dm-row', cls].filter(Boolean).join(' ')} data-dm-row={place} data-id={item.id} data-qty={item.qty ?? ''} role="checkbox" aria-checked="false" aria-label={withQty(item.qty, item.name[lang])}>
      <span className="dm-row-emoji" aria-hidden="true">
        {item.emoji || <span className="dm-row-placeholder" />}
      </span>
      <span className="dm-row-name" data-text>
        {q && <b className="dm-row-qty">{q} </b>}
        {item.name[lang]}
      </span>
      {tag}
    </div>
  );
}

/** A worded action. `label` is the accessible name when the visible words leave out the item. */
function Act({ action, cls, onClick, label, children, amount, pressed }: { action: string; cls: string; onClick: () => void; label?: string; children: ReactNode; amount?: string; pressed?: boolean }) {
  return (
    <button type="button" className={cls} data-dm-action={action} data-dm-amount={amount} aria-label={label} aria-pressed={pressed} onClick={onClick}>
      {children}
    </button>
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
      <button key={k} type="button" className="dm-key" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey(k)}>
        {k}
      </button>
    ));
  return (
    <div className="dm-keyboard" data-dm-keyboard data-dm-cover aria-label="Keyboard">
      <div className="dm-keys">{keys(rowA)}</div>
      <div className="dm-keys">{keys(rowB)}</div>
      <div className="dm-keys">
        <span className="dm-key dm-key--wide" aria-hidden="true">
          ⇧
        </span>
        {keys(rowC)}
        <button type="button" className="dm-key dm-key--wide" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey('\b')} aria-label="Backspace">
          ⌫
        </button>
      </div>
      <div className="dm-keys">
        <span className="dm-key dm-key--wide" aria-hidden="true">
          123
        </span>
        <button type="button" className="dm-key dm-key--space" onMouseDown={(e) => e.preventDefault()} onClick={() => onKey(' ')}>
          {c.space}
        </button>
        <button type="button" className="dm-key dm-key--send" data-dm-send onMouseDown={(e) => e.preventDefault()} onClick={onSend}>
          {c.send}
        </button>
      </div>
    </div>
  );
}

interface PhoneProps {
  option: OptionId;
  fixture: Fixture;
  lang: Lang;
  keyboard: boolean;
  moment: Moment;
}

export function Phone({ option, fixture, lang, keyboard, moment }: PhoneProps) {
  const c = COPY[lang];
  const [state, dispatch] = useReducer(reduce, undefined, () => scripted(option, fixture, moment, lang));
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const open = state.phase === 'open';
  const offer = offerFor(option, state, lang);
  const { match } = offer;
  const item = match ? (state.items.find((it) => it.id === match.item.id) ?? match.item) : null;
  const name = item?.name[lang] ?? '';
  const resultLabel = qtyLabel(offer.result) || offer.result;
  const showKeyboard = open && keyboard;
  const typing = open && state.text.trim().length > 0;

  const run = (a: Action | null) => {
    if (a) dispatch(a);
  };
  const doMerge = (amount?: string) => run(act('merge', offer, lang, amount));
  const doTick = () => run(act('tick', offer, lang));
  const doNew = () => run(act('new', offer, lang));
  const doCatalog = (n: string) => run({ type: 'add', name: n, qty: null, lang, note: c.added(n) });
  const submit = () => {
    if (!typing) return dispatch({ type: 'close' });
    if (!match) return doNew();
    if (option === 'dm5') return state.choice === 'tick' ? doTick() : state.choice === 'new' ? doNew() : doMerge();
    return doMerge();
  };
  const typeKey = (k: string) => dispatch({ type: 'text', text: k === '\b' ? state.text.slice(0, -1) : state.text + k });

  useEffect(() => {
    if (open) inputRef.current?.focus({ preventScroll: true });
  }, [open, state.seq]);

  // AE2: the match, else the latest change, scrolls into view; DM1 also its actions under it.
  useLayoutEffect(() => {
    const scroller = scrollRef.current;
    if (!scroller || !open) return;
    const id = item?.id ?? Object.keys(state.marks).pop();
    if (!id) return;
    const target = scroller.querySelector<HTMLElement>(`[data-dm-under="${id}"]`) ?? scroller.querySelector<HTMLElement>(`[data-id="${id}"]`);
    const row = scroller.querySelector<HTMLElement>(`[data-id="${id}"]`);
    if (!target || !row) return;
    const s = scroller.getBoundingClientRect();
    const top = row.getBoundingClientRect().top - s.top;
    const bottom = target.getBoundingClientRect().bottom - s.top;
    const header = (scroller.querySelector<HTMLElement>('.dm-header')?.offsetHeight ?? 52) + 12;
    if (bottom > scroller.clientHeight) scroller.scrollTop += Math.min(bottom - scroller.clientHeight + 8, top - header);
    else if (top < header) scroller.scrollTop += top - header;
  }, [item?.id, open, state.seq, keyboard, state.k]);

  /* ---------- the list ---------- */

  const tagFor = (it: Item): ReactNode => {
    const mark = open ? state.marks[it.id] : undefined;
    if (mark === 'new')
      return (
        <span className="dm-tag" data-text>
          {c.newTag}
        </span>
      );
    if (mark === 'raised')
      return option === 'today' ? (
        <span className="dm-tag dm-tag--brand" aria-hidden="true">
          <DmIcon name="merge" />
        </span>
      ) : (
        <span className="dm-tag dm-tag--brand" data-text>
          {qtyLabel(it.qty)}
        </span>
      );
    if (item && it.id === item.id && option !== 'dm1')
      return (
        <span className="dm-tag dm-tag--brand" data-text data-dm-peek-tag>
          → {option === 'dm5' && state.choice === 'tick' ? '✓' : resultLabel}
        </span>
      );
    return null;
  };

  const rowClass = (it: Item) => {
    const mark = open ? state.marks[it.id] : undefined;
    if (item && it.id === item.id) return 'dm-row--match';
    if (mark === 'new') return 'dm-row--new';
    if (mark === 'raised') return 'dm-row--raised';
    return '';
  };

  const dm1Under = (it: Item) => (
    <div className="dm-under" data-dm-under={it.id} data-dm-match-ui>
      {offer.amounts.map((amount, n) => (
        <Act key={amount} action="merge" amount={amount} cls={n === 0 ? 'dm-chip dm-chip--merge dm-chip--enter' : 'dm-chip dm-chip--merge'} onClick={() => doMerge(amount)} label={`${c.plus(amount, qtyLabel(mergedQty(it, amount)))}, ${c.raise(it.name[lang], qtyLabel(mergedQty(it, amount)))}`}>
          <span data-text>{c.plus(amount, qtyLabel(mergedQty(it, amount)))}</span>
        </Act>
      ))}
      <Act action="tick" cls="dm-chip dm-chip--tick" onClick={doTick} label={`${c.tickOff}, ${it.name[lang]}`}>
        <DmIcon name="check" />
        <span data-text>{c.tickOff}</span>
      </Act>
    </div>
  );

  const sections = sectionsOf(state.items);
  const list = (
    <div className="dm-list-body" style={{ paddingBottom: open ? 16 : 150 }}>
      {sections.map((s) => (
        <section key={s.store} className="dm-store">
          <SectionHeader store={s.store} count={s.items.length} lang={lang} />
          {s.items.map((it, n) => (
            <Fragment key={it.id}>
              <ItemRow item={it} lang={lang} cls={[rowClass(it), n === s.items.length - 1 ? 'dm-row--last' : ''].filter(Boolean).join(' ')} tag={tagFor(it)} />
              {option === 'dm1' && item && it.id === item.id && dm1Under(it)}
            </Fragment>
          ))}
        </section>
      ))}
    </div>
  );

  /* ---------- the sheet ---------- */

  const typedRow = (sub: string) => (
    <Act action="new" cls="dm-sug dm-sug--typed" onClick={doNew} label={`${withQty(offer.newQty, offer.newName)}, ${sub}`}>
      <span className="dm-sug-icon">
        <DmIcon name="add" className="dm-ic--brand" />
      </span>
      <span className="dm-sug-text">
        <span className="dm-sug-name" data-text>
          {withQty(offer.newQty, offer.newName)}
        </span>
        <span className="dm-sug-sub" data-text>
          {sub}
        </span>
      </span>
    </Act>
  );

  const catalog = catalogRows(state.text, lang).map((r) => (
    <button key={r.name[lang]} type="button" className="dm-sug" data-dm-catalog onClick={() => doCatalog(r.name[lang])}>
      <span className="dm-sug-icon">
        <span className="dm-sug-emoji">{r.emoji}</span>
      </span>
      <span className="dm-sug-text">
        <span className="dm-sug-name" data-text>
          {r.name[lang]}
        </span>
        <span className="dm-sug-sub" data-text>
          {storeName(r.store, lang)}
        </span>
      </span>
    </button>
  ));

  const details = item ? storeName(item.store, lang) : '';
  const dm5Confirm = state.choice === 'tick' ? c.dm5DoTick(name) : state.choice === 'new' ? c.dm5DoNew(withQty(offer.newQty, offer.newName)) : c.dm5DoMerge(resultLabel);
  let rows: ReactNode;
  let fixed: ReactNode = null;
  let capRows = 2;

  if (!match) {
    rows = (
      <>
        {typedRow(c.asTyped)}
        {catalog}
      </>
    );
  } else if (option === 'today' || option === 'dm2') {
    const worded = option === 'dm2';
    rows = (
      <>
        <div className="dm-split" data-dm-match-ui>
          <Act action="merge" amount={offer.amounts[0]} cls="dm-split-merge" onClick={() => doMerge()} label={[worded ? c.dm2Kicker(offer.amounts[0] ?? '1') : c.merge, withQty(offer.result, name), details].join(', ')}>
            <DmIcon name="merge" />
            <span className="dm-sug-text">
              {worded && (
                <span className="dm-split-kicker" data-text>
                  {c.dm2Kicker(offer.amounts[0] ?? '1')}
                </span>
              )}
              <span className="dm-sug-name" data-text>
                {withQty(offer.result, name)}
              </span>
              <span className="dm-sug-sub" data-text>
                {details}
              </span>
            </span>
          </Act>
          <Act action="tick" cls={worded ? 'dm-split-tick dm-split-tick--worded' : 'dm-split-tick'} onClick={doTick} label={`${c.tickOff}, ${name}`}>
            <DmIcon name="checkCircle" />
            {worded && <span data-text>{c.tickOff}</span>}
          </Act>
        </div>
        {typedRow(worded ? c.dm2Second : c.asTyped)}
        {catalog}
      </>
    );
  } else if (option === 'dm1') {
    fixed = (
      <p className="dm-note dm-note--pointer" data-text>
        <DmIcon name="north" />
        {c.dm1Hint(name)}
      </p>
    );
    capRows = 1;
    rows = (
      <>
        {typedRow(c.newEntry)}
        {catalog}
      </>
    );
  } else if (option === 'dm3') {
    fixed = (
      <p className="dm-note dm-sentence" data-text data-dm-match-ui>
        {c.dm3Line(name, qtyLabel(item?.qty ?? null) || '1×', details)}
      </p>
    );
    capRows = 3;
    rows = (
      <>
        <Act action="merge" amount={offer.amounts[0]} cls="dm-verb dm-verb--merge dm-verb--enter" onClick={() => doMerge()} label={`${c.dm3Merge(resultLabel)}, ${name}`}>
          <DmIcon name="merge" />
          <span data-text>{c.dm3Merge(resultLabel)}</span>
        </Act>
        <Act action="tick" cls="dm-verb dm-verb--tick" onClick={doTick} label={`${c.dm3Tick}, ${name}`}>
          <DmIcon name="checkCircle" />
          <span data-text>{c.dm3Tick}</span>
        </Act>
        <Act action="new" cls="dm-verb" onClick={doNew}>
          <DmIcon name="add" className="dm-ic--brand" />
          <span data-text>{c.dm3New(withQty(offer.newQty, offer.newName))}</span>
        </Act>
        {catalog}
      </>
    );
  } else if (option === 'dm4' && item) {
    fixed = (
      <div className="dm-card" data-dm-match-ui>
        <p className="dm-card-title" data-text>
          {c.dm4Title}
        </p>
        <ItemRow item={item} lang={lang} place="card" cls="dm-row--last" tag={<span className="dm-row-store" data-text>{details}</span>} />
        <div className="dm-card-actions">
          <Act action="merge" amount={offer.amounts[0]} cls="dm-chip dm-chip--merge dm-chip--enter" onClick={() => doMerge()} label={`${c.plus(offer.amounts[0] ?? '1', resultLabel)}, ${c.raise(name, resultLabel)}`}>
            <span data-text>{c.plus(offer.amounts[0] ?? '1', resultLabel)}</span>
          </Act>
          <Act action="tick" cls="dm-chip dm-chip--tick" onClick={doTick} label={`${c.tickOff}, ${name}`}>
            <DmIcon name="check" />
            <span data-text>{c.tickOff}</span>
          </Act>
        </div>
      </div>
    );
    capRows = 1;
    rows = (
      <>
        <p className="dm-divider" data-text>
          {c.dm4Or}
        </p>
        {typedRow(c.asTyped)}
        {catalog}
      </>
    );
  } else if (option === 'dm5' && item) {
    const unit = stepOf(item.qty);
    const k = state.k || stepsIn(match.step, unit);
    const amount = offer.amounts[0] ?? '1';
    const choices = [
      ['merge', c.dm5ChooseMerge],
      ['tick', c.dm5ChooseTick],
      ['new', c.dm5ChooseNew],
    ] as const;
    fixed = (
      <div className="dm-ask" data-dm-match-ui>
        <p className="dm-note dm-sentence" data-text>
          {c.dm5Ask(name)}
        </p>
        <div className="dm-seg" role="radiogroup" aria-label={c.dm5Ask(name)}>
          {choices.map(([id, text]) => (
            <button key={id} type="button" role="radio" aria-checked={state.choice === id} className={state.choice === id ? 'dm-seg-on' : ''} data-dm-action={`choose-${id}`} onClick={() => dispatch({ type: 'choose', choice: id })}>
              <span data-text>{text}</span>
            </button>
          ))}
        </div>
        {state.choice === 'merge' && (
          <div className="dm-amount" role="group" aria-label={c.dm5Amount}>
            <span className="dm-amount-label" data-text>
              {c.dm5Amount}
            </span>
            <Act action="less" cls="dm-step" onClick={() => dispatch({ type: 'k', k: k - 1 })} label={`− ${c.dm5Less}, ${c.dm5Amount}`}>
              <span data-text>− {c.dm5Less}</span>
            </Act>
            <b className="dm-amount-n" data-text data-dm-amount-n>
              +{amount}
            </b>
            <Act action="more" cls="dm-step" onClick={() => dispatch({ type: 'k', k: k + 1 })} label={`+ ${c.dm5More}, ${c.dm5Amount}`}>
              <span data-text>+ {c.dm5More}</span>
            </Act>
          </div>
        )}
        <Act action={state.choice === 'merge' ? 'merge' : state.choice} amount={state.choice === 'merge' ? amount : undefined} cls={`dm-confirm dm-confirm--${state.choice}`} onClick={submit}>
          <span data-text>{dm5Confirm}</span>
        </Act>
      </div>
    );
    capRows = 0;
    rows = null;
  }

  const hint = !match || option === 'today' ? c.sheetHint : c.enterDoes(option === 'dm5' ? dm5Confirm : c.dm3Merge(resultLabel));

  const sheetBody = typing ? (
    <>
      {fixed}
      {rows && (
        <div className="dm-sug-list" style={{ ['--dm-rows' as string]: capRows }}>
          {rows}
        </div>
      )}
    </>
  ) : state.note ? (
    <p className="dm-note dm-note--done" data-text data-dm-note={state.note.kind}>
      {state.note.text}
    </p>
  ) : (
    <p className="dm-type-to" data-text>
      {c.typeToSuggest}
    </p>
  );

  const field = (
    <div className={open ? 'dm-field dm-field--open' : 'dm-field'} data-dm-field>
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
        <button type="button" className="dm-field-btn" aria-label={c.clear} onClick={() => dispatch({ type: 'text', text: '' })}>
          <DmIcon name="close" />
        </button>
      )}
      <span className="dm-field-btn dm-field-mic" aria-hidden="true">
        <DmIcon name="mic" />
      </span>
    </div>
  );

  return (
    <div className={open ? 'dm-screen dm-screen--open' : 'dm-screen'} data-testid="dm-screen" data-option={option} data-phase={state.phase}>
      <div className="dm-top">
        <StatusBar />
        <div className="dm-viewport" onClick={open ? () => dispatch({ type: 'close' }) : undefined}>
          <div className="dm-scroll" ref={scrollRef} data-dm-scroll onClick={(e) => (e.target as HTMLElement).closest('[data-dm-action]') && e.stopPropagation()}>
            <Header c={c} />
            {list}
          </div>
        </div>
      </div>
      {open && (
        <div className="dm-sheet" data-dm-sheet data-dm-cover>
          <button type="button" className="dm-grab" aria-label={c.close} onClick={() => dispatch({ type: 'close' })}>
            <span className="dm-grab-handle" />
          </button>
          {sheetBody}
        </div>
      )}
      {open && (
        <div className="dm-bar dm-bar--open" data-dm-bar data-dm-cover>
          {field}
        </div>
      )}
      {open &&
        (showKeyboard ? (
          <Keyboard lang={lang} onKey={typeKey} onSend={submit} />
        ) : (
          <div className="dm-hint-band" data-dm-hint data-dm-cover>
            <span data-text>{typing ? hint : c.sheetHint}</span>
          </div>
        ))}
      {!open && (
        <div className="dm-dock">
          <div className="dm-bar" data-dm-bar>
            {field}
          </div>
          <nav className="dm-pill" aria-label="Tabs">
            <span className="dm-tab dm-tab--on">
              <DmIcon name="cart" />
              <span data-text>{c.tabs[0]}</span>
            </span>
            <span className="dm-tab">
              <DmIcon name="menu" />
              <span data-text>{c.tabs[1]}</span>
            </span>
          </nav>
        </div>
      )}
    </div>
  );
}
