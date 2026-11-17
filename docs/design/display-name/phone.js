import { icons } from './icons.js';
import { copy, personas, derivedName, firstName } from './copy.js';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const ic = (n, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[n]}"/></svg>`;
const HOUSEHOLD = 'Familie Brandt';
const PETER = 'Peter';
const MAX = 80;
const valid = (v) => { const n = [...v.trim()].length; return n >= 1 && n <= MAX; };

// The screens each option's flow passes, in order. `counted` are the steps behind „Step N of M“ (usage, the first, is
// the same for every option and left out of the walk).
export function flow(round, option, role) {
  if (role === 'join') {
    const ask = { DN1: ['you'], DN3: ['confirm'], DN5: ['hello'] }[option] ?? [];
    return ['joinpage', 'account', 'emailSignup', ...ask, 'joinconfirm', 'list'];
  }
  const s = ['who', 'hhname', 'stores', 'need', 'account', 'emailSignup', 'invite', 'list'];
  if (option === 'DN1') s.splice(1, 0, 'you');
  if (option === 'DN5') s.unshift('hello');
  if (option === 'DN3') s.splice(s.indexOf('invite'), 0, 'confirm');
  return s;
}
const counted = (option) => ['usage', ...(option === 'DN5' ? ['hello'] : []), 'who', ...(option === 'DN1' ? ['you'] : []), 'hhname', 'stores', 'need', 'account', ...(option === 'DN3' ? ['confirm'] : []), 'invite'];
const countedAs = { emailSignup: 'account' };

export class Phone {
  // opts: { round: 'DN'|'DE'|'peer', option, lang, persona, role: 'create'|'join', state, bus, peer }
  constructor(el, opts) {
    this.el = el;
    this.o = opts;
    this.t = copy[opts.lang];
    this.p = personas[opts.persona] ?? personas.email;
    this.bus = opts.bus;
    this.taps = 0;
    this.typed = false;
    const st = opts.state ?? {};
    this.s = {
      screen: st.screen ?? (opts.round === 'DE' ? 'list' : opts.role === 'join' ? 'joinpage' : (opts.option === 'DN5' ? 'hello' : 'who')),
      sheet: st.sheet ?? null, kind: st.kind ?? null, needs: st.needs ?? [], stores: [], invited: !!st.invited, draftName: st.draftName ?? '', hhName: '',
      profile: { name: '', source: 'none' }, inline: !!st.inline, confirmEdit: false, joined: false, snack: null, flash: null, field: {},
      skippedName: !!st.skippedName,
    };
    if (st.signedIn || opts.round === 'DE') this.signIn(this.p.via, true);
    if (opts.round === 'DE' && st.profile) this.s.profile = { ...st.profile };
    if (opts.round === 'DE' && this.bus) this.bus.set(this.s.profile);
    this.trail = [this.s.screen];
    el.addEventListener('click', (e) => this.onClick(e));
    el.addEventListener('pointerdown', (e) => {
      const f = e.target.closest('input[data-field]');
      if (f && !f.hasAttribute('data-autofocus') && document.activeElement !== f) this.count(`focus:${f.dataset.field}`);
    });
    el.addEventListener('input', (e) => this.onInput(e));
    this.render();
  }

  get flow() { return flow(this.o.round, this.o.option, this.o.role); }
  get finished() { return this.s.screen === 'list' && this.o.round === 'DN'; }
  count(what) { this.taps += 1; this.lastTap = what; }

  signIn(provider, silent = false) {
    const p = this.p;
    const social = provider === 'email' ? '' : provider === p.via ? p.social : 'Lea Brandt';
    const email = provider === p.via ? p.email : 'lea.brandt87@gmail.com';
    this.s.provider = provider;
    this.s.email = email;
    // The options' target (DN-Q4): a name typed before the account goes into the user's metadata as display_name
    // (signUp's data, or updateUser right after an OAuth sign-in), which default_display_name reads first.
    if (valid(this.s.draftName)) this.s.profile = { name: this.s.draftName.trim(), source: 'chosen' };
    else if (social) this.s.profile = { name: social, source: 'social' };
    else this.s.profile = { name: derivedName(email), source: 'derived' };
    if (!silent) this.changed();
  }

  setName(v) {
    this.s.profile = { name: v.trim(), source: 'chosen' };
    if (this.bus) this.bus.set(this.s.profile);
  }

  go(screen) {
    this.s.screen = screen;
    this.s.sheet = null;
    this.s.snack = null;
    this.trail.push(screen);
    this.focusNext = true;
    this.render();
    this.changed();
  }

  next() {
    const f = this.flow;
    let i = f.indexOf(this.s.screen) + 1;
    // The e-mail form only follows „Continue with email“.
    while (f[i] === 'emailSignup') i++;
    this.go(f[i]);
  }

