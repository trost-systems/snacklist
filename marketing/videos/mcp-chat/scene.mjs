// Video 3, mcp-chat: a generic AI chat in Hummlist's own style asks Hummlist's MCP server to add
// two items, then, by voice, to tick them off. The chat shows the real tool results of the take
// (capture/shots.ts calls the local mcp function with Sam's token) at the times they came back;
// Sam's real app shows the rows arrive and leave. The thread exits upwards at the end, so the
// loop starts and ends on an empty chat and the same list.

import { readFileSync } from 'node:fs';
import { captions, esc, frames, ICONS, page, phone, t, touches } from '../lib.mjs';

const arb = (lang) => JSON.parse(readFileSync(new URL(`../../../app/l10n/app_${lang}.arb`, import.meta.url), 'utf8'));

/** The app's own label for a seeded category (the household data is German). */
function categoryLabel(name, lang) {
  if (lang === 'de') return name;
  const de = arb('de');
  const key = Object.keys(de).find((k) => /^category[A-Z]/.test(k) && de[k] === name);
  return key ? arb('en')[key] : name;
}

const toolJson = (result) => JSON.parse(result.content.find((c) => c.type === 'text').text);

export function plan(take, events, lang) {
  const mark = (prefix) => events.find((e) => e.kind === 'mark' && e.text.startsWith(prefix)).t / 1000;
  const S1 = mark('mcp add_items sent');
  const A1 = mark('mcp add_items answered');
  const V = mark('voice start');
  const S2 = mark('mcp tick_items sent');
  const A2 = mark('mcp tick_items answered');
  const a = frames(S1 - 2.5);
  const exitAt = A2 + 2.0;
  const b = frames(exitAt + 0.65);
  const rel = (s) => frames(s - a);
  const added = toolJson(take.measured.added).added.map((i) => ({ name: i.name, category: categoryLabel(i.category, lang) }));
  const ticked = toolJson(take.measured.ticked).ticked.map((i) => ({ name: i.name }));
  const duration = frames(b - a);
  return {
    a, b, duration,
    t: { typeFrom: rel(S1 - 2.2), typeTo: rel(S1 - 0.55), send1: rel(S1 - 0.12), s1: rel(S1), a1: rel(A1), v: rel(V), s2: rel(S2), a2: rel(A2), exit: rel(exitAt) },
    added, ticked,
    cues: [{ text: t('mcp-chat.caption', lang), from: 0, to: duration, enter: false, exit: false }],
    poster: frames(rel(A1 + 1.4)),
    rows: { ...take.measured.newRows, shown: rel(mark('shown')), gone: rel(mark('gone')) },
    beats: { send: rel(S1), answer: rel(A1), voice: rel(V), send2: rel(S2), answer2: rel(A2), exit: rel(exitAt) },
    offset: (take.offsets?.sam ?? 0) / 1000,
    latency: { addAnswerMs: Math.round((A1 - S1) * 1000), tickAnswerMs: Math.round((A2 - S2) * 1000), addToAppMs: take.measured.addToAppMs, tickToAppMs: take.measured.tickToAppMs },
  };
}

const LAYOUT = {
  wide: {
    caption: 'left:calc(24 * var(--u));top:calc(18 * var(--u));width:calc(300 * var(--u))',
    align: 'row',
    chat: { x: 24, y: 62, w: 300, h: 246 },
    phone: { box: { x: 340, y: -30, w: 260, h: 400 }, appTop: 150 },
  },
  compact: {
    caption: 'left:calc(16 * var(--u));top:calc(14 * var(--u));width:calc(326 * var(--u))',
    align: 'center',
    chat: { x: 16, y: 52, w: 326, h: 206 },
    phone: { box: { x: 30, y: 226, w: 300, h: 260 }, appTop: 357 },
  },
};

const mi = (name) => `<i class="mi">&#x${ICONS[name]};</i>`;

