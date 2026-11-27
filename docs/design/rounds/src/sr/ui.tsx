// Shared phone widgets for round SR, drawn after the app's soft look (RD1): 2 px contours,
// rounded corners by size, and a hard drop edge on buttons only.

import { useEffect, useRef } from 'react';
import type { ReactNode } from 'react';
import { C, WEEKDAYS, dayLong, dayShort, hhmm } from './model';
import type { Lang, Offset, Weekday } from './model';

const PATHS = {
  arrow_back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
  add: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  close:
    'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  check: 'M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
  chevron_right: 'M10 6 8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z',
  delete:
    'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM8 9h8v10H8V9zm7.5-5-1-1h-5l-1 1H5v2h14V4z',
  schedule:
    'M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z',
  moon: 'M9.27 4.49c-1.63 7.54 3.75 12.41 7.66 13.8A7.94 7.94 0 0 1 12 20c-4.41 0-8-3.59-8-8 0-3.45 2.2-6.4 5.27-7.51m2.72-2.48C6.4 2.01 2 6.54 2 12c0 5.52 4.48 10 10 10 3.05 0 5.78-1.37 7.62-3.52-7.27-.52-12.2-8.21-7.63-16.47z',
  sun: 'M6.76 4.84 4.96 3.05 3.55 4.46l1.79 1.79zM1 10.5h3v2H1zM11 .55h2V3.5h-2zm8.04 2.495 1.408 1.407-1.79 1.79-1.407-1.408zm-1.8 15.115 1.79 1.8 1.41-1.41-1.8-1.79zM20 10.5h3v2h-3zm-8-5c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 10c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm-1 4h2v2.95h-2zm-7.45-.96 1.41 1.41 1.79-1.8-1.41-1.41z',
  cart: 'M15.55 13c.75 0 1.41-.41 1.75-1.03l3.58-6.49A.996.996 0 0 0 20.01 4H5.21l-.94-2H1v2h2l3.6 7.59-1.35 2.44C4.52 15.37 5.48 17 7 17h12v-2H7l1.1-2h7.45zM6.16 6h12.15l-2.76 5H8.53L6.16 6zM7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zm10 0c-1.1 0-1.99.9-1.99 2s.89 2 1.99 2 2-.9 2-2-.9-2-2-2z',
  history:
    'M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42A8.954 8.954 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z',
  menu: 'M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z',
  bell: 'M12 22c1.1 0 2-.9 2-2h-4c0 1.1.89 2 2 2zm6-6v-5c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2zm-2 1H8v-6c0-2.48 1.51-4.5 4-4.5s4 2.02 4 4.5v6z',
  visibility_off:
    'M12 6a9.77 9.77 0 0 1 8.82 5.5 9.647 9.647 0 0 1-2.41 3.12l1.41 1.41c1.39-1.23 2.49-2.77 3.18-4.53C21.27 7.11 17 4 12 4c-1.27 0-2.49.2-3.64.57l1.65 1.65C10.66 6.09 11.32 6 12 6zm-1.07 1.14L13 9.21c.57.25 1.03.71 1.28 1.28l2.07 2.07c.08-.34.14-.7.14-1.07C16.5 9.01 14.48 7 12 7c-.37 0-.72.05-1.07.14zM2.01 3.87l2.68 2.68A11.738 11.738 0 0 0 1 11.5C2.73 15.89 7 19 12 19c1.52 0 2.98-.29 4.32-.82l3.42 3.42 1.41-1.41L3.42 2.45 2.01 3.87zm7.5 7.5 2.61 2.61c-.04.01-.08.02-.12.02a2.5 2.5 0 0 1-2.5-2.5c0-.05.01-.08.01-.13zm-3.4-3.4 1.75 1.75a4.6 4.6 0 0 0-.36 1.78 4.507 4.507 0 0 0 6.27 4.14l.98.98c-.88.24-1.8.38-2.75.38a9.77 9.77 0 0 1-8.82-5.5c.7-1.43 1.72-2.61 2.93-3.53z',
} as const;

export type IconName = keyof typeof PATHS;

export function Icon({ name, className }: { name: IconName; className?: string }) {
  return (
    <svg className={className ? `sr-icon ${className}` : 'sr-icon'} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={PATHS[name]} fill="currentColor" />
    </svg>
  );
}

export const offsetIcon = (o: Offset): IconName => (o === 'before' ? 'moon' : 'sun');

export function SectionLabel({ children }: { children: string }) {
  return (
    <h2 className="sr-label" aria-label={children}>
      <span>{children.toUpperCase().replaceAll('ß', 'SS')}</span>
      <i aria-hidden="true" />
    </h2>
  );
}

