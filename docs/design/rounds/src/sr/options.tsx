import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  C,
  CAP,
  DEFAULT_OFFSET,
  DEFAULT_TIME,
  addSingles,
  byShoppingDay,
  dateShort,
  dayLong,
  dayShort,
  explode,
  firingWhen,
  hhmm,
  newId,
  nextFiring,
  offsetLabel,
  reminderCount,
  reminderLine,
  sameReminder,
  sortDays,
  upcoming,
  WEEKDAYS,
} from './model';
import type { Firing, Lang, Offset, Reminder, Rule, Weekday } from './model';
import {
  Button,
  DayChips,
  Field,
  Group,
  Icon,
  NotificationPreview,
  OffsetSeg,
  SectionLabel,
  Sheet,
  TimePicker,
  offsetIcon,
} from './ui';

export interface OptionProps {
  lang: Lang;
  now: Date;
  rules: Rule[];
  setRules: (rules: Rule[]) => void;
  notify: (text: string) => void;
}

/* ---------- Shared behaviour ---------- */

/** Scrolls an inline composer into the phone's view when it opens or switches target. */
function useReveal(key: string | null) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (key !== null) ref.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }, [key]);
  return ref;
}

function firstFiringText(lang: Lang, reminders: Reminder[], now: Date): string {
  const first = reminders.map((r) => nextFiring(r, now)).sort((a, b) => a.at.getTime() - b.at.getTime())[0];
  if (!first) return '';
  const passed = first.rolledOver ? ` (${C[lang].passedToday(hhmm(first.time))})` : '';
  return C[lang].savedFirst(firingWhen(lang, first, now) + passed);
}

function nextLine(lang: Lang, f: Firing, now: Date): string {
  const c = C[lang];
  const base = `${c.next}: ${firingWhen(lang, f, now)}`;
  return f.rolledOver ? `${base} · ${c.passedToday(hhmm(f.time))}` : base;
}

type Draft = { day: Weekday | null; offset: Offset; time: number };
const NEW_DRAFT: Draft = { day: null, offset: DEFAULT_OFFSET, time: DEFAULT_TIME };

/** Saves one single-day reminder, new ([editing] null) or replacing a rule; refuses duplicates and the cap. */
function saveSingle(p: OptionProps, editing: string | null, day: Weekday, offset: Offset, time: number): boolean {
  const c = C[p.lang];
  const others = editing ? p.rules.filter((r) => r.id !== editing) : p.rules;
  if (explode(others).some((r) => sameReminder(r, { day, offset, time }))) {
    p.notify(c.duplicate);
    return false;
  }
  if (!editing && reminderCount(p.rules) >= CAP) {
    p.notify(c.capReached);
    return false;
  }
  const rule: Rule = { id: editing ?? newId(), days: [day], offset, time };
  p.setRules(editing ? p.rules.map((r) => (r.id === editing ? rule : r)) : [...p.rules, rule]);
  p.notify(firstFiringText(p.lang, [{ ruleId: rule.id, day, offset, time }], p.now));
  return true;
}

function remove(p: OptionProps, id: string) {
  p.setRules(p.rules.filter((r) => r.id !== id));
  p.notify(C[p.lang].deleted);
}

const atCap = (rules: Rule[]) => reminderCount(rules) >= CAP;

function CapLine({ lang, rules }: { lang: Lang; rules: Rule[] }) {
  return atCap(rules) ? <p className="sr-cap" role="status">{C[lang].capReached}</p> : null;
}

