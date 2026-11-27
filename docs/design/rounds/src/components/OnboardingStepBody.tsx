// The body of one onboarding step (everything below the progress bar), plus the hex
// controls it is built from. RD1: only HexButton casts a shadow; chips and fields are flat.

import { useId } from 'react';
import type { ButtonHTMLAttributes, Dispatch, ReactNode, SetStateAction } from 'react';
import {
  COPY,
  PRESET_STORE_IDS,
  STAPLE_IDS,
  WHO_IDS,
  audienceOf,
  householdNameFor,
  itemKey,
  itemLabel,
  storeKey,
  storeLabel,
  toggleWho,
} from '../data/onboardingSteps';
import type {
  FinishKind,
  Lang,
  ListItem,
  OnboardingState,
  SignInMethod,
  StepNumber,
  StoreRef,
} from '../data/onboardingSteps';
import { AppleMark, GoogleMark, Icon } from './Icons';
import type { IconName } from './Icons';

/* ---------- Hex controls ---------- */

type HexButtonTone = 'primary' | 'secondary' | 'ink';

type HexButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  tone?: HexButtonTone;
  icon?: ReactNode;
  block?: boolean;
  size?: 'm' | 's';
};

export function HexButton({
  tone = 'secondary',
  icon,
  block = false,
  size = 'm',
  className,
  children,
  type = 'button',
  ...rest
}: HexButtonProps) {
  const classes = ['hx', 'btn', `btn--${tone}`, `btn--${size}`, block ? 'btn--block' : '', className ?? '']
    .filter(Boolean)
    .join(' ');
  return (
    <button type={type} className={classes} {...rest}>
      {icon}
      {children !== undefined && <span className="hx-label">{children}</span>}
    </button>
  );
}

interface ChipProps {
  selected: boolean;
  onToggle: () => void;
  children: ReactNode;
  lead?: ReactNode;
}

export function Chip({ selected, onToggle, children, lead }: ChipProps) {
  return (
    <button type="button" className="hx chip" aria-pressed={selected} onClick={onToggle}>
      {lead ?? (selected ? <Icon name="check" /> : null)}
      <span className="hx-label">{children}</span>
    </button>
  );
}

interface HexFieldProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  onSubmit?: () => void;
  action?: ReactNode;
}

function HexField({ label, value, onChange, placeholder, onSubmit, action }: HexFieldProps) {
  const id = useId();
  return (
    <div className="field">
      <label className="field-label" htmlFor={id}>
        {label}
      </label>
      <div className="field-row">
        <div className="hx field-box">
          <input
            id={id}
            className="field-input"
            value={value}
            placeholder={placeholder}
            autoComplete="off"
            enterKeyHint={onSubmit ? 'done' : 'next'}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && onSubmit) {
                e.preventDefault();
                onSubmit();
              }
            }}
          />
        </div>
        {action}
      </div>
    </div>
  );
}

function HexBadge({ icon }: { icon: IconName }) {
  return (
    <div className="hex-badge" aria-hidden="true">
      <Icon name={icon} />
    </div>
  );
}

interface StepFrameProps {
  title: string;
  lead?: string;
  badge?: IconName;
  children?: ReactNode;
  actions: ReactNode;
}

function StepFrame({ title, lead, badge, children, actions }: StepFrameProps) {
  return (
    <div className="step">
      <div className="step-scroll">
        <div className="step-content">
          {badge && <HexBadge icon={badge} />}
          <h2 className="step-title" tabIndex={-1} data-step-heading="true">
            {title}
          </h2>
          {lead && <p className="step-lead">{lead}</p>}
          {children}
        </div>
      </div>
      <div className="step-actions">{actions}</div>
    </div>
  );
}

/* ---------- Steps ---------- */

export interface StepBodyProps {
  step: StepNumber;
  lang: Lang;
  state: OnboardingState;
  setState: Dispatch<SetStateAction<OnboardingState>>;
  onAdvance: () => void;
  onFinish: (kind: FinishKind) => void;
  onNotice: (text: string) => void;
}