  prev() {
    const f = this.flow;
    let i = f.indexOf(this.s.screen) - 1;
    while (f[i] === 'emailSignup') i--;
    if (i >= 0) this.go(f[i]);
  }

  sheet(name) {
    this.s.sheet = name;
    if (name) this.trail.push(`sheet:${name}`);
    this.focusNext = true;
    this.render();
    this.changed();
  }

  changed() { this.o.onChange?.(this); }

  field(name) { return this.s.field[name] ?? ''; }

  onInput(e) {
    const f = e.target.closest('input[data-field]');
    if (!f) return;
    this.typed = true;
    this.s.field[f.dataset.field] = f.value;
    this.el.querySelectorAll(`[data-count="${f.dataset.field}"]`).forEach((c) => { c.textContent = `${[...f.value].length}/${MAX}`; });
    this.el.querySelectorAll('[data-needs]').forEach((b) => {
      const v = this.field(b.dataset.needs);
      b.disabled = !valid(v) || (b.dataset.unchanged !== undefined && v.trim() === b.dataset.unchanged);
    });
    this.changed();
  }

  onClick(e) {
    const b = e.target.closest('[data-act]');
    if (!b || b.disabled || !this.el.contains(b)) return;
    const act = b.dataset.act;
    this.count(act);
    this.act(act);
    this.changed();
  }

  act(a) {
    const s = this.s;
    const [verb, arg] = a.split(':');
    switch (verb) {
      case 'chip': {
        if (s.screen === 'who') s.kind = s.kind === arg ? null : arg;
        else if (s.screen === 'stores') s.stores = s.stores.includes(arg) ? s.stores.filter((x) => x !== arg) : [...s.stores, arg];
        else s.needs = s.needs.includes(+arg) ? s.needs.filter((x) => x !== +arg) : [...s.needs, +arg];
        return this.render();
      }
      case 'back': return this.prev();
      case 'exit': return undefined;
      case 'next': return this.onNext();
      case 'skip': {
        if (s.screen === 'hello') { s.draftName = ''; s.skippedName = true; }
        return this.next();
      }
      case 'google': return this.sheet('google');
      case 'apple': return this.sheet('apple');
      case 'email': return this.go('emailSignup');
      case 'sys': { this.signIn(s.sheet); return this.next(); }
      case 'register': { this.signIn('email'); return this.next(); }
      case 'yes': return this.next();
      case 'confirmChange': { s.confirmEdit = true; s.field.you = s.profile.name; this.focusNext = true; return this.render(); }
      case 'invite': {
        if (this.o.option === 'DN4' && s.profile.source === 'derived') { s.field.ask = ''; return this.sheet('ask'); }
        s.invited = true; return this.render();
      }
      case 'another': return this.render();
      case 'later': case 'toList': return this.go('list');
      case 'join': return this.go(this.flow[this.flow.indexOf('joinpage') + 1]);
      case 'joinHousehold': {
        if (this.o.option === 'DN2' && valid(this.field('you'))) this.setName(this.field('you'));
        if (this.o.option === 'DN4' && s.profile.source === 'derived') { s.field.ask = ''; return this.sheet('ask'); }
        s.joined = true; return this.go('list');
      }
      case 'cancelJoin': return undefined;
      case 'askChange': { s.field.ask = s.profile.name; return this.sheet('ask'); }
      case 'askSave': {
        this.setName(this.field('ask'));
        return this.afterAsk();
      }
      case 'askLater': return this.afterAsk(true);
      case 'nudge': { s.field.edit = ''; return this.sheet('edit'); }
      // Signed in (round DE).
      case 'tab': return this.go(arg);
      case 'row': return this.go(arg);
      case 'edit': { s.field.edit = s.profile.source === 'derived' ? '' : s.profile.name; return this.sheet('edit'); }
      case 'editInline': { s.inline = true; s.field.edit = s.profile.source === 'derived' ? '' : s.profile.name; this.focusNext = true; return this.render(); }
      case 'editAll': { s.all = !s.all; return this.render(); }
      case 'save': case 'inlineDone': {
        this.setName(this.field('edit'));
        s.inline = false; s.sheet = null; s.snack = this.t.saved; s.flash = 'name'; this.saved = true;
        this.render();
        return undefined;
      }
      case 'cancel': { s.inline = false; return this.sheet(null); }
      case 'close': return this.sheet(null);
      default: return undefined;
    }
  }

  afterAsk(later = false) {
    const s = this.s;
    s.sheet = null;
    if (s.screen === 'invite') { s.invited = !!(later || valid(this.field('ask'))); return this.render(); }
    if (s.screen === 'joinconfirm') { s.joined = true; return this.go('list'); }
    return this.render();
  }