/** The sheet SR1, SR3 and SR5 use: one shopping day, the offset, the time. */
function ReminderSheet({
  lang,
  now,
  draft: initial,
  editing,
  fixedDays,
  onSave,
  onDelete,
  onClose,
}: {
  lang: Lang;
  now: Date;
  draft: Draft;
  editing: boolean;
  /** SR3's custom time: the days come from the chips, so the sheet only names them. */
  fixedDays?: Weekday[];
  onSave: (d: Draft) => void;
  onDelete?: () => void;
  onClose: () => void;
}) {
  const c = C[lang];
  const [draft, setDraft] = useState(initial);
  const previewDay = fixedDays?.[0] ?? draft.day;
  const preview = previewDay ? nextFiring({ ruleId: '', day: previewDay, offset: draft.offset, time: draft.time }, now) : null;
  return (
    <Sheet
      title={editing ? c.editReminder : c.newReminder}
      onClose={onClose}
      actions={
        <>
          {onDelete ? (
            <Button tone="danger" icon="delete" onClick={onDelete}>
              {c.delete}
            </Button>
          ) : (
            <Button tone="ghost" onClick={onClose}>
              {c.cancel}
            </Button>
          )}
          <Button tone="primary" disabled={!fixedDays && draft.day === null} onClick={() => onSave(draft)} testId="sheet-save">
            {c.save}
          </Button>
        </>
      }
    >
      {fixedDays ? (
        <Field label={c.shoppingDays}>
          <p className="sr-fixed-days">{fixedDays.map((d) => dayLong(lang, d)).join(', ')}</p>
        </Field>
      ) : (
        <Field label={c.shoppingDay}>
          <DayChips
            lang={lang}
            multi={false}
            name={c.shoppingDay}
            selected={new Set(draft.day ? [draft.day] : [])}
            onToggle={(d) => setDraft({ ...draft, day: d })}
          />
        </Field>
      )}
      <Field label={c.when}>
        <OffsetSeg lang={lang} value={draft.offset} onChange={(offset) => setDraft({ ...draft, offset })} />
      </Field>
      <Field label={c.time}>
        <TimePicker lang={lang} value={draft.time} onChange={(time) => setDraft({ ...draft, time })} />
      </Field>
      {preview && (
        <p className="sr-preview-line">
          {c.fires}: {firingWhen(lang, preview, now)}
          {preview.rolledOver ? ` · ${c.passedToday(hhmm(preview.time))}` : ''}
        </p>
      )}
    </Sheet>
  );
}

function Row({
  icon,
  title,
  sub,
  onClick,
  trailing,
  testId,
}: {
  icon: Offset;
  title: string;
  sub: string;
  onClick: () => void;
  trailing?: ReactNode;
  testId?: string;
}) {
  return (
    <div className="sr-row" data-testid={testId}>
      <button type="button" className="sr-row-main" onClick={onClick}>
        <span className={`sr-tile sr-tile--${icon}`} aria-hidden="true">
          <Icon name={offsetIcon(icon)} />
        </span>
        <span className="sr-row-text">
          <span className="sr-row-title">{title}</span>
          <span className="sr-row-sub">{sub}</span>
        </span>
        {!trailing && <Icon name="chevron_right" className="sr-row-chev" />}
      </button>
      {trailing}
    </div>
  );
}

/* ---------- Today (production, job 378) ---------- */

export function TodayOption({ lang, days, setDays }: { lang: Lang; days: Set<Weekday>; setDays: (d: Set<Weekday>) => void }) {
  const c = C[lang];
  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.todayTitle}</SectionLabel>
      <Group>
        <div className="sr-pad">
          <p className="sr-body">{c.todayHint}</p>
          <div className="sr-filter-chips" role="group" aria-label={c.todayTitle}>
            {WEEKDAYS.map((d) => {
              const on = days.has(d);
              return (
                <button
                  key={d}
                  type="button"
                  className="sr-filter"
                  role="checkbox"
                  aria-checked={on}
                  aria-label={dayLong(lang, d)}
                  onClick={() => {
                    const next = new Set(days);
                    if (on) next.delete(d);
                    else next.add(d);
                    setDays(next);
                  }}
                >
                  {on && <Icon name="check" />}
                  {dayShort(lang, d)}
                </button>
              );
            })}
          </div>
        </div>
      </Group>
    </section>
  );
}

/* ---------- SR1: reminder list + add sheet ---------- */