export function Group({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={className ? `sr-group ${className}` : 'sr-group'}>{children}</div>;
}

export function Button({
  children,
  tone = 'plain',
  icon,
  onClick,
  disabled,
  wide,
  label,
  testId,
}: {
  children: ReactNode;
  tone?: 'plain' | 'primary' | 'ghost' | 'danger';
  icon?: IconName;
  onClick?: () => void;
  disabled?: boolean;
  wide?: boolean;
  label?: string;
  testId?: string;
}) {
  return (
    <button
      type="button"
      className={`sr-btn sr-btn--${tone}${wide ? ' sr-btn--wide' : ''}`}
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      data-testid={testId}
    >
      {icon && <Icon name={icon} />}
      <span>{children}</span>
    </button>
  );
}

export function Switch({ on, onToggle, label }: { on: boolean; onToggle: () => void; label: string }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} className="sr-switch" onClick={onToggle}>
      <i aria-hidden="true" />
    </button>
  );
}

/** Weekday chips: one day ([multi] false) or several. */
export function DayChips({
  lang,
  selected,
  onToggle,
  multi,
  name,
}: {
  lang: Lang;
  selected: ReadonlySet<Weekday>;
  onToggle: (d: Weekday) => void;
  multi: boolean;
  name: string;
}) {
  return (
    <div className="sr-days" role={multi ? 'group' : 'radiogroup'} aria-label={name}>
      {WEEKDAYS.map((d) => {
        const on = selected.has(d);
        return (
          <button
            key={d}
            type="button"
            className="sr-day"
            role={multi ? 'checkbox' : 'radio'}
            aria-checked={on}
            aria-label={dayLong(lang, d)}
            onClick={() => onToggle(d)}
          >
            {on && multi && <Icon name="check" />}
            {dayShort(lang, d)}
          </button>
        );
      })}
    </div>
  );
}

export function OffsetSeg({ lang, value, onChange }: { lang: Lang; value: Offset; onChange: (o: Offset) => void }) {
  const c = C[lang];
  return (
    <div className="sr-seg" role="radiogroup" aria-label={c.when}>
      {(['before', 'same'] as const).map((o) => (
        <button key={o} type="button" role="radio" aria-checked={value === o} onClick={() => onChange(o)}>
          <Icon name={offsetIcon(o)} />
          <span>{o === 'before' ? c.before : c.same}</span>
        </button>
      ))}
    </div>
  );
}

const HOURS = Array.from({ length: 24 }, (_, h) => h);
const MINUTES = Array.from({ length: 12 }, (_, i) => i * 5);
const pad2 = (n: number) => String(n).padStart(2, '0');

/** One tap for the hour, one for the minute; the time it shows is what gets saved. */
export function TimePicker({ lang, value, onChange }: { lang: Lang; value: number; onChange: (m: number) => void }) {
  const c = C[lang];
  const h = Math.floor(value / 60);
  const m = value % 60;
  return (
    <div className="sr-time">
      <p className="sr-time-value" aria-live="polite">
        <Icon name="schedule" />
        <span data-testid="time-value">{hhmm(value)}</span>
      </p>
      <div className="sr-time-grid sr-time-hours" role="radiogroup" aria-label={c.hour}>
        {HOURS.map((hour) => (
          <button
            key={hour}
            type="button"
            role="radio"
            aria-checked={hour === h}
            aria-label={`${c.hour} ${pad2(hour)}`}
            onClick={() => onChange(hour * 60 + m)}
          >
            {pad2(hour)}
          </button>
        ))}
      </div>
      <div className="sr-time-grid sr-time-minutes" role="radiogroup" aria-label={c.minute}>
        {MINUTES.map((minute) => (
          <button
            key={minute}
            type="button"
            role="radio"
            aria-checked={minute === m}
            aria-label={`${c.minute} ${pad2(minute)}`}
            onClick={() => onChange(h * 60 + minute)}
          >
            :{pad2(minute)}
          </button>
        ))}
      </div>
    </div>
  );
}

/** A bottom sheet inside the phone: scrim, handle, title, scrolling body, sticky actions. */
export function Sheet({
  title,
  onClose,
  children,
  actions,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  actions: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    ref.current?.focus();
  }, []);
  return (
    <div className="sr-sheet-layer">
      <div className="sr-scrim" aria-hidden="true" onClick={onClose} />
      <div className="sr-sheet" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={ref}>
        <span className="sr-sheet-handle" aria-hidden="true" />
        <h3 className="sr-sheet-title">{title}</h3>
        <div className="sr-sheet-body">{children}</div>
        <div className="sr-sheet-actions">{actions}</div>
      </div>
    </div>
  );
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="sr-field">
      <p className="sr-field-label">{label}</p>
      {children}
    </div>
  );
}

/** The push the reminder sends, as the lock screen shows it. */
export function NotificationPreview({ lang, offset }: { lang: Lang; offset: Offset }) {
  const c = C[lang];
  return (
    <div className="sr-notif" aria-label={offset === 'before' ? c.notifBefore : c.notifSame}>
      <span className="sr-notif-app" aria-hidden="true">
        <Icon name="cart" />
      </span>
      <span className="sr-notif-text">
        <b>{offset === 'before' ? c.notifBefore : c.notifSame}</b>
        <span>{c.notifBody}</span>
      </span>
    </div>
  );
}