  onNext() {
    const s = this.s;
    if (['you', 'hello', 'confirm'].includes(s.screen)) {
      const v = this.field('you');
      if (!s.provider) s.draftName = v;
      else this.setName(v);
    }
    if (s.screen === 'hhname') {
      s.hhName = this.field('hh') || this.t.hhDefault[s.kind ?? 'partner'];
      if (this.o.option === 'DN2') s.draftName = this.field('you');
    }
    this.next();
  }

  // What others see of this user: the member list and the join page (preview_invite_public's first word).
  seen() {
    const p = this.s.profile;
    return { member: p.name || this.t.unnamed, join: firstName(p), source: p.source };
  }

  // ---- rendering ----
  render() {
    const s = this.s;
    const scr = this[`scr_${s.screen}`]?.() ?? { body: `<p>${s.screen}</p>` };
    const prevBody = this.el.querySelector('.body, .web');
    const keep = prevBody && this.lastScreen === s.screen ? prevBody.scrollTop : 0;
    this.lastScreen = s.screen;
    const tabs = scr.tabs ? `<nav class="tabs"><button class="tab ${scr.tabs === 'list' ? 'on' : ''}" data-act="tab:list">${ic('shopping_cart_outlined', 'sm')}${this.t.tabList}</button><button class="tab ${scr.tabs === 'more' ? 'on' : ''}" data-act="tab:more">${ic('menu', 'sm')}${this.t.tabMore}</button></nav>` : '';
    const bar = scr.bar === false ? '' : `<header class="appbar ${scr.back ? '' : 'top'} ${scr.plain ? 'plain' : ''}">${scr.back ? `<button class="iconbtn" data-act="${scr.back}" aria-label="${this.t.back}">${ic('arrow_back')}</button>` : ''}<h1>${esc(scr.title ?? '')}</h1>${scr.exit ? `<button class="iconbtn" data-act="exit" aria-label="${this.t.exit}">${ic('close')}</button>` : ''}</header>`;
    this.el.innerHTML = `<div class="status"><span>9:41</span><span class="grow"></span><span class="sig"></span></div>${scr.web ? scr.web : `${bar}<div class="body ${scr.center ? 'center' : ''} ${scr.list ? 'list' : ''}"><div class="col">${scr.body}</div></div>${scr.foot ?? ''}`}${tabs}${this.renderSheet()}${s.snack ? `<div class="snack" role="status">${esc(s.snack)}</div>` : ''}<div class="homeind"><i></i></div>`;
    const body = this.el.querySelector('.body, .web');
    if (body) body.scrollTop = keep;
    if (this.focusNext) {
      this.focusNext = false;
      const f = this.el.querySelector('[data-autofocus]');
      if (f && this.o.interactive !== false) { f.focus({ preventScroll: true }); f.setSelectionRange?.(f.value.length, f.value.length); }
    }
    this.saved = false;
    this.el.dataset.screen = s.screen;
    this.el.dataset.sheet = s.sheet ?? '';
  }

  progress(step) {
    const c = counted(this.o.option);
    const i = c.indexOf(countedAs[step] ?? step) + 1;
    return { title: this.t.stepOf(i, c.length), bar: `<div class="progress" aria-hidden="true"><i style="width:${(i / c.length) * 100}%"></i></div>` };
  }

  fieldHtml(name, label, { value = '', hint = '', autofocus = false, counter = true, err = false } = {}) {
    if (this.s.field[name] === undefined) this.s.field[name] = value;
    const v = this.s.field[name];
    return `<div class="field"><label class="flabel" for="f-${name}">${esc(label)}</label><div class="hexfield ${err ? 'err' : ''}"><span><input id="f-${name}" data-field="${name}" value="${esc(v)}" placeholder="${esc(hint)}" maxlength="${MAX}" autocomplete="off" ${autofocus ? 'data-autofocus' : ''}></span></div>${counter ? `<div class="fmeta"><span class="count" data-count="${name}">${[...v].length}/${MAX}</span></div>` : ''}</div>`;
  }

  btn(act, label, { honey = false, needs = '', unchanged, icon = '' } = {}) {
    const dis = needs && (!valid(this.field(needs)) || (unchanged !== undefined && this.field(needs).trim() === unchanged));
    return `<button class="tact ${honey ? 'honey' : ''}" data-act="${act}" ${needs ? `data-needs="${needs}"` : ''} ${unchanged !== undefined ? `data-unchanged="${esc(unchanged)}"` : ''} ${dis ? 'disabled' : ''}><span>${icon ? ic(icon, 'sm') : ''}${esc(label)}</span></button>`;
  }