export function Sr1(p: OptionProps) {
  const { lang, now, rules } = p;
  const c = C[lang];
  const [sheet, setSheet] = useState<{ id: string | null; draft: Draft } | null>(null);
  const reminders = explode(rules).sort(byShoppingDay);
  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.title}</SectionLabel>
      {reminders.length === 0 ? (
        <div className="sr-empty">
          <p className="sr-body sr-muted">{c.empty}</p>
          <Button icon="add" tone="primary" onClick={() => setSheet({ id: null, draft: NEW_DRAFT })}>
            {c.addReminder}
          </Button>
        </div>
      ) : (
        <Group>
          {reminders.map((r) => (
            <Row
              key={r.ruleId}
              icon={r.offset}
              title={reminderLine(lang, r)}
              sub={nextLine(lang, nextFiring(r, now), now)}
              onClick={() => setSheet({ id: r.ruleId, draft: { day: r.day, offset: r.offset, time: r.time } })}
            />
          ))}
          <button type="button" className="sr-row-add" disabled={atCap(rules)} onClick={() => setSheet({ id: null, draft: NEW_DRAFT })}>
            <Icon name="add" />
            <span>{c.addReminder}</span>
          </button>
        </Group>
      )}
      <CapLine lang={lang} rules={rules} />
      {sheet && (
        <ReminderSheet
          lang={lang}
          now={now}
          draft={sheet.draft}
          editing={sheet.id !== null}
          onClose={() => setSheet(null)}
          onDelete={sheet.id ? () => (remove(p, sheet.id ?? ''), setSheet(null)) : undefined}
          onSave={(d) => {
            if (d.day && saveSingle(p, sheet.id, d.day, d.offset, d.time)) setSheet(null);
          }}
        />
      )}
    </section>
  );
}

/* ---------- SR2: week map ---------- */

export function Sr2(p: OptionProps) {
  const { lang, now, rules } = p;
  const c = C[lang];
  const [composer, setComposer] = useState<{ day: Weekday; id: string | null; offset: Offset; time: number } | null>(null);
  const reveal = useReveal(composer ? `${composer.day}${composer.id}` : null);
  const reminders = explode(rules).sort(byShoppingDay);
  const shopDays = sortDays(reminders.map((r) => r.day));
  const next = upcoming(rules, now)[0];
  const openDay = (day: Weekday) => {
    if (composer?.day === day && composer.id === null) setComposer(null);
    else setComposer({ day, id: null, offset: DEFAULT_OFFSET, time: DEFAULT_TIME });
  };
  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.title}</SectionLabel>
      <Group className="sr-week">
        <p className="sr-body sr-muted sr-pad-x">{c.weekHint}</p>
        <div className="sr-strip" role="group" aria-label={c.shoppingDays}>
          {WEEKDAYS.map((d) => {
            const count = reminders.filter((r) => r.day === d).length;
            return (
              <button
                key={d}
                type="button"
                className="sr-strip-day"
                aria-label={`${dayLong(lang, d)}${count ? `, ${count}` : ''}`}
                aria-pressed={composer?.day === d}
                data-shop={count > 0}
                onClick={() => openDay(d)}
              >
                <span>{dayShort(lang, d)}</span>
                <span className="sr-strip-dots" aria-hidden="true">
                  {count === 0 ? <Icon name="add" /> : Array.from({ length: Math.min(count, 3) }, (_, i) => <i key={i} />)}
                </span>
              </button>
            );
          })}
        </div>
        {composer && (
          <div ref={reveal} className="sr-composer" role="group" aria-label={composer.id ? c.editFor(dayLong(lang, composer.day)) : c.addTo(dayLong(lang, composer.day))}>
            <p className="sr-composer-title">
              {composer.id ? c.editFor(dayLong(lang, composer.day)) : c.addTo(dayLong(lang, composer.day))}
            </p>
            <OffsetSeg lang={lang} value={composer.offset} onChange={(offset) => setComposer({ ...composer, offset })} />
            <TimePicker lang={lang} value={composer.time} onChange={(time) => setComposer({ ...composer, time })} />
            <div className="sr-actions">
              {composer.id ? (
                <Button tone="danger" icon="delete" onClick={() => (remove(p, composer.id ?? ''), setComposer(null))}>
                  {c.delete}
                </Button>
              ) : (
                <Button tone="ghost" onClick={() => setComposer(null)}>
                  {c.cancel}
                </Button>
              )}
              <Button
                tone="primary"
                testId="composer-save"
                disabled={!composer.id && atCap(rules)}
                onClick={() => {
                  if (saveSingle(p, composer.id, composer.day, composer.offset, composer.time)) setComposer(null);
                }}
              >
                {composer.id ? c.save : c.add}
              </Button>
            </div>
          </div>
        )}
        {shopDays.map((d) => (
          <div key={d} className="sr-dayblock">
            <p className="sr-dayblock-name">{dayLong(lang, d)}</p>
            <div className="sr-timechips">
              {reminders
                .filter((r) => r.day === d)
                .map((r) => (
                  <button
                    key={r.ruleId}
                    type="button"
                    className={`sr-timechip sr-timechip--${r.offset}`}
                    aria-pressed={composer?.id === r.ruleId}
                    onClick={() => setComposer({ day: d, id: r.ruleId, offset: r.offset, time: r.time })}
                  >
                    <Icon name={offsetIcon(r.offset)} />
                    <span>
                      {offsetLabel(lang, r.offset)} · <b>{hhmm(r.time)}</b>
                      {nextFiring(r, now).rolledOver && <span className="sr-timechip-note"> · {c.nextWeek}</span>}
                    </span>
                  </button>
                ))}
            </div>
          </div>
        ))}
        {next && (
          <p className="sr-next-foot">
            <Icon name="bell" />
            <span>
              {nextLine(lang, next, now)} · {c.forShop(dayLong(lang, next.day))}
            </span>
          </p>
        )}
      </Group>
      <CapLine lang={lang} rules={rules} />
    </section>
  );
}

