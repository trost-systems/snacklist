import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { C, byShoppingDay, explode } from './model';
import type { Lang, OptionId, Rule, Weekday } from './model';
import { Sr1, Sr2, Sr3, Sr4, Sr5, TodayOption } from './options';
import { Group, Icon, Switch } from './ui';
import type { IconName } from './ui';

export interface Fit {
  content: number;
  viewport: number;
  section: number;
}

const NOTICE_MS = 3200;

export function SrPhone({
  option,
  lang,
  now,
  rules,
  setRules,
  days,
  setDays,
  onFit,
}: {
  option: OptionId;
  lang: Lang;
  now: Date;
  rules: Rule[];
  setRules: (r: Rule[]) => void;
  days: Set<Weekday>;
  setDays: (d: Set<Weekday>) => void;
  onFit: (f: Fit) => void;
}) {
  const c = C[lang];
  const [householdAdd, setHouseholdAdd] = useState(true);
  const [nameHidden, setNameHidden] = useState(false);
  const [notice, setNotice] = useState<{ id: number; text: string } | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const notify = useCallback((text: string) => {
    if (text) setNotice({ id: Date.now(), text });
  }, []);

  useEffect(() => {
    if (!notice) return;
    const id = window.setTimeout(() => setNotice(null), NOTICE_MS);
    return () => window.clearTimeout(id);
  }, [notice]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const measure = () => {
      const section = el.querySelector<HTMLElement>('[data-section="reminders"]');
      onFit({
        content: Math.round(el.firstElementChild?.getBoundingClientRect().height ?? el.scrollHeight),
        viewport: Math.round(el.clientHeight),
        section: Math.round(section?.getBoundingClientRect().height ?? 0),
      });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    for (const child of Array.from(el.children)) ro.observe(child);
    return () => ro.disconnect();
  });

  const props = { lang, now, rules, setRules, notify };

  return (
    <div
      className="sr-phone"
      data-option={option}
      data-reminders={JSON.stringify(
        option === 'today' ? [...days].sort() : explode(rules).sort(byShoppingDay).map(({ day, offset, time }) => ({ day, offset, time })),
      )}
    >
      <div className="sr-screen">
        <div className="sr-status" aria-hidden="true">
          <span>9:41</span>
          <span className="sr-status-dots">
            <i />
            <i />
            <i />
          </span>
        </div>
        <header className="sr-appbar">
          <button type="button" className="sr-iconbtn" aria-label={c.back}>
            <Icon name="arrow_back" />
          </button>
          <h1 className="sr-appbar-title">{c.appBar}</h1>
        </header>
        <div className={`sr-scroll sr-scroll--${option}`} ref={scrollRef} data-testid="phone-scroll">
          <div className="sr-content">
            <Group className="sr-switches">
              <div className="sr-switch-row">
                <span className="sr-tile sr-tile--sunken" aria-hidden="true">
                  <Icon name="bell" />
                </span>
                <span className="sr-row-text">
                  <span className="sr-row-title">{c.householdAdd}</span>
                  <span className="sr-row-sub">{c.householdAddHint}</span>
                </span>
                <Switch on={householdAdd} onToggle={() => setHouseholdAdd((v) => !v)} label={c.householdAdd} />
              </div>
              <div className="sr-switch-row">
                <span className="sr-tile sr-tile--sunken" aria-hidden="true">
                  <Icon name="visibility_off" />
                </span>
                <span className="sr-row-text">
                  <span className="sr-row-title">{c.nameHidden}</span>
                  <span className="sr-row-sub">{c.nameHiddenHint}</span>
                </span>
                <Switch on={nameHidden} onToggle={() => setNameHidden((v) => !v)} label={c.nameHidden} />
              </div>
            </Group>
            {option === 'today' && <TodayOption lang={lang} days={days} setDays={setDays} />}
            {option === 'sr1' && <Sr1 {...props} />}
            {option === 'sr2' && <Sr2 {...props} />}
            {option === 'sr3' && <Sr3 {...props} />}
            {option === 'sr4' && <Sr4 {...props} />}
            {option === 'sr5' && <Sr5 {...props} />}
          </div>
        </div>
        {notice && (
          <div key={notice.id} className="sr-snack" role="status">
            {notice.text}
          </div>
        )}
        <nav className="sr-tabs" aria-label="Tabs">
          {(['cart', 'history', 'menu'] as IconName[]).map((icon, i) => (
            <span key={icon} className="sr-tab" aria-current={i === 2 ? 'page' : undefined}>
              <span className="sr-tab-pill">
                <Icon name={icon} />
              </span>
              <span className="sr-tab-label">{c.tabs[i]}</span>
            </span>
          ))}
        </nav>
        <span className="sr-home" aria-hidden="true" />
      </div>
    </div>
  );
}