  onb(step, { heading, body = '', parts = '', back = true, exit = true }) {
    const pr = this.progress(step);
    return { title: pr.title, back: back ? 'back' : null, exit, center: true, body: `${pr.bar}<h2 class="heading">${esc(heading)}</h2>${body ? `<p class="lead">${esc(body)}</p>` : ''}${parts}` };
  }

  named() { return this.o.option === 'DN5' && valid(this.s.draftName) ? this.s.draftName.trim().split(/\s+/)[0] : null; }

  // Onboarding screens.
  scr_hello() {
    const t = this.t;
    const join = this.o.role === 'join';
    const value = join && this.s.profile.source === 'social' ? this.s.profile.name : '';
    const parts = `${this.fieldHtml('you', t.youLabel, { value, hint: t.youHint, autofocus: true })}${this.btn('next', t.next, { honey: true, needs: 'you' })}${this.btn('skip', t.skip)}`;
    if (join) return { title: t.joinTitle, center: true, body: `<h2 class="heading">${esc(t.helloTitle)}</h2><p class="lead">${esc(t.helloBody)}</p>${parts}` };
    return this.onb('hello', { heading: t.helloTitle, body: t.helloBody, parts, back: false });
  }

  scr_who() {
    const t = this.t;
    const n = this.named();
    const chips = Object.entries(t.kinds).map(([k, v]) => `<button class="chip ${this.s.kind === k ? 'on' : ''}" data-act="chip:${k}">${this.s.kind === k ? ic('check', 'sm') : ''}${esc(v)}</button>`).join('');
    return this.onb('who', { heading: n ? t.whoTitleNamed(n) : t.whoTitle, body: t.whoBody, back: this.o.option === 'DN5', parts: `<div class="chips">${chips}</div>${this.s.kind ? this.btn('next', t.next, { honey: true }) : `<button class="tact honey" disabled><span>${t.next}</span></button>`}${this.btn('skip', t.skip)}` });
  }

  scr_you() {
    const t = this.t;
    const join = this.o.role === 'join';
    const value = join && this.s.profile.source === 'social' ? this.s.profile.name : this.s.draftName;
    const parts = `${this.fieldHtml('you', t.youLabel, { value, hint: t.youHint, autofocus: true })}${this.btn('next', t.next, { honey: true, needs: 'you' })}`;
    if (join) return { title: t.joinTitle, center: true, body: `<h2 class="heading">${esc(t.youTitle)}</h2><p class="lead">${esc(t.youBody)}</p>${parts}` };
    return this.onb('you', { heading: t.youTitle, body: t.youBody, parts });
  }

  scr_hhname() {
    const t = this.t;
    const you = this.o.option === 'DN2' ? `${this.fieldHtml('you', t.youLabel, { value: this.s.draftName, hint: t.youHint, counter: false })}<p class="small" style="padding:0 18px">${esc(t.youInlineHint)}</p>` : '';
    return this.onb('hhname', { heading: t.hhTitle, body: t.hhBody, parts: `${you}${this.fieldHtml('hh', t.hhLabel, { value: this.s.hhName || t.hhDefault[this.s.kind ?? 'partner'] })}${this.btn('next', t.next, { honey: true })}` });
  }

  scr_stores() {
    const t = this.t;
    const chips = ['EDEKA', 'REWE', 'Lidl', 'Aldi Süd', 'dm', 'Rossmann'].map((n) => `<button class="chip ${this.s.stores.includes(n) ? 'on' : ''}" data-act="chip:${n}">${esc(n)}</button>`).join('');
    return this.onb('stores', { heading: t.storesTitle, body: t.storesBody, parts: `<div class="chips">${chips}</div>${this.btn('next', t.next, { honey: true })}${this.btn('skip', t.skip)}` });
  }

  scr_need() {
    const t = this.t;
    const chips = t.needs.map((n, i) => `<button class="chip ${this.s.needs.includes(i) ? 'on' : ''}" data-act="chip:${i}">${this.s.needs.includes(i) ? ic('check', 'sm') : ''}${esc(n)}</button>`).join('');
    return this.onb('need', { heading: t.needTitle, body: t.needBody, parts: `<div class="chips">${chips}</div>${this.btn('next', t.needNext(this.s.needs.length), { honey: true })}` });
  }

  scr_account() {
    const t = this.t;
    const buttons = `<button class="social google" data-act="google"><i class="glogo"></i>${esc(t.google)}</button><button class="social apple" data-act="apple"><span aria-hidden="true"></span>${esc(t.apple)}</button>${this.btn('email', t.email, { icon: 'mail_outline' })}`;
    const foot = `<div class="legalfoot"><u>${t.imprint}</u><span>·</span><u>${t.privacy}</u></div>`;
    if (this.o.role === 'join') return { title: t.joinAccountTitle(HOUSEHOLD), center: true, foot, body: `<h2 class="heading">${esc(t.accountTitle)}</h2><p class="lead">${esc(t.joinAccountBody(PETER))}</p>${buttons}` };
    const n = this.named();
    return { ...this.onb('account', { heading: n ? t.accountTitleNamed(n) : t.accountTitle, body: t.accountBody, parts: buttons }), foot };
  }