/* ---------- SR3: presets first ---------- */

const PRESETS: readonly { offset: Offset; time: number }[] = [
  { offset: 'before', time: 20 * 60 },
  { offset: 'before', time: 18 * 60 },
  { offset: 'same', time: 9 * 60 + 15 },
];

export function Sr3(p: OptionProps) {
  const { lang, now, rules } = p;
  const c = C[lang];
  const [days, setDays] = useState<Set<Weekday>>(new Set());
  const [sheet, setSheet] = useState<{ id: string | null; draft: Draft } | null>(null);
  const reminders = explode(rules).sort(byShoppingDay);
  const picked = sortDays([...days]);
  const presetLabel = (o: Offset, time: number) => `${o === 'before' ? c.eveningBefore : c.morningOf} · ${hhmm(time)}`;

  const apply = (offset: Offset, time: number) => {
    if (picked.length === 0) {
      p.notify(c.pickDayFirst);
      return;
    }
    const res = addSingles(rules, picked, offset, time);
    if (res.added.length === 0) {
      p.notify(res.capped ? c.capReached : c.duplicate);
      return;
    }
    p.setRules(res.rules);
    p.notify(firstFiringText(lang, res.added, now));
  };

  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.title}</SectionLabel>
      <Group>
        <div className="sr-pad">
          <p className="sr-body sr-muted">{c.quickHint}</p>
          <DayChips
            lang={lang}
            multi
            name={c.shoppingDays}
            selected={days}
            onToggle={(d) => {
              const next = new Set(days);
              if (next.has(d)) next.delete(d);
              else next.add(d);
              setDays(next);
            }}
          />
        </div>
        <div className="sr-presets">
          {PRESETS.map((pr) => {
            const has = picked.length > 0 && picked.every((day) => reminders.some((r) => sameReminder(r, { day, ...pr })));
            return (
              <button
                key={`${pr.offset}${pr.time}`}
                type="button"
                className="sr-preset"
                data-has={has}
                disabled={atCap(rules)}
                onClick={() => apply(pr.offset, pr.time)}
              >
                <Icon name={offsetIcon(pr.offset)} />
                <span>{presetLabel(pr.offset, pr.time)}</span>
                {has ? <Icon name="check" className="sr-preset-end" /> : <Icon name="add" className="sr-preset-end" />}
              </button>
            );
          })}
          <button
            type="button"
            className="sr-preset sr-preset--custom"
            disabled={atCap(rules)}
            onClick={() => (picked.length ? setSheet({ id: null, draft: { ...NEW_DRAFT } }) : p.notify(c.pickDayFirst))}
          >
            <Icon name="schedule" />
            <span>{c.customTime}</span>
            <Icon name="chevron_right" className="sr-preset-end" />
          </button>
        </div>
      </Group>
      <CapLine lang={lang} rules={rules} />
      {reminders.length > 0 && (
        <>
          <p className="sr-sublabel">{c.yourReminders}</p>
          <Group>
            {reminders.map((r) => (
              <Row
                key={r.ruleId}
                icon={r.offset}
                title={reminderLine(lang, r)}
                sub={nextLine(lang, nextFiring(r, now), now)}
                onClick={() => setSheet({ id: r.ruleId, draft: { day: r.day, offset: r.offset, time: r.time } })}
                trailing={
                  <button type="button" className="sr-row-x" aria-label={`${c.delete}: ${reminderLine(lang, r)}`} onClick={() => remove(p, r.ruleId)}>
                    <Icon name="close" />
                  </button>
                }
              />
            ))}
          </Group>
        </>
      )}
      {sheet && (
        <ReminderSheet
          lang={lang}
          now={now}
          draft={sheet.draft}
          editing={sheet.id !== null}
          fixedDays={sheet.id ? undefined : picked}
          onClose={() => setSheet(null)}
          onDelete={sheet.id ? () => (remove(p, sheet.id ?? ''), setSheet(null)) : undefined}
          onSave={(d) => {
            if (sheet.id) {
              if (d.day && saveSingle(p, sheet.id, d.day, d.offset, d.time)) setSheet(null);
              return;
            }
            apply(d.offset, d.time);
            setSheet(null);
          }}
        />
      )}
    </section>
  );
}

