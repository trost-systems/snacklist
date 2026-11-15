// The app's chrome as HTML: list, More, sheets, the feedback form's parts, Peter's desk cards.
// Every builder takes the render context `c` ({ lang, scen, T, att, tog }) and returns a string.
import { icons } from './icons.js';
import { list, scenarios, fields, money } from './model.js';

export const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[ch]);
export const ic = (name, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;
export const L = (c, o) => (typeof o === 'string' ? o : o[c.lang]);

// `data-go` moves the interactive phone to another state; the verify script counts these clicks as taps.
export const go = (state, gesture) => `data-go="${state}"${gesture ? ` data-gesture="${gesture}"` : ''}`;
export const tact = (label, { to, honey, off, wide, icon, testid } = {}) =>
  `<button class="tact ${honey ? 'honey' : ''} ${off ? 'off' : ''} ${wide ? 'wide' : ''}" ${to ? go(to) : ''} ${testid ? `data-testid="${testid}"` : ''}><span>${icon ? ic(icon, 'sm') : ''}${label}</span></button>`;

export const statusBar = () => `<div class="status"><b>9:41</b><span class="grow"></span><span class="sig"></span></div>`;

const tabs = (c, on, to = {}) => `<div class="nav"><div class="pill-wrap"><nav class="pill-nav">
  ${[['list', 'shopping_cart', c.T.list], ['history', 'history', c.T.history], ['more', 'menu', c.T.more]]
    .map(([k, i, t]) => `<button class="${on === k ? 'on' : ''}" ${to[k] ? go(to[k]) : ''} data-tab="${k}">${ic(i, 'sm')}<span>${t}</span></button>`)
    .join('')}</nav></div></div>`;

// The list tab. `o.redact` draws item names as bars (the app knows which widgets are list text);
// `o.hot` marks the oat milk row; `o.press` makes it the long-press target; `o.banner` sits above the list.
export const listScreen = (c, o = {}) => {
  // `o.moved`: oat milk already moved from Pantry to Chilled (FB3, after the user's own fix).
  const groups = o.moved
    ? list.map((g) => ({ ...g, items: g.cat.en === 'Chilled' ? [...g.items, ...list.flatMap((x) => x.items.filter((it) => it.id === 'oat'))] : g.items.filter((it) => it.id !== 'oat') }))
    : list;
  const rows = groups
    .map((g) => `<div class="cat"><span>${L(c, g.cat)}</span><i></i></div>${g.items
      .map((it) => {
        const name = o.redact ? `<span class="redact" style="width:${40 + it.en.length * 6}px"></span>` : `${it.q ? `<span class="qty">${it.q}</span> ` : ''}${esc(L(c, it))}`;
        const hot = it.id === 'oat' && o.hot;
        const attrs = it.id === 'oat' && o.press ? go(o.press, 'long-press') : '';
        return `<div class="item ${hot ? 'hot' : ''}" ${attrs} ${it.id ? `data-item="${it.id}"` : ''}><span class="emoji">${it.e}</span><span class="iname">${name}</span><span class="pchip"><span>+ ${c.T.price}</span></span></div>`;
      })
      .join('')}`)
    .join('');
  return `${statusBar()}
  <div class="hdr"><button class="tact"><span>${c.T.household} ${ic('expand_more', 'sm')}</span></button><span class="grow"></span><button class="tact"><span>${c.T.edit}</span></button></div>
  ${o.banner ?? ''}
  <div class="storebar"><span class="badge-hex"><i>${c.T.noStore}</i></span><span class="rule"></span><b>${c.T.items(9)}</b></div>
  <div class="scroll">${rows}<div class="endpad"></div></div>
  <div class="bottom">${o.snack ?? ''}<div class="total-bar"><span><b>${c.T.total}</b><small>${c.T.totalMeta}</small></span><span class="big-sum">${money(c.lang)}</span></div>
  <div class="addbar"><div class="addfield"><span class="in">${c.T.addHint}</span></div></div>${tabs(c, 'list', o.tabs)}</div>`;
};

// More: today's groups, with the feedback group's rows replaceable (`o.fbRows`) and one row highlighted.
export const moreRow = (c, { icon, label, sub, face, to, hot, trail = 'chevron_right', testid, badge }) =>
  `<button class="mrow ${hot ? 'hot' : ''}" ${to ? go(to) : ''} ${testid ? `data-testid="${testid}"` : ''}><span class="hexface"><span style="--face:${face ?? 'var(--hl-color-surface-sunken)'}">${ic(icon)}</span></span><span class="grow"><span>${label}</span>${sub ? `<small>${sub}</small>` : ''}</span>${badge ? `<span class="badge-n">${badge}</span>` : ''}${ic(trail, 'sm')}</button>`;

export const moreScreen = (c, o = {}) => {
  const honey = 'var(--hl-color-honey-soft)', mint = 'var(--hl-color-mint-soft)', cobalt = 'var(--hl-color-accent-soft)';
  const fbRows = o.fbRows ?? [moreRow(c, { icon: 'feedback_outlined', label: c.T.feedback, to: o.fbTo, hot: o.hot, testid: 'more-feedback' })];
  return `${statusBar()}<div class="scroll">
  <h2 class="more-title">${c.T.moreTitle}</h2>
  ${o.top ?? ''}
  <div class="group-card">${moreRow(c, { icon: 'shopping_cart_outlined', label: c.T.startTrip, sub: c.T.startTripSub, face: honey, trail: 'chevron_right' })}</div>
  <div class="group-card">${moreRow(c, { icon: 'manage_accounts_outlined', label: c.T.account, face: mint })}</div>
  <div class="group-card">${moreRow(c, { icon: 'home_outlined', label: c.T.household, face: honey })}${moreRow(c, { icon: 'person_add_outlined', label: c.T.invite, face: honey })}</div>
  <div class="group-card">${moreRow(c, { icon: 'key_outlined', label: c.T.access, face: cobalt })}</div>
  <div class="group-card">${moreRow(c, { icon: 'settings_outlined', label: c.T.settings, face: mint, to: o.settingsTo })}${moreRow(c, { icon: 'insights_outlined', label: c.T.usage, face: mint })}</div>
  <div class="group-card">${moreRow(c, { icon: 'lightbulb_outline', label: c.T.tips })}${fbRows.join('')}${moreRow(c, { icon: 'star_outline', label: c.T.rate, trail: 'open_in_new' })}${moreRow(c, { icon: 'help_outline', label: c.T.help, trail: 'open_in_new' })}</div>
  <div class="endpad"></div></div>
  <div class="bottom more-bottom">${o.snack ?? ''}${tabs(c, 'more', o.tabs)}</div>`;
};

export const sheet = (c, title, body, { full, closeTo } = {}) =>
  `<div class="scrim"></div><section class="sheet ${full ? 'full' : ''}" role="dialog" aria-label="${esc(title)}"><div class="handle"></div>
  <div class="sheet-top"><h3>${title}</h3><button class="ibtn" aria-label="${c.T.close}" ${closeTo ? go(closeTo) : ''}>${ic('close')}</button></div>
  <div class="sheet-body">${body}</div></section>`;

export const messageField = (c, text = L(c, scenarios[c.scen].message)) =>
  `<div class="field focus"><label>${c.T.message}</label><textarea rows="4" aria-label="${c.T.message}" placeholder="${c.T.messageHint}">${esc(text)}</textarea></div>`;

export const typeChips = (c, on = scenarios[c.scen].category) =>
  `<div class="lab">${c.T.type}</div><div class="chips">${['bug', 'idea', 'other'].map((k) => `<span class="chip ${on === k ? 'on' : ''}"><span>${c.T[k]}</span></span>`).join('')}</div>`;

export const contactBox = (c, on = false, label = c.T.contact) =>
  `<div class="check ${on ? 'on' : ''}"><span class="hexbox"><i>${on ? ic('check', 'xs') : ''}</i></span><span>${label}</span></div>`;

// What goes with the note: one row per field with its real value; `fixed` rows cannot be dropped,
// the others have a switch (`data-tog`). List content rows are tinted so they stand out.
export const attPanel = (c, rows, { title, open = true } = {}) => {
  const body = rows
    .map(({ key, fixed }) => {
      const f = fields[key];
      const on = fixed || c.att[key];
      const v = f.value(c.lang)[c.lang];
      return `<div class="att-row ${on ? '' : 'out'} ${f.list ? 'list' : ''}" data-att="${key}" data-on="${on ? 1 : 0}"><span class="grow"><b>${f.label[c.lang]}</b><small>${esc(v)}</small></span>${fixed ? `<span class="fixed">${c.lang === 'de' ? 'immer' : 'always'}</span>` : `<button class="sw ${on ? 'on' : ''}" role="switch" aria-checked="${on}" aria-label="${f.label[c.lang]}" data-tog="${key}"></button>`}</div>`;
    })
    .join('');
  return `<div class="att" data-testid="attachments"><div class="att-h">${ic('attach_file', 'sm')}<span class="grow">${title ?? (c.lang === 'de' ? 'Wird mitgeschickt' : 'Sent along')}</span>${ic(open ? 'expand_less' : 'expand_more', 'sm')}</div>${open ? body : ''}</div>`;
};

export const snack = (c, text, action) => `<div class="snack" role="status"><span class="grow">${text}</span>${action ?? ''}</div>`;

// A desk card: what Peter (only Peter) reads, and where.
export const desk = (title, body, who) => `<div class="desk"><div class="desk-top"><span class="dots"><i></i><i></i><i></i></span><span class="grow ell">${title}</span></div><div class="desk-body">${who ? `<div class="who">${who}</div>` : ''}${body}</div></div>`;
export const kv = (rows) => `<table>${rows.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}</table>`;

// Step 3: where the note travels. Each hop names its host region and who can read it.
export const route = (c, hops, notes) =>
  `<div class="desk"><div class="desk-top"><span class="grow">${c.lang === 'de' ? 'So reist die Notiz' : 'Where the note goes'}</span></div><div class="desk-body"><ol class="hops">${hops
    .map((h) => `<li><b>${esc(L(c, h.what))}</b><span class="muted"> · ${esc(L(c, h.where))}</span>${h.reader ? `<br><small>${esc(L(c, h.reader))}</small>` : ''}</li>`)
    .join('')}</ol>${notes ? `<p class="muted">${esc(L(c, notes))}</p>` : ''}</div></div>`;