  scr_emailSignup() {
    const t = this.t;
    return { title: t.emailTitle, back: 'back', center: true, body: `${this.fieldHtml('mail', t.emailLabel, { value: this.p.via === 'email' ? this.p.email : 'lea.brandt87@gmail.com', counter: false })}${this.fieldHtml('pw', t.pwLabel, { value: '••••••••••', counter: false })}${this.btn('register', t.register, { honey: true })}` };
  }

  scr_confirm() {
    const t = this.t;
    const p = this.s.profile;
    const join = this.o.role === 'join';
    const head = join ? { title: t.joinTitle, center: true } : { ...this.onb('confirm', { heading: '', back: false }), body: undefined };
    const bar = join ? '' : this.progress('confirm').bar;
    if (p.source === 'social' && !this.s.confirmEdit) {
      const prov = this.s.provider === 'apple' ? 'Apple' : 'Google';
      return { ...head, body: `${bar}<h2 class="heading">${esc(t.confirmTitle)}</h2><div class="card"><span class="namebig emo">${esc(p.name)}</span></div><p class="lead">${esc(t.confirmBody(prov))}</p>${this.btn('yes', t.confirmYes, { honey: true })}${this.btn('confirmChange', t.confirmChange)}` };
    }
    const value = p.source === 'derived' ? '' : p.name;
    return { ...head, body: `${bar}<h2 class="heading">${esc(t.youTitle)}</h2><p class="lead">${esc(t.youBody)}</p>${this.fieldHtml('you', t.youLabel, { value, hint: t.youHint, autofocus: true })}${this.btn('next', t.next, { honey: true, needs: 'you' })}` };
  }

  scr_invite() {
    const t = this.t;
    const s = this.s;
    const n = this.named();
    const pr = this.progress('invite');
    const fn = firstName(s.profile);
    const hh = s.hhName || t.hhDefault[s.kind ?? 'partner'];
    const seesLine = this.o.option === 'DN4' && s.profile.source !== 'derived'
      ? `<div class="card soft"><span class="small">${esc(t.seesYou(t.partner))}</span><span class="preview emo">${esc(fn ? t.invitedBy(fn, hh) : t.invitedTo(hh))}</span><button class="textbtn" data-act="askChange">${ic('edit_outlined', 'sm')}${esc(t.change)}</button></div>` : '';
    const card = s.invited ? `<div class="card"><span class="code">K7QM-4XZP</span><span class="small">snacklist.app/join/K7QM-4XZP · ${esc(t.validUntil)}</span><div class="chips"><button class="textbtn" data-act="share">${ic('share', 'sm')}${esc(t.share)}</button><button class="textbtn" data-act="copy">${ic('content_copy', 'sm')}${esc(t.copyLink)}</button></div></div>` : '';
    const needs = s.needs.length;
    return {
      title: pr.title, center: true,
      body: `${pr.bar}<h2 class="heading">${esc(n ? t.inviteTitleNamed(n) : t.inviteTitle)}</h2><span class="bigicon">${ic('person_add_outlined')}</span><p class="lead center-text">${esc(t.inviteBody)}</p>${needs ? `<p class="center-text" style="font-weight:700">${esc(t.waiting(needs))}</p>` : ''}<p class="small center-text">${esc(t.joinHint)}</p>${seesLine}${card}${s.invited ? this.btn('another', t.another, { icon: 'person_add_outlined' }) : this.btn('invite', t.inviteTitle, { honey: true, icon: 'person_add_outlined' })}<button class="tonal" data-act="${s.invited ? 'toList' : 'later'}">${esc(s.invited ? t.toList : t.later)}</button>`,
    };
  }

  scr_joinpage() {
    const t = this.t;
    return {
      web: `<div class="urlbar">snacklist.app/join/K7QM-4XZP</div><div class="web"><div class="brandrow"><span class="applogo"><i></i></span>Snacklist</div><div class="joincard"><h2>${esc(t.invitedBy(PETER, HOUSEHOLD))}</h2><p class="muted">${esc(t.members(1))} · ${esc(t.openItems(12))}</p>${this.btn('join', t.joinWeb, { honey: true })}<hr style="border:0;border-top:1px solid var(--hl-color-divider);width:100%"><p class="section" style="margin:0">${esc(t.joinCodeLabel)}</p><span class="code">K7QM-4XZP</span><p class="small">${esc(t.joinCodeHint)}</p></div></div>`,
    };
  }