/* ---------- SR4: multi-day rules ---------- */

export function Sr4(p: OptionProps) {
  const { lang, now, rules } = p;
  const c = C[lang];
  const [composer, setComposer] = useState<{ id: string | null; days: Set<Weekday>; offset: Offset; time: number } | null>(null);
  const empty = rules.length === 0;
  const reveal = useReveal(composer ? composer.id ?? 'new' : null);
  const fresh = { id: null, days: new Set<Weekday>(), offset: DEFAULT_OFFSET, time: DEFAULT_TIME };
  const shown = composer ?? (empty ? fresh : null);
  const sorted = [...rules].sort((a, b) => (a.offset === b.offset ? a.time - b.time : a.offset === 'before' ? -1 : 1));

  const save = () => {
    if (!shown) return;
    const days = sortDays([...shown.days]);
    const others = shown.id ? rules.filter((r) => r.id !== shown.id) : rules;
    const fresh = days.filter((day) => !explode(others).some((r) => sameReminder(r, { day, offset: shown.offset, time: shown.time })));
    if (fresh.length === 0) {
      p.notify(c.duplicate);
      return;
    }
    if (reminderCount(others) + fresh.length > CAP) {
      p.notify(c.capReached);
      return;
    }
    const rule: Rule = { id: shown.id ?? newId(), days: fresh, offset: shown.offset, time: shown.time };
    p.setRules(shown.id ? rules.map((r) => (r.id === shown.id ? rule : r)) : [...rules, rule]);
    p.notify(firstFiringText(lang, explode([rule]), now));
    setComposer(null);
  };

  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.title}</SectionLabel>
      {!empty && (
        <Group>
          {sorted.map((r) => {
            const first = upcoming([r], now)[0];
            return (
              <Row
                key={r.id}
                icon={r.offset}
                title={c.ruleSentence(r.offset, hhmm(r.time))}
                sub={`${c.onDays} ${r.days.map((d) => dayShort(lang, d)).join(', ')}${first ? ` · ${nextLine(lang, first, now)}` : ''}`}
                onClick={() => setComposer({ id: r.id, days: new Set(r.days), offset: r.offset, time: r.time })}
              />
            );
          })}
          {!shown && (
            <button type="button" className="sr-row-add" disabled={atCap(rules)} onClick={() => setComposer(fresh)}>
              <Icon name="add" />
              <span>{c.newRule}</span>
            </button>
          )}
        </Group>
      )}
      {shown && (
        <div ref={reveal}>
        <Group className="sr-rule-composer">
          <div className="sr-pad sr-stack">
            <p className="sr-composer-title">{empty ? c.firstRule : shown.id ? c.editRule : c.newRule}</p>
            {empty && <p className="sr-body sr-muted">{c.rulesHint}</p>}
            <OffsetSeg lang={lang} value={shown.offset} onChange={(offset) => setComposer({ ...shown, offset })} />
            <TimePicker lang={lang} value={shown.time} onChange={(time) => setComposer({ ...shown, time })} />
            <Field label={c.onDays}>
              <DayChips
                lang={lang}
                multi
                name={c.shoppingDays}
                selected={shown.days}
                onToggle={(d) => {
                  const days = new Set(shown.days);
                  if (days.has(d)) days.delete(d);
                  else days.add(d);
                  setComposer({ ...shown, days });
                }}
              />
            </Field>
            <p className="sr-preview-line">
              {shown.days.size > 0
                ? `${c.ruleSentence(shown.offset, hhmm(shown.time))} · ${sortDays([...shown.days])
                    .map((d) => dayLong(lang, d))
                    .join(', ')}`
                : c.pickDayFirst}
            </p>
            <div className="sr-actions">
              {shown.id ? (
                <Button tone="danger" icon="delete" onClick={() => (remove(p, shown.id ?? ''), setComposer(null))}>
                  {c.delete}
                </Button>
              ) : empty ? (
                <span />
              ) : (
                <Button tone="ghost" onClick={() => setComposer(null)}>
                  {c.cancel}
                </Button>
              )}
              <Button tone="primary" testId="rule-save" disabled={shown.days.size === 0} onClick={save}>
                {c.saveRule}
              </Button>
            </div>
          </div>
        </Group>
        </div>
      )}
      <CapLine lang={lang} rules={rules} />
    </section>
  );
}

