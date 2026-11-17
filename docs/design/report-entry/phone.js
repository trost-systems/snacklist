import { icons } from './icons.js';
import { copy } from './copy.js';

// Each option is a table row: where More leads (`rows`, top to bottom inside the Tips group) and what the
// hub offers at its top (`hub`). Everything after the entry (form, picker, confirmation) is shared.
export const options = {
  today: {
    rows: [{ key: 'hub', label: 'hub', icon: 'forum_outlined', to: 'hub' }],
    hub: ['write'],
  },
  RC1: {
    rows: [{ key: 'hub', label: 'hubReports', icon: 'forum_outlined', to: 'chooser' }],
    hub: ['write'],
  },
  RC2: {
    rows: [{ key: 'hub', label: 'hub', sub: 'alsoReport', icon: 'forum_outlined', to: 'hub' }],
    hub: ['write', 'report'],
  },
  RC3: {
    rows: [
      { key: 'hub', label: 'hub', icon: 'forum_outlined', to: 'hub' },
      { key: 'report', label: 'report', icon: 'flag_outlined', to: 'form' },
    ],
    hub: ['write', 'report'],
  },
};

const MIN = 20;
const MAX = 5000;
const REF_CHARS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

export const blankForm = () => ({
  kind: null, where: null, whereText: '', reason: '', name: null, email: null,
  contactShown: true, good: false, shot: false, tried: false,
});

export const newRef = () => `R-${Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => REF_CHARS[b % REF_CHARS.length]).join('')}`;