  scr_joinconfirm() {
    const t = this.t;
    const p = this.s.profile;
    const inline = this.o.option === 'DN2' ? `${this.fieldHtml('you', t.youLabel, { value: p.source === 'derived' ? '' : p.name, hint: t.youHint, counter: false })}<p class="small" style="padding:0 18px">${esc(t.youInlineJoin(PETER))}</p>` : '';
    return { title: t.joinTitle, back: null, center: true, body: `<div class="card"><span class="preview">${esc(t.invitedBy(PETER, HOUSEHOLD))}</span><span class="small">${esc(t.members(1))} · ${esc(t.openItems(12))}</span></div>${inline}${this.btn('joinHousehold', t.joinBtn, { honey: true })}<button class="tonal" data-act="cancelJoin">${esc(t.cancel)}</button>` };
  }

  scr_list() {
    const t = this.t;
    const s = this.s;
    if (this.o.round === 'DE' || this.o.role === 'join') {
      const nudge = this.o.option === 'DN5' && s.profile.source === 'derived'
        ? `<div class="card soft"><span class="emo">${esc(t.nudge(PETER, s.profile.name))}</span>${this.btn('nudge', t.nudgeBtn, { icon: 'edit_outlined' })}</div>` : '';
      const items = t.items.map((x, i) => `<div class="item"><span class="box"></span><span>${esc(x)}</span>${i < 2 ? `<span class="who">${PETER}</span>` : ''}</div>`).join('');
      return { title: HOUSEHOLD, tabs: 'list', list: true, body: `${nudge}<div class="banner">${ic('group_add_outlined', 'sm')}${esc(t.newFrom(2, PETER))}</div><div>${items}</div>` };
    }
    const hh = s.hhName || t.hhDefault[s.kind ?? 'partner'];
    const items = (s.needs.length ? s.needs.map((i) => t.needs[i]) : []).map((x) => `<div class="item"><span class="box"></span><span>${esc(x)}</span></div>`).join('');
    return { title: hh, tabs: 'list', list: true, body: `<div>${items}</div>` };
  }

  // Signed in: More, Account, the household page, the invite page (round DE).
  scr_more() {
    const t = this.t;
    const s = this.s;
    const row = (icon, label, act, cls = '', trail = 'chevron_right') => `<button class="mrow" ${act ? `data-act="${act}"` : ''}><span class="hexface ${cls}">${ic(icon, 'sm')}</span><span class="grow"><span class="mlabel">${esc(label)}</span></span>${trail ? `<span class="trail">${ic(trail, 'sm')}</span>` : ''}</button>`;
    let header = '';
    if (this.o.option === 'DE3') {
      const p = s.profile;
      const init = [...(p.name.trim() || '?')][0].toUpperCase();
      header = s.inline
        ? `<div class="group"><div class="profile" style="display:grid;gap:10px">${this.fieldHtml('edit', t.nameRow, { hint: t.youHint, autofocus: true })}<div style="display:flex;gap:8px;justify-content:flex-end"><button class="textbtn" data-act="cancel">${esc(t.cancel)}</button>${this.btn('inlineDone', t.done, { honey: true, needs: 'edit', icon: 'check' })}</div></div></div>`
        : `<div class="group" data-name-entry><div class="profile"><span class="hexface honey big"><b class="emo">${esc(init)}</b></span><span class="grow"><span class="pname emo">${esc(p.source === 'derived' ? t.nameRowEmpty : p.name)}</span><span class="msub">${esc(s.email)}</span></span><button class="iconbtn" data-act="editInline" aria-label="${esc(t.editName)}">${ic('edit_outlined')}</button></div></div>`;
    }
    return {
      title: t.moreTitle, tabs: 'more', list: true,
      body: `<div class="groups">${header}<div class="group">${row('manage_accounts_outlined', t.account, 'row:accountPage', 'cobalt')}${row('star_outline', t.premium, '', 'honey')}</div><div class="group">${row('home_outlined', HOUSEHOLD, 'row:household', 'mint')}${row('person_add_outlined', t.invitePartner, 'row:invites', 'honey')}</div><div class="group">${row('vpn_key_outlined', t.access, '', 'cobalt')}</div><div class="group">${row('settings_outlined', t.settings, '', 'mint')}</div><div class="group">${row('lightbulb_outline', t.tips, '')}${row('forum_outlined', t.feedback, '')}${row('help_outline', t.help, '', '', 'open_in_new')}</div><div class="group">${row('info_outline', t.imprintRow, '', '', 'open_in_new')}${row('privacy_tip_outlined', t.privacyRow, '', '', 'open_in_new')}${row('article_outlined', t.terms, '', '', 'open_in_new')}${row('description_outlined', t.licenses, '')}</div><div class="group">${row('logout', t.signOut, '', '', '')}</div><p class="version">${t.version}</p></div>`,
    };
  }