/* ---------- SR5: next-up timeline ---------- */

export function Sr5(p: OptionProps) {
  const { lang, now, rules } = p;
  const c = C[lang];
  const [sheet, setSheet] = useState<{ id: string | null; draft: Draft } | null>(null);
  const firings = upcoming(rules, now);
  const [first, ...rest] = firings;
  const open = (f: Firing) => setSheet({ id: f.ruleId, draft: { day: f.day, offset: f.offset, time: f.time } });
  return (
    <section className="sr-section" data-section="reminders">
      <SectionLabel>{c.title}</SectionLabel>
      {first ? (
        <Group className="sr-hero">
          <button type="button" className="sr-hero-main" onClick={() => open(first)}>
            <span className="sr-hero-kicker">{c.nextUp}</span>
            <span className="sr-hero-when">
              {firingWhen(lang, first, now)}
            </span>
            <span className="sr-hero-for">
              <Icon name={offsetIcon(first.offset)} />
              {c.forShop(dayLong(lang, first.day))}
            </span>
          </button>
          <NotificationPreview lang={lang} offset={first.offset} />
        </Group>
      ) : (
        <Group className="sr-hero sr-hero--empty">
          <div className="sr-pad sr-stack">
            <p className="sr-hero-when">{c.noneYet}</p>
            <p className="sr-body sr-muted">{c.noneYetHint}</p>
          </div>
        </Group>
      )}
      {rest.length > 0 && (
        <>
          <p className="sr-sublabel">{c.upcomingWeek}</p>
          <Group>
            {rest.map((f) => (
              <button key={f.ruleId} type="button" className="sr-tl-row" onClick={() => open(f)}>
                <span className="sr-tl-date">
                  <b>{hhmm(f.time)}</b>
                  <span>{dateShort(lang, f.at)}</span>
                </span>
                <span className="sr-row-text">
                  <span className="sr-row-title">
                    <Icon name={offsetIcon(f.offset)} />
                    {dayLong(lang, f.day)} · {offsetLabel(lang, f.offset).toLowerCase()}
                  </span>
                  {f.rolledOver && (
                    <span className="sr-tl-tag">
                      {c.nextWeek} · {c.passedToday(hhmm(f.time))}
                    </span>
                  )}
                </span>
                <Icon name="chevron_right" className="sr-row-chev" />
              </button>
            ))}
          </Group>
        </>
      )}
      <CapLine lang={lang} rules={rules} />
      <button
          type="button"
          className="sr-fab"
          disabled={atCap(rules)}
          onClick={() => setSheet({ id: null, draft: NEW_DRAFT })}
        >
          <Icon name="add" />
          <span>{c.addReminder}</span>
        </button>
      {sheet && (
        <ReminderSheet
          lang={lang}
          now={now}
          draft={sheet.draft}
          editing={sheet.id !== null}
          onClose={() => setSheet(null)}
          onDelete={sheet.id ? () => (remove(p, sheet.id ?? ''), setSheet(null)) : undefined}
          onSave={(d) => {
            if (d.day && saveSingle(p, sheet.id, d.day, d.offset, d.time)) setSheet(null);
          }}
        />
      )}
    </section>
  );
}