export function OnboardingStepBody(props: StepBodyProps) {
  switch (props.step) {
    case 1:
      return <UsageStep {...props} />;
    case 2:
      return <WhoStep {...props} />;
    case 3:
      return <NameStep {...props} />;
    case 4:
      return <StoresStep {...props} />;
    case 5:
      return <NeedStep {...props} />;
    case 6:
      return <AccountStep {...props} />;
    case 7:
      return <InviteStep {...props} />;
  }
}

function UsageStep({ lang, setState, onAdvance, onNotice }: StepBodyProps) {
  const c = COPY[lang].usage;
  const choose = (analytics: OnboardingState['analytics']) => {
    setState((s) => ({ ...s, analytics }));
    onAdvance();
  };
  return (
    <StepFrame
      badge="query_stats"
      title={c.title}
      actions={
        <div className="actions-pair">
          <HexButton block onClick={() => choose('declined')}>
            {c.decline}
          </HexButton>
          <HexButton block onClick={() => choose('allowed')}>
            {c.allow}
          </HexButton>
        </div>
      }
    >
      <p className="step-body">
        {c.bodyBeforeLink}
        <a
          href="#privacy"
          className="inline-link"
          onClick={(e) => {
            e.preventDefault();
            onNotice(COPY[lang].notices.privacy);
          }}
        >
          {c.link}
        </a>
        {c.bodyAfterLink}
      </p>
    </StepFrame>
  );
}

function WhoStep({ lang, state, setState, onAdvance }: StepBodyProps) {
  const c = COPY[lang].who;
  return (
    <StepFrame
      title={c.title}
      lead={c.lead}
      actions={
        <>
          <HexButton tone="primary" block disabled={state.who.length === 0} onClick={onAdvance}>
            {c.continue}
          </HexButton>
          <HexButton block onClick={onAdvance}>
            {c.skip}
          </HexButton>
        </>
      }
    >
      <div className="chips" role="group" aria-label={c.title}>
        {WHO_IDS.map((id) => (
          <Chip
            key={id}
            selected={state.who.includes(id)}
            onToggle={() => setState((s) => ({ ...s, who: toggleWho(s.who, id) }))}
          >
            {c.options[id]}
          </Chip>
        ))}
      </div>
      {state.who.includes('other') && (
        <div className="reveal">
          <HexField
            label={c.otherLabel}
            value={state.whoOther}
            placeholder={c.otherPlaceholder}
            onChange={(whoOther) => setState((s) => ({ ...s, whoOther }))}
          />
        </div>
      )}
    </StepFrame>
  );
}

function NameStep({ lang, state, setState, onAdvance, onNotice }: StepBodyProps) {
  const c = COPY[lang].name;
  const name = householdNameFor(state, lang);
  const valid = name.trim().length > 0;
  return (
    <StepFrame
      title={c.title}
      lead={c.lead}
      actions={
        <>
          <HexButton tone="primary" block disabled={!valid} onClick={onAdvance}>
            {c.continue}
          </HexButton>
          <HexButton block onClick={() => onNotice(COPY[lang].notices.join)}>
            {c.join}
          </HexButton>
        </>
      }
    >
      <HexField
        label={c.label}
        value={name}
        onChange={(householdName) => setState((s) => ({ ...s, householdName }))}
        onSubmit={valid ? onAdvance : undefined}
      />
    </StepFrame>
  );
}