  scr_accountPage() {
    const t = this.t;
    const s = this.s;
    const p = s.profile;
    const nameRow = this.o.option === 'DE1'
      ? `<button class="lrow tap ${this.saved ? 'flash' : ''}" data-act="edit" data-name-entry>${ic('badge_outlined')}<span class="grow"><span class="t emo">${esc(p.source === 'derived' ? t.nameRowEmpty : p.name)}</span><span class="s">${esc(t.nameRow)} · ${esc(t.nameRowSub)}</span></span><span class="trail">${ic('edit_outlined', 'sm')}</span></button>` : '';
    return { title: t.accountTitleBar, back: 'tab:more', plain: true, tabs: 'more', list: true, body: `${nameRow}<div class="lrow">${ic('account_circle_outlined')}<span class="grow"><span class="t">${esc(s.email)}</span></span><span class="trail">${ic('content_copy', 'sm')}</span></div><div class="lrow">${ic('file_download_outlined')}<span class="grow"><span class="t">${esc(t.export)}</span><span class="s">${esc(t.exportBody)}</span></span></div><div class="lrow danger">${ic('delete_forever_outlined')}<span class="grow"><span class="t">${esc(t.del)}</span></span></div>` };
  }

  scr_household() {
    const t = this.t;
    const p = this.s.profile;
    const editable = ['DE2', 'DE5'].includes(this.o.option);
    const me = `<${editable ? 'button' : 'div'} class="lrow ${editable ? 'tap' : ''} ${this.saved ? 'flash' : ''}" ${editable ? 'data-act="edit" data-name-entry' : ''}>${ic('person_outline')}<span class="grow"><span class="t emo">${esc(t.you(p.name || t.unnamed))}</span></span>${editable ? `<span class="trailbtn">${ic('edit_outlined', 'sm')}</span>` : ''}</${editable ? 'button' : 'div'}>`;
    return { title: t.hhPage, back: 'tab:more', plain: true, tabs: 'more', list: true, body: `<p class="section">${esc(t.hhNameSection)}</p><div class="lrow">${ic('home_outlined')}<span class="grow"><span class="t" style="font-weight:700">${HOUSEHOLD}</span></span><span class="trailbtn">${esc(t.rename)}</span></div><p class="section">${esc(t.membersSection)}</p><div class="lrow">${ic('person_outline')}<span class="grow"><span class="t">Peter Brandt</span><span class="s">${esc(t.owner)}</span></span></div>${me}<div class="lrow">${ic('person_add_outlined')}<span class="grow"><span class="t">${esc(t.invitePeople)}</span></span><span class="trail">${ic('chevron_right', 'sm')}</span></div><div class="lrow danger">${ic('logout')}<span class="grow"><span class="t">${esc(t.leave)}</span></span></div>` };
  }

  scr_invites() {
    const t = this.t;
    const p = this.s.profile;
    const fn = firstName(p);
    const ctx = this.o.option === 'DE4'
      ? `<div class="card soft ${this.saved ? 'flash' : ''}" data-name-entry><span class="small">${esc(t.yourInviteShows)}</span><span class="preview emo">${esc(fn ? t.invitedBy(fn, HOUSEHOLD) : t.invitedTo(HOUSEHOLD))}</span><button class="textbtn" data-act="edit">${ic('edit_outlined', 'sm')}${esc(t.changeName)}</button></div>` : '';
    return { title: t.invitesTitle, back: 'tab:more', plain: true, tabs: 'more', list: true, body: `<p class="small">${esc(t.joinHint)}</p>${ctx}<div class="card"><span class="preview">${esc(t.invitePerson)}</span><span class="small">${esc(t.invitePersonBody)}</span>${this.btn('createLink', t.createLink, { honey: true })}</div>` };
  }

  // Peers: what Peter sees of Lea, and the join page of Lea's invite (frames fed by the bus).
  scr_peerHousehold() {
    const t = this.t;
    const p = this.bus?.profile ?? this.s.profile;
    return { title: t.hhPage, back: 'none', plain: true, tabs: 'more', list: true, body: `<p class="section">${esc(t.membersSection)}</p><div class="lrow">${ic('person_outline')}<span class="grow"><span class="t">${esc(t.you('Peter Brandt'))}</span><span class="s">${esc(t.owner)}</span></span></div><div class="lrow ${this.bus?.fresh ? 'flash' : ''}">${ic('person_outline')}<span class="grow"><span class="t emo" data-peer-name>${esc(p.name || t.unnamed)}</span></span></div>` };
  }