// What the form still lacks, in field order. Name and e-mail are never required (N-228.4).
export function missing(f) {
  const out = [];
  if (!f.kind) out.push('kind');
  if (!f.where || (f.where.kind === 'else' && f.whereText.trim().length === 0)) out.push('where');
  const n = f.reason.trim().length;
  if (n < MIN || f.reason.length > MAX) out.push('reason');
  if (!f.good) out.push('good');
  return out;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const ic = (name, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;

export class Phone {
  constructor(el, { option, lang, fb4 = true, state = {} }) {
    this.el = el;
    this.option = option;
    this.lang = lang;
    this.fb4 = fb4;
    this.s = { screen: 'more', sheet: null, stack: [], form: blankForm(), ref: null, copied: false, pick: '', scrollTo: null, press: null, ...state };
    el.addEventListener('click', (e) => this.onClick(e));
    el.addEventListener('input', (e) => this.onInput(e));
    this.render();
  }

  get t() { return copy[this.lang]; }
  get o() { return options[this.option]; }

  // Without FB4 there is no hub: More's feedback row opens the feedback sheet, as on main today.
  get rows() {
    if (this.fb4) return this.o.rows;
    return this.o.rows.map((r) => (r.key !== 'hub' ? r : { ...r, label: r.label === 'hub' ? 'feedbackRow' : r.label, icon: 'feedback_outlined', to: r.to === 'hub' ? 'compose' : r.to }));
  }

  go(screen) { this.s.stack.push(this.s.screen); this.s.screen = screen; this.s.sheet = null; this.s.scrollTop = 0; }
  back() { this.s.screen = this.s.stack.pop() ?? 'more'; this.s.sheet = null; }

  onClick(e) {
    const a = e.target.closest('[data-act]');
    if (!a || !this.el.contains(a)) return;
    e.preventDefault();
    const [act, arg, arg2] = a.dataset.act.split(':');
    const s = this.s;
    const f = s.form;
    s.press = null;
    switch (act) {
      case 'row': {
        const to = this.rows.find((r) => r.key === arg).to;
        if (to === 'chooser' || to === 'compose') s.sheet = to; else { if (to === 'form') s.form = blankForm(); this.go(to); }
        break;
      }
      case 'choose':
        if (arg === 'report') { s.form = blankForm(); this.go('form'); } else if (this.fb4) this.go('hub'); else s.sheet = 'compose';
        break;
      case 'write': s.sheet = 'compose'; break;
      case 'report': s.form = blankForm(); this.go('form'); break;
      case 'back': this.back(); break;
      case 'sheet-close': s.sheet = null; break;
      case 'tab': s.screen = 'more'; s.stack = []; s.sheet = null; break;
      case 'kind':
        // Only child abuse material may hide name and e-mail (N-228.4).
        f.kind = arg;
        f.contactShown = arg !== 'csam';
        break;
      case 'csam-add': f.contactShown = true; break;
      case 'where-open': s.sheet = 'where'; s.pick = ''; break;
      case 'pick': {
        const t = this.t;
        const label = arg === 'household' ? t.household : arg === 'list' ? t.lists[+arg2] : t.items[+arg2][1];
        f.where = { kind: arg, label };
        s.sheet = null;
        break;
      }
      case 'pick-else': f.where = { kind: 'else' }; s.sheet = null; s.focus = 'whereText'; break;
      case 'good': f.good = !f.good; break;
      case 'shot': f.shot = !f.shot; break;
      case 'send': {
        f.tried = true;
        const miss = missing(f);
        if (miss.length === 0) { s.ref = newRef(); s.copied = false; this.go('done'); }
        else s.scrollToField = miss[0];
        break;
      }
      case 'copy': s.copied = true; navigator.clipboard?.writeText(s.ref).catch(() => {}); break;
      case 'done':
        // Back to where the report was started from: the hub, the More list.
        while (s.stack.length && ['form', 'done'].includes(s.stack.at(-1))) s.stack.pop();
        this.back();
        break;
      default: return;
    }
    this.render();
  }

  onInput(e) {
    const k = e.target.dataset.in;
    if (!k) return;
    if (k === 'pick') this.s.pick = e.target.value; else this.s.form[k] = e.target.value;
    this.render();
  }

  render() {
    const body = this.el.querySelector('.body');
    const keep = body && this.el.dataset.screen === this.s.screen ? body.scrollTop : this.s.scrollTop ?? 0;
    const sheetBody = this.el.querySelector('.sheet .sbody');
    const keepSheet = sheetBody ? sheetBody.scrollTop : 0;
    const focus = document.activeElement && this.el.contains(document.activeElement) ? document.activeElement.dataset.in : null;
    const caret = focus ? document.activeElement.selectionStart : null;
    this.el.dataset.screen = this.s.screen;
    this.el.dataset.sheet = this.s.sheet ?? '';
    this.el.innerHTML = `<div class="status"><span>9:41</span><span class="grow"></span><span class="sig"></span></div>${this.screen()}${this.sheet()}<div class="homeind"><i></i></div>`;
    const nb = this.el.querySelector('.body');
    nb.scrollTop = keep;
    const sb = this.el.querySelector('.sheet .sbody');
    if (sb) sb.scrollTop = keepSheet;
    const want = this.s.focus ?? focus;
    this.s.focus = null;
    if (want) {
      const inp = this.el.querySelector(`[data-in="${want}"]`);
      if (inp) { inp.focus({ preventScroll: true }); if (caret != null && want === focus) inp.setSelectionRange(caret, caret); }
    }
    if (this.s.scrollTo) {
      const g = this.el.querySelector(`[data-group="${this.s.scrollTo}"]`);
      if (g) nb.scrollTop = g.offsetTop - (nb.clientHeight - g.offsetHeight) / 2;
      this.s.scrollTo = null;
    }
    if (this.s.scrollToField) {
      const g = this.el.querySelector(`[data-field="${this.s.scrollToField}"]`);
      if (g) nb.scrollTop = g.offsetTop - 12;
      this.s.scrollToField = null;
    }
    if (this.s.scrollBottom) { nb.scrollTop = nb.scrollHeight; this.s.scrollBottom = false; }
  }

  appbar(title, lead = 'back') {
    const btn = lead === 'close'
      ? `<button class="iconbtn" data-act="back" aria-label="${esc(this.t.back)}">${ic('close')}</button>`
      : lead === 'back' ? `<button class="iconbtn" data-act="back" aria-label="${esc(this.t.back)}">${ic('arrow_back')}</button>` : '';
    return `<header class="appbar ${lead === 'none' ? 'top' : ''}">${btn}<h1>${esc(title)}</h1></header>`;
  }

  tabs() {
    const t = this.t;
    const tab = (icon, label, on) => `<button class="tab ${on ? 'on' : ''}" ${on ? 'data-act="tab"' : ''} aria-label="${esc(label)}"><span class="tabicon">${ic(icon)}</span><span>${esc(label)}</span></button>`;
    return `<nav class="tabs">${tab('checklist', t.list, false)}${tab('history', t.history, false)}${tab('more_horiz', t.more, true)}</nav>`;
  }

  screen() {
    switch (this.s.screen) {
      case 'hub': return this.hub();
      case 'form': return this.form();
      case 'done': return this.done();
      default: return this.more();
    }
  }

  row({ key, label, sub, icon, to, tint = 'plain', trail = 'chevron_right' }) {
    const t = this.t;
    const act = to ? `data-act="row:${key}"` : '';
    const pressed = this.s.press === key ? ' pressed' : '';
    return `<button class="mrow${pressed}" ${act} data-row="${key}"><span class="hexface ${tint}">${ic(icon, 'sm')}</span><span class="grow"><span class="mlabel">${esc(t[label] ?? label)}</span>${sub ? `<span class="msub">${esc(t[sub])}</span>` : ''}</span>${trail ? ic(trail, 'sm trail') : ''}</button>`;
  }

  group(rows, name = '') {
    return `<div class="group" ${name ? `data-group="${name}"` : ''}>${rows.join('')}</div>`;
  }

  more() {
    const r = (key, icon, tint, trail) => this.row({ key, label: key, icon, tint, trail });
    const fb = this.rows.map((x) => this.row(x));
    return `${this.appbar(this.t.more, 'none')}<main class="body more">
      ${this.group([r('account', 'manage_accounts_outlined', 'mint')])}
      ${this.group([r('access', 'key_outlined', 'cobalt')])}
      ${this.group([r('settings', 'settings_outlined', 'mint'), r('usage', 'insights_outlined', 'mint')])}
      ${this.group([r('tips', 'lightbulb_outline'), ...fb, r('rate', 'star_outline', 'plain', 'open_in_new'), r('help', 'help_outline', 'plain', 'open_in_new')], 'feedback')}
      ${this.group([r('imprint', 'info_outline', 'plain', 'open_in_new'), r('privacy', 'privacy_tip_outlined', 'plain', 'open_in_new'), r('terms', 'article_outlined', 'plain', 'open_in_new'), r('licenses', 'description_outlined')])}
      ${this.group([this.row({ key: 'signOut', label: 'signOut', icon: 'logout', trail: null })])}
      <p class="version">${esc(this.t.version)}</p>
    </main>${this.tabs()}`;
  }

  hub() {
    const t = this.t;
    const o = this.o;
    const label = o.rows[0].label === 'hubReports' ? t.hubReports : t.hub;
    const glyph = { fixed: 'check_circle_outline', read: 'visibility_outlined', planned: 'event_note_outlined' };
    const notes = t.notes.map(([k, st, text]) => `<div class="card"><span class="status-chip ${k}">${ic(glyph[k], 'xs')}${esc(st)}</span><p>${esc(text)}</p></div>`).join('');
    const report = o.hub.includes('report')
      ? `<div class="hubreport" data-entry="report"><span class="tact wide"><span data-act="report" role="button" tabindex="0">${ic('flag_outlined', 'sm')}${esc(t.report)}</span></span><p class="hint">${esc(t.reportHint)}</p></div>`
      : '';
    return `${this.appbar(label)}<main class="body hub">
      <div class="hubtop" data-entry="feedback"><span class="tact honey wide"><span data-act="write" role="button" tabindex="0">${ic('edit_outlined', 'sm')}${esc(t.write)}</span></span></div>
      ${report}
      <h2 class="section">${esc(t.yourNotes)}</h2>
      ${notes}
      <h2 class="section">${esc(t.ideas)}</h2>
      <div class="card idea"><span class="grow"><b>${esc(t.idea)}</b><span class="muted">${esc(t.ideaStatus)}</span></span><span class="tact"><span>${ic('thumb_up_outlined', 'sm')}14</span></span></div>
    </main>${this.tabs()}`;
  }

  label(text, need, field) {
    const tag = need === 'req' ? `<span class="req">${esc(this.t.required)}</span>` : need === 'rec' ? `<span class="recd">${esc(this.t.recommended)}</span>` : '';
    return `<p class="flabel" id="lbl-${field}">${esc(text)} ${tag}</p>`;
  }

  err(field) {
    const f = this.s.form;
    if (!f.tried || !missing(f).includes(field)) return '';
    const t = this.t;
    const n = f.reason.trim().length;
    const msg = { kind: t.errAbout, where: t.errWhere, reason: f.reason.length > MAX ? t.errLong : t.errShort(MIN - n), good: t.errGood }[field];
    return `<p class="ferr" role="alert">${ic('error_outline', 'xs')}${esc(msg)}</p>`;
  }

  whereSummary() {
    const t = this.t;
    const w = this.s.form.where;
    const q = (x) => (this.lang === 'de' ? `„${x}“` : `“${x}”`);
    const kind = { household: t.kindHousehold, list: t.kindList, item: t.kindItem }[w.kind];
    const ctx = w.kind === 'item' ? `${t.kindList} ${q(t.lists[0])} · ${t.household}` : w.kind === 'list' ? t.household : '';
    return `<div class="picked"><span class="pk">${esc(kind)}</span><b>${esc(q(w.label))}</b>${ctx ? `<span class="muted">${esc(ctx)}</span>` : ''}</div>`;
  }

  form() {
    const t = this.t;
    const f = this.s.form;
    const name = f.name ?? t.meName;
    const email = f.email ?? t.meEmail;
    const kinds = t.kinds.map(([k, label]) => `<button class="radio ${f.kind === k ? 'on' : ''}" data-act="kind:${k}" role="radio" aria-checked="${f.kind === k}"><span class="hexdot"></span><span class="grow">${esc(label)}</span></button>`).join('');
    const n = f.reason.length;
    const contact = f.contactShown
      ? `<div class="field" data-field="contact">${this.label(t.name, 'rec', 'name')}<input class="input" data-in="name" value="${esc(name)}" aria-labelledby="lbl-name" autocomplete="name">
         ${this.label(t.email, 'rec', 'email')}<input class="input" data-in="email" type="email" value="${esc(email)}" aria-labelledby="lbl-email" autocomplete="email">
         <p class="help">${esc(f.kind === 'csam' ? t.csamNote : t.contactHelp)}</p></div>`
      : `<div class="field" data-field="contact"><p class="help strong">${esc(t.csamNote)}</p><span class="tact"><span data-act="csam-add" role="button" tabindex="0">${ic('person_outline', 'sm')}${esc(t.csamAdd)}</span></span></div>`;
    const where = f.where?.kind === 'else'
      ? `<textarea class="input short" data-in="whereText" aria-labelledby="lbl-where">${esc(f.whereText)}</textarea><span class="tact"><span data-act="where-open" role="button" tabindex="0">${esc(t.whereChange)}</span></span>`
      : f.where ? `${this.whereSummary()}<span class="tact"><span data-act="where-open" role="button" tabindex="0">${esc(t.whereChange)}</span></span>`
        : `<span class="tact"><span data-act="where-open" role="button" tabindex="0">${ic('search', 'sm')}${esc(t.whereChoose)}</span></span>`;
    return `${this.appbar(t.report, 'close')}<main class="body form">
      <p class="intro">${esc(t.intro)}</p>
      <div class="field" data-field="kind" role="radiogroup" aria-labelledby="lbl-kind">${this.label(t.about, 'req', 'kind')}${kinds}${this.err('kind')}</div>
      <div class="field" data-field="where">${this.label(t.where, 'req', 'where')}<p class="help">${esc(!f.where ? t.whereChooseHelp : f.where.kind === 'else' ? t.pickElseHint : t.whereHelp)}</p>${where}${this.err('where')}</div>
      <div class="field" data-field="reason">${this.label(t.why, 'req', 'reason')}<p class="help">${esc(t.whyHelp)}</p>
        <textarea class="input long ${n > MAX ? 'over' : ''}" data-in="reason" aria-labelledby="lbl-reason">${esc(f.reason)}</textarea>
        <p class="counter ${n > MAX ? 'over' : ''}">${esc(t.counter(n))}</p>${this.err('reason')}</div>
      ${contact}
      <div class="field" data-field="shot">${f.shot
        ? `<div class="shot"><span class="thumb">${ic('image_outlined')}</span><span class="grow">${esc(t.shotAttached)}</span><span class="tact"><span data-act="shot" role="button" tabindex="0">${esc(t.shotRemove)}</span></span></div>`
        : `<span class="tact"><span data-act="shot" role="button" tabindex="0">${ic('photo_camera_outlined', 'sm')}${esc(t.shot)}</span></span>`}<p class="help">${esc(t.shotHelp)}</p></div>
      <div class="field" data-field="good"><button class="check ${f.good ? 'on' : ''}" data-act="good" role="checkbox" aria-checked="${f.good}"><span class="hexbox">${f.good ? ic('check', 'xs') : ''}</span><span class="grow">${esc(t.goodFaith)} <span class="req">${esc(t.required)}</span></span></button>${this.err('good')}</div>
      <p class="help">${esc(t.footer)}<a href="#" onclick="return false">${esc(t.footerLink)}</a></p>
      <div class="sendrow"><span class="tact honey"><span data-act="send" role="button" tabindex="0">${esc(t.sendReport)}</span></span></div>
    </main>`;
  }

  done() {
    const t = this.t;
    const f = this.s.form;
    const mail = f.contactShown ? (f.email ?? t.meEmail).trim() : '';
    return `${this.appbar(t.report, 'none')}<main class="body done">
      <div class="donehead"><span class="bigcheck">${ic('check_circle_outline')}</span><h2>${esc(t.thanksTitle)}</h2></div>
      <div class="refbox" data-ref="${esc(this.s.ref)}"><span class="pk">${esc(t.number)}</span><b class="ref">${esc(this.s.ref)}</b>
        <span class="tact"><span data-act="copy" role="button" tabindex="0">${ic(this.s.copied ? 'check' : 'content_copy', 'sm')}${esc(this.s.copied ? t.copied : t.copyNumber)}</span></span></div>
      <p class="thanks">${esc(t.thanks('\u0000')).replace('\u0000', `<span class="nw">${esc(this.s.ref)}</span>`)}</p>
      <p class="help">${esc(mail ? t.mailed(mail) : t.notMailed)}</p>
      <p class="help">${esc(t.notInNotes)}</p>
      <div class="sendrow"><span class="tact honey"><span data-act="done" role="button" tabindex="0">${esc(t.done)}</span></span></div>
    </main>`;
  }

  sheet() {
    const t = this.t;
    const head = (title) => `<div class="handle"></div><div class="shead"><h2>${esc(title)}</h2><button class="iconbtn" data-act="sheet-close" aria-label="${esc(t.back)}">${ic('close')}</button></div>`;
    switch (this.s.sheet) {
      case 'chooser':
        return `<div class="scrim" data-act="sheet-close"></div><section class="sheet" role="dialog" aria-label="${esc(t.hubReports)}">${head(t.hubReports)}<div class="sbody">
          <button class="choice" data-act="choose:hub" data-entry="feedback"><span class="hexface">${ic(this.fb4 ? 'forum_outlined' : 'feedback_outlined', 'sm')}</span><span class="grow"><b>${esc(this.fb4 ? t.hub : t.feedbackRow)}</b><span class="msub">${esc(this.fb4 ? t.chooseFeedback : t.chooseFeedbackSheet)}</span></span>${ic('chevron_right', 'sm')}</button>
          <button class="choice" data-act="choose:report" data-entry="report"><span class="hexface">${ic('flag_outlined', 'sm')}</span><span class="grow"><b>${esc(t.report)}</b><span class="msub">${esc(t.chooseReport)}</span></span>${ic('chevron_right', 'sm')}</button>
        </div></section>`;
      case 'compose':
        return `<div class="scrim" data-act="sheet-close"></div><section class="sheet" role="dialog" aria-label="${esc(t.feedbackRow)}">${head(t.feedbackRow)}<div class="sbody">
          ${!this.fb4 && this.o.hub.includes('report') ? `<div class="hubreport" data-entry="report"><span class="tact wide"><span data-act="report" role="button" tabindex="0">${ic('flag_outlined', 'sm')}${esc(t.report)}</span></span><p class="hint">${esc(t.reportHint)}</p></div>` : ''}
          <div class="input long compose"><span class="pk">${esc(t.message)}</span><span class="muted">${esc(t.messageHint)}</span></div>
          <p class="help">${esc(t.categories)}</p>
          <div class="chips">${[t.catBug, t.catIdea, t.catOther].map((c) => `<span class="tact"><span>${esc(c)}</span></span>`).join('')}</div>
          <div class="check"><span class="hexbox"></span><span class="grow">${esc(t.contact)}</span></div>
          <p class="help">${esc(t.attached)}</p>
          <div class="sendrow"><span class="tact honey"><span>${esc(t.send)}</span></span></div>
        </div></section>`;
      case 'where': {
        const q = this.s.pick.trim().toLowerCase();
        const hit = (s) => !q || s.toLowerCase().includes(q);
        const opt = (act, emoji, label, icon) => `<button class="pickrow" data-act="${act}">${emoji ? `<span class="emoji">${emoji}</span>` : `<span class="emoji">${ic(icon, 'sm')}</span>`}<span class="grow">${esc(label)}</span></button>`;
        const sec = (title, rows) => (rows.length ? `<h3 class="section">${esc(title)}</h3>${rows.join('')}` : '');
        return `<div class="scrim" data-act="sheet-close"></div><section class="sheet tall" role="dialog" aria-label="${esc(t.pickTitle)}">${head(t.pickTitle)}
          <div class="searchwrap"><span class="search">${ic('search', 'sm')}<input data-in="pick" value="${esc(this.s.pick)}" placeholder="${esc(t.pickSearch)}" aria-label="${esc(t.pickSearch)}"></span></div><div class="sbody">
          ${sec(t.pickItems, t.items.map(([e, n], i) => (hit(n) ? opt(`pick:item:${i}`, e, n) : '')).filter(Boolean))}
          ${sec(t.pickLists, t.lists.map((n, i) => (hit(n) ? opt(`pick:list:${i}`, null, n, 'list_alt') : '')).filter(Boolean))}
          ${sec(t.pickHousehold, hit(t.household) ? [opt('pick:household:0', null, t.household, 'home_outlined')] : [])}
          <h3 class="section">${esc(t.pickPhotos)}</h3><p class="help pad">${esc(t.pickNoPhotos)}</p>
          ${opt('pick-else', null, t.pickElse, 'edit_outlined')}
        </div></section>`;
      }
      default: return '';
    }
  }
}