function StoresStep({ lang, state, setState, onAdvance }: StepBodyProps) {
  const c = COPY[lang].stores;
  const presets: StoreRef[] = PRESET_STORE_IDS.map((id) => ({ kind: 'preset', id }));
  const customs = state.stores.filter((s) => s.kind === 'custom');
  const position = (store: StoreRef) => state.stores.findIndex((s) => storeKey(s) === storeKey(store));

  const toggle = (store: StoreRef) =>
    setState((s) => {
      const key = storeKey(store);
      const has = s.stores.some((x) => storeKey(x) === key);
      return { ...s, stores: has ? s.stores.filter((x) => storeKey(x) !== key) : [...s.stores, store] };
    });

  const addOwn = () =>
    setState((s) => {
      const name = s.storeDraft.trim();
      if (!name) return s;
      const preset = PRESET_STORE_IDS.find((id) => c.names[id].toLowerCase() === name.toLowerCase());
      const store: StoreRef = preset ? { kind: 'preset', id: preset } : { kind: 'custom', name };
      const key = storeKey(store);
      const stores = s.stores.some((x) => storeKey(x) === key) ? s.stores : [...s.stores, store];
      return { ...s, stores, storeDraft: '' };
    });

  return (
    <StepFrame
      title={c.title}
      lead={c.lead}
      actions={
        <>
          <HexButton tone="primary" block disabled={state.stores.length === 0} onClick={onAdvance}>
            {c.continue}
          </HexButton>
          <HexButton block onClick={onAdvance}>
            {c.skip}
          </HexButton>
        </>
      }
    >
      <div className="chips" role="group" aria-label={c.title}>
        {[...presets, ...customs].map((store) => {
          const index = position(store);
          return (
            <Chip
              key={storeKey(store)}
              selected={index >= 0}
              onToggle={() => toggle(store)}
              lead={index >= 0 ? <span className="chip-order">{index + 1}</span> : undefined}
            >
              {storeLabel(store, lang)}
            </Chip>
          );
        })}
        <button
          type="button"
          className="hx chip chip--add"
          aria-expanded={state.storeFieldOpen}
          onClick={() => setState((s) => ({ ...s, storeFieldOpen: !s.storeFieldOpen }))}
        >
          <Icon name={state.storeFieldOpen ? 'close' : 'add'} />
          <span className="hx-label">{c.addOwn}</span>
        </button>
      </div>
      {state.storeFieldOpen && (
        <div className="reveal">
          <HexField
            label={c.fieldLabel}
            value={state.storeDraft}
            placeholder={c.fieldPlaceholder}
            onChange={(storeDraft) => setState((s) => ({ ...s, storeDraft }))}
            onSubmit={addOwn}
            action={
              <HexButton
                tone="primary"
                className="btn--icon"
                aria-label={c.add}
                icon={<Icon name="add" />}
                disabled={!state.storeDraft.trim()}
                onClick={addOwn}
              />
            }
          />
        </div>
      )}
      {state.stores.length > 1 && (
        <p className="order-line">
          <span className="order-line-label">{c.orderLabel}:</span>{' '}
          {state.stores.map((s) => storeLabel(s, lang)).join(' → ')}
        </p>
      )}
    </StepFrame>
  );
}