  scr_peerList() {
    const t = this.t;
    const p = this.bus?.profile ?? this.s.profile;
    const w = p.name || t.unnamed;
    const items = t.items.map((x, i) => `<div class="item"><span class="box"></span><span>${esc(x)}</span>${i < 2 ? `<span class="who emo">${esc(w)}</span>` : ''}</div>`).join('');
    return { title: HOUSEHOLD, tabs: 'list', list: true, body: `<div class="banner emo ${this.bus?.fresh ? 'flash' : ''}">${ic('group_add_outlined', 'sm')}<span data-peer-name>${esc(t.newFrom(2, w))}</span></div><div>${items}</div>` };
  }

  scr_peerJoin() {
    const t = this.t;
    const p = this.bus?.profile ?? this.s.profile;
    const fn = firstName(p);
    return { web: `<div class="urlbar">snacklist.app/join/R4TB-8MXC</div><div class="web"><div class="brandrow"><span class="applogo"><i></i></span>Snacklist</div><div class="joincard"><h2 class="emo" data-peer-name>${esc(fn ? t.invitedBy(fn, HOUSEHOLD) : t.invitedTo(HOUSEHOLD))}</h2><p class="muted">${esc(t.members(2))} · ${esc(t.openItems(5))}</p>${this.btn('none', t.joinWeb, { honey: true })}</div></div>` };
  }

  renderSheet() {
    const s = this.s;
    const t = this.t;
    if (!s.sheet) return '';
    if (s.sheet === 'google') {
      const name = this.p.via === 'google' ? this.p.social : 'Lea Brandt';
      const mail = this.p.via === 'google' ? this.p.email : 'lea.brandt87@gmail.com';
      return `<div class="scrim" data-act="close"></div><div class="sys"><h3>${esc(t.gChoose)}</h3><p class="opt">${esc(t.gTo)}</p><button class="acct" data-act="sys"><span class="avatar">${esc(name[0])}</span><span class="grow"><b style="display:block">${esc(name)}</b>${esc(mail)}</span></button></div>`;
    }
    if (s.sheet === 'apple') {
      const name = this.p.via === 'apple' ? this.p.social : 'Lea Brandt';
      return `<div class="scrim" data-act="close"></div><div class="sys"><h3>Snacklist</h3><p class="opt">${esc(t.aTitle)}</p><div class="acct"><span class="grow"><b style="display:block">${esc(t.aName)}</b>${esc(name || t.aNone)}</span></div><div class="acct"><span class="grow">${esc(this.p.via === 'apple' && !this.p.social ? t.aHide : t.aShare)}</span>${ic('check', 'sm')}</div><button class="cont" data-act="sys">${esc(t.aCont)}</button></div>`;
    }
    if (s.sheet === 'ask') {
      const join = s.screen === 'joinconfirm';
      return `<div class="scrim"></div><div class="sheet" role="dialog"><div class="handle"></div><div class="shead"><h2>${esc(t.askTitle)}</h2></div><div class="sbody"><p class="lead">${esc(join ? t.askJoin(PETER) : t.askInvite)}</p>${this.fieldHtml('ask', t.youLabel, { hint: t.youHint, autofocus: true })}${this.btn('askSave', join ? t.askSaveJoin : t.askSaveInvite, { honey: true, needs: 'ask' })}<button class="tonal" data-act="askLater">${esc(t.askNotNow)}</button></div></div>`;
    }
    if (s.sheet === 'edit') {
      const per = this.o.option === 'DE5';
      const unchanged = s.profile.source === 'derived' ? undefined : s.profile.name;
      return `<div class="scrim" data-act="cancel"></div><div class="sheet" role="dialog"><div class="handle"></div><div class="shead"><h2>${esc(per ? t.editTitleIn(HOUSEHOLD) : t.editTitle)}</h2></div><div class="sbody"><p class="lead">${esc(per ? t.editBodyIn(HOUSEHOLD) : t.editBody)}</p>${this.fieldHtml('edit', t.youLabel, { hint: t.youHint, autofocus: true })}${per ? `<button class="check ${s.all ? 'on' : ''}" data-act="editAll"><span class="hexbox">${s.all ? ic('check') : ''}</span><span>${esc(t.editAll)}</span></button>` : ''}${this.btn('save', t.save, { honey: true, needs: 'edit', unchanged })}<button class="tonal" data-act="cancel">${esc(t.cancel)}</button></div></div>`;
    }
    return '';
  }
}

// One shared name for a page: the DE phones write it, the peer frames read it.
export class NameBus {
  constructor() { this.profile = { name: '', source: 'none' }; this.subs = new Set(); this.fresh = false; }
  set(p) { this.profile = { ...p }; this.fresh = true; this.subs.forEach((f) => f()); }
}