export function compose({ fmt, lang, events, p }) {
  const L = LAYOUT[fmt];
  const T = p.t;
  const tw = [];
  const ph = phone({ id: 'sam', box: L.phone.box, appTop: L.phone.appTop, z: 1, src: 'assets/sam.mp4', start: 0, duration: p.duration, mediaStart: p.a + p.offset });

  // Composer: placeholder, then the request typed letter by letter, then empty again on send.
  const req1 = t('mcp-chat.add.request', lang);
  const letters = [...req1].map((ch, i) => `<span class="ch" id="ch-${i}">${esc(ch)}</span>`).join('');
  const step = (T.typeTo - T.typeFrom) / req1.length;
  [...req1].forEach((_, i) => tw.push(`tl.set('#ch-${i}', { display: 'inline' }, ${(T.typeFrom + i * step).toFixed(3)});`));
  tw.push(`tl.set('#ph1', { opacity: 0 }, ${T.typeFrom});`);
  tw.push(`tl.set('#caret', { opacity: 1 }, ${T.typeFrom});`);
  tw.push(`tl.set('#typed', { opacity: 0 }, ${T.s1});`);
  tw.push(`tl.set('#ph1', { opacity: 1 }, ${T.s1});`);
  // Voice: the mic turns on, bars move while Sam speaks, then the words go out as a message.
  tw.push(`tl.set('#ph1', { opacity: 0 }, ${T.v});`);
  tw.push(`tl.fromTo('#listen', { opacity: 0 }, { opacity: 1, duration: 0.16 }, ${T.v});`);
  tw.push(`tl.to('#mic b', { backgroundColor: 'var(--hl-color-tomato)', duration: 0.16 }, ${T.v});`);
  const bars = 14;
  for (let i = 0; i < bars; i++) {
    tw.push(`tl.set('#bar-${i}', { scaleY: 0.2 }, 0);`);
    const seq = [0.35, 0.9, 0.5, 1, 0.6, 0.8, 0.4].map((h, j) => ((h + i * 0.37 + j * 0.23) % 1) * 0.8 + 0.2);
    let at = T.v + 0.1;
    for (const h of seq) {
      tw.push(`tl.to('#bar-${i}', { scaleY: ${h.toFixed(2)}, duration: 0.2, ease: 'sine.inOut' }, ${at.toFixed(3)});`);
      at += 0.2;
      if (at > T.s2 - 0.2) break;
    }
  }
  tw.push(`tl.to('#listen', { opacity: 0, duration: 0.12 }, ${T.s2 - 0.12});`);
  tw.push(`tl.to('#mic b', { backgroundColor: 'var(--hl-color-cobalt)', duration: 0.16 }, ${T.s2 - 0.12});`);
  tw.push(`tl.set('#ph1', { opacity: 1 }, ${T.s2});`);

  // Thread: each message arrives whole from just below, carrying the thread up with it.
  const msg = (id, at, dur = 0.24) => tw.push(`tl.fromTo('#${id}', { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: ${dur.toFixed(3)}, ease: 'power2.out' }, ${at.toFixed(3)});`);
  // The working line lasts exactly as long as the real call did; its entrance fits inside it.
  const work = (id, from, to) => msg(id, from, Math.max(1 / 30, Math.min(0.24, to - 0.06 - from)));
  // Scrolls the thread so the second request sits at the top (measured from the laid-out page).
  const shift = (at) => tw.push(`tl.to('#thread', { y: () => -document.getElementById('m2').offsetTop, duration: 0.32, ease: 'power2.inOut' }, ${at.toFixed(3)});`);
  const rows = (items, done) => items.map((i) => `<li><span class="hxp hxp--mint ok"><b>${mi('check')}</b></span><span class="nm${done ? ' nm--done' : ''}">${esc(i.name)}</span>${i.category ? `<span class="cat">${esc(i.category)}</span>` : ''}</li>`).join('');
  const card = (id, title, items, done) => `<div class="msg card" id="${id}"><p class="card-h"><img src="assets/hummlist-icon.svg" alt=""><b>Hummlist</b><span>${esc(title)}</span></p><ul>${rows(items, done)}</ul></div>`;
  const thread = `
  <div class="thread" id="thread">
    <p class="msg me" id="m1">${esc(req1)}</p>
    <p class="msg work" id="w1"><span class="dots"><i id="d1a"></i><i id="d1b"></i><i id="d1c"></i></span>${esc(t('mcp-chat.working', lang))}</p>
    ${card('r1', t('mcp-chat.added', lang), p.added, false)}
    <p class="msg me" id="m2">${mi('mic')} ${esc(t('mcp-chat.tick.request', lang))}</p>
    <p class="msg work" id="w2"><span class="dots"><i id="d2a"></i><i id="d2b"></i><i id="d2c"></i></span>${esc(t('mcp-chat.working', lang))}</p>
    ${card('r2', t('mcp-chat.ticked', lang), p.ticked, true)}
  </div>`;
  msg('m1', T.s1);
  work('w1', T.s1 + 0.12, T.a1);
  tw.push(`tl.to('#w1', { opacity: 0, duration: 0.12 }, ${(T.a1 - 0.06).toFixed(3)});`);
  tw.push(`tl.set('#w1', { display: 'none' }, ${(T.a1 + 0.06).toFixed(3)});`);
  msg('r1', T.a1);
  msg('m2', T.s2);
  work('w2', T.s2 + 0.12, T.a2);
  tw.push(`tl.to('#w2', { opacity: 0, duration: 0.12 }, ${(T.a2 - 0.06).toFixed(3)});`);
  tw.push(`tl.set('#w2', { display: 'none' }, ${(T.a2 + 0.06).toFixed(3)});`);
  msg('r2', T.a2);
  // The first exchange makes room for the second; at the end the whole thread leaves upwards.
  shift(T.s2 - 0.05);
  // Scrolled out of the chat's view: no longer painted.
  tw.push(`tl.set('#m1, #r1', { opacity: 0 }, ${(T.s2 + 0.3).toFixed(3)});`);
  tw.push(`tl.to('#thread', { yPercent: -120, opacity: 0, duration: 0.6, ease: 'power2.in' }, ${T.exit.toFixed(3)});`);
  for (const [w, from, to] of [['1', T.s1 + 0.12, T.a1], ['2', T.s2 + 0.12, T.a2]]) {
    ['a', 'b', 'c'].forEach((d, i) => {
      for (let at = from + i * 0.08; at < to - 0.1; at += 0.36) {
        tw.push(`tl.fromTo('#d${w}${d}', { opacity: 0.25 }, { opacity: 1, duration: 0.18, yoyo: true, repeat: 1 }, ${at.toFixed(3)});`);
      }
    });
  }

  const chat = `
  <div class="chat" id="chat" style="left:calc(${L.chat.x} * var(--u));top:calc(${L.chat.y} * var(--u));width:calc(${L.chat.w} * var(--u));height:calc(${L.chat.h} * var(--u))">
    <div class="thread-box">${thread}</div>
    <div class="composer">
      <p class="field"><span id="ph1" class="ph">${esc(t('mcp-chat.composer', lang))}</span><span class="typed-box"><span id="typed">${letters}<i class="caret" id="caret"></i></span></span>
        <span id="listen" class="listen">${Array.from({ length: bars }, (_, i) => `<i id="bar-${i}"></i>`).join('')}<em>${esc(t('mcp-chat.listening', lang))}</em></span></p>
      <span class="hxp hxp--cobalt btn" id="mic"><b>${mi('mic')}</b></span>
      <span class="hxp btn" id="send"><b>${mi('up')}</b></span>
    </div>
  </div>`;

  // Taps on the chat: send, then the mic. Positions are in the chat's own corner, in u.
  const btn = (id) => {
    const c = L.chat;
    const hexW = 32 * 0.866;
    const right = id === 'send' ? 12 + hexW / 2 : 12 + hexW + 6 + hexW / 2;
    return { x: c.x + c.w - right, y: c.y + c.h - 12 - 17 };
  };
  const taps = [
    { at: T.send1, ...btn('send') },
    { at: T.v - 0.05, ...btn('mic') },
  ];
  const tapHtml = taps.map((k, i) => `<div id="ct-${i}" class="clip touch-host" data-start="${frames(Math.max(0, k.at - 0.12))}" data-duration="0.6" data-track-index="9" style="left:calc(${k.x} * var(--u));top:calc(${k.y} * var(--u))"><div class="touch" id="ct-${i}-dot"></div></div>`).join('\n');
  taps.forEach((k, i) => {
    tw.push(`tl.fromTo('#ct-${i}-dot', { scale: 0.55, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.1, ease: 'power2.out' }, ${(frames(k.at) - 0.1).toFixed(4)});`);
    tw.push(`tl.to('#ct-${i}-dot', { scale: 1.25, opacity: 0, duration: 0.24, ease: 'power2.in' }, ${(frames(k.at) + 0.1).toFixed(4)});`);
  });

  // Sam's own additions get no highlight in the app, so a mint marker at the phone's edge points
  // at the new rows from the moment they are in the list until they leave it.
  const mid = ph.at(0, (p.rows.top + p.rows.bottom) / 2);
  const marker = `<div id="mk" class="clip marker-host" data-start="${frames(p.rows.shown)}" data-duration="${frames(p.rows.gone - p.rows.shown + 0.3)}" data-track-index="7" style="left:calc(${L.phone.box.x} * var(--u));top:calc(${mid.y} * var(--u))"><span class="hxp hxp--mint marker" id="mk-i"><b>${mi('add')}</b></span></div>`;
  tw.push(`tl.fromTo('#mk-i', { scale: 0.4, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.2, ease: 'back.out(2)' }, ${frames(p.rows.shown).toFixed(3)});`);
  tw.push(`tl.to('#mk-i', { scale: 0.4, opacity: 0, duration: 0.18, ease: 'power2.in' }, ${frames(p.rows.gone).toFixed(3)});`);
  const caps = captions({ id: 'cap', cues: p.cues.map((c) => ({ ...c, icon: 'chat' })), slot: L.caption, align: L.align });
  return page({
    fmt,
    duration: p.duration,
    title: `mcp-chat ${lang} ${fmt}`,
    body: [ph.html, chat, tapHtml, marker, caps.html].join('\n'),
    tweens: [...tw, ...caps.tweens],
  });
}