function NeedStep({ lang, state, setState, onAdvance }: StepBodyProps) {
  const c = COPY[lang].need;
  const has = (item: ListItem) => state.items.some((i) => itemKey(i) === itemKey(item));

  const toggle = (item: ListItem) =>
    setState((s) => {
      const key = itemKey(item);
      const present = s.items.some((i) => itemKey(i) === key);
      return { ...s, items: present ? s.items.filter((i) => itemKey(i) !== key) : [...s.items, item] };
    });

  const addTyped = () =>
    setState((s) => {
      const text = s.itemDraft.trim();
      if (!text) return s;
      const staple = STAPLE_IDS.find((id) => c.staples[id].toLowerCase() === text.toLowerCase());
      const item: ListItem = staple ? { kind: 'staple', id: staple } : { kind: 'custom', text };
      const key = itemKey(item);
      const items = s.items.some((i) => itemKey(i) === key) ? s.items : [...s.items, item];
      return { ...s, items, itemDraft: '' };
    });

  const n = state.items.length;
  return (
    <StepFrame
      title={c.title}
      lead={c.lead}
      actions={
        <HexButton tone="primary" block onClick={onAdvance}>
          {n > 0 ? c.continueWith(n) : c.continue}
        </HexButton>
      }
    >
      <div className="chips" role="group" aria-label={c.title}>
        {STAPLE_IDS.map((id) => {
          const item: ListItem = { kind: 'staple', id };
          return (
            <Chip key={id} selected={has(item)} onToggle={() => toggle(item)}>
              {c.staples[id]}
            </Chip>
          );
        })}
      </div>
      <HexField
        label={c.fieldLabel}
        value={state.itemDraft}
        placeholder={c.fieldPlaceholder}
        onChange={(itemDraft) => setState((s) => ({ ...s, itemDraft }))}
        onSubmit={addTyped}
        action={
          <HexButton
            tone="primary"
            className="btn--icon"
            aria-label={c.add}
            icon={<Icon name="add" />}
            disabled={!state.itemDraft.trim()}
            onClick={addTyped}
          />
        }
      />
      {n > 0 && (
        <section className="on-list" aria-live="polite">
          <h3 className="on-list-title">{c.onList(n)}</h3>
          <div className="chips">
            {state.items.map((item) => {
              const label = itemLabel(item, lang);
              return (
                <button
                  key={itemKey(item)}
                  type="button"
                  className="hx chip chip--removable"
                  aria-label={c.remove(label)}
                  onClick={() => toggle(item)}
                >
                  <span className="hx-label">{label}</span>
                  <Icon name="close" />
                </button>
              );
            })}
          </div>
        </section>
      )}
    </StepFrame>
  );
}

function AccountStep({ lang, setState, onAdvance, onNotice }: StepBodyProps) {
  const c = COPY[lang].account;
  const notices = COPY[lang].notices;
  const signIn = (method: SignInMethod) => {
    setState((s) => ({ ...s, signIn: method }));
    onAdvance();
  };
  return (
    <StepFrame
      title={c.title}
      lead={c.lead}
      actions={
        <>
          <HexButton block icon={<GoogleMark />} onClick={() => signIn('google')}>
            {c.google}
          </HexButton>
          <HexButton block tone="ink" icon={<AppleMark />} onClick={() => signIn('apple')}>
            {c.apple}
          </HexButton>
          <HexButton block icon={<Icon name="mail" />} onClick={() => signIn('email')}>
            {c.email}
          </HexButton>
          <p className="legal">
            {c.legalBefore}
            <a
              href="#terms"
              className="inline-link"
              onClick={(e) => {
                e.preventDefault();
                onNotice(notices.terms);
              }}
            >
              {c.terms}
            </a>
            {c.legalMiddle}
            <a
              href="#privacy"
              className="inline-link"
              onClick={(e) => {
                e.preventDefault();
                onNotice(notices.privacy);
              }}
            >
              {c.privacy}
            </a>
            {c.legalAfter}
          </p>
        </>
      }
    />
  );
}

function InviteStep({ lang, state, onFinish }: StepBodyProps) {
  const c = COPY[lang].invite;
  const audience = audienceOf(state.who);
  const solo = audience === 'me';
  const n = state.items.length;
  return (
    <StepFrame
      badge="person_add"
      title={c.titles[audience]}
      lead={solo ? c.bodyMe : c.body}
      actions={
        <>
          <HexButton tone="primary" block icon={<Icon name="person_add" />} onClick={() => onFinish('invited')}>
            {solo ? c.inviteSomeone : c.titles[audience]}
          </HexButton>
          <HexButton block onClick={() => onFinish('later')}>
            {solo ? c.goToList : c.later}
          </HexButton>
        </>
      }
    >
      {n > 0 && (
        <p className="waiting">
          <Icon name="check" />
          <span>{c.waiting(n)}</span>
        </p>
      )}
    </StepFrame>
  );
}
