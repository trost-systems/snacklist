// Video 2, household-sync: three members of one household, three real app instances filmed on
// one clock. Mia puts an item on the list; it arrives on Noah's and Ida's phones at the
// measured latency; Noah ticks it off and it leaves all three lists. The loop starts and ends
// on the same lists.

import { captions, esc, frames, page, phone, t, touches } from '../lib.mjs';

const MEMBERS = ['mia', 'noah', 'ida'];

export function plan(take, events, lang) {
  const first = (pred) => events.find(pred).t / 1000;
  const open = first((e) => e.client === 'mia' && e.kind === 'press');
  const enter = first((e) => e.client === 'mia' && e.kind === 'key');
  const shown = first((e) => e.kind === 'mark' && e.text.startsWith('shown'));
  const tick = first((e) => e.client === 'noah' && e.kind === 'press');
  const goneAll = Math.max(...events.filter((e) => e.kind === 'mark' && e.text.startsWith('gone')).map((e) => e.t / 1000));
  const a = frames(open - 1.5);
  const b = frames(goneAll + 2.1);
  const duration = frames(b - a);
  const rel = (s) => frames(s - a);
  const cues = [
    { text: t('household-sync.add', lang), who: 'mia', from: 0, to: rel(enter + 0.15), enter: false },
    { text: t('household-sync.arrive', lang), who: 'noah+ida', from: rel(enter + 0.15), to: rel(tick - 0.25) },
    { text: t('household-sync.tick', lang), who: 'noah', from: rel(tick - 0.25), to: rel(goneAll + 1.3) },
    { text: t('household-sync.add', lang), who: 'mia', from: rel(goneAll + 1.3), to: duration, exit: false },
  ];
  // Poster: the item on all three lists, the sheet closed, still fresh (mint) on Noah's and Ida's.
  const close = events.filter((e) => e.client === 'mia' && e.kind === 'press')[1].t / 1000;
  const poster = frames(rel(close + 0.9));
  const offsets = Object.fromEntries(MEMBERS.map((m) => [m, (take.offsets?.[m] ?? 0) / 1000]));
  const beats = { open, enter, shown, close, tick, gone: goneAll };
  return { a, b, duration, cues, poster, offsets, latency: take.measured, beats: Object.fromEntries(Object.entries(beats).map(([k, v]) => [k, rel(v)])) };
}

// Mia leads: her phone runs off the top edge and holds the add sheet. Noah and Ida are fanned
// behind, their real screen tops in view (header note and the chilled rows), running off the
// bottom. Wide: Mia on the right, the caption above Noah's and Ida's phones. Compact: a deck,
// Mia on top (her head dissolves under the caption), then Noah's and Ida's phones as two bands,
// each showing its header note and the new row.
const LAYOUT = {
  wide: {
    caption: { slot: 'left:calc(30 * var(--u));top:calc(28 * var(--u));width:calc(210 * var(--u))', align: 'left' },
    phones: {
      ida: { box: { x: 30, y: 150, w: 250.6, h: 220 }, appTop: 0, z: 1 },
      noah: { box: { x: 140, y: 150, w: 250.6, h: 220 }, appTop: 0, z: 2 },
      mia: { box: { x: 250, y: -60, w: 303, h: 420 }, appTop: 281.1, z: 3 },
    },
    tags: { ida: { x: 40, y: 138 }, noah: { x: 150, y: 138 }, mia: { x: 488, y: 18 } },
  },
  compact: {
    caption: { slot: 'left:calc(16 * var(--u));top:calc(14 * var(--u));width:calc(326 * var(--u))', align: 'center' },
    phones: {
      mia: { box: { x: 54, y: -204.5, w: 250.6, h: 514.6 }, appTop: 0, z: 3, fadeTop: [252, 284] },
      noah: { box: { x: 40, y: 264, w: 250.6, h: 200 }, appTop: 0, z: 4 },
      ida: { box: { x: 68, y: 356, w: 250.6, h: 120 }, appTop: 0, z: 5 },
    },
    tags: { noah: { x: 236, y: 252 }, ida: { x: 264, y: 344 }, mia: { x: 252, y: 82 } },
  },
};

const AV = { mia: 'tomato', noah: 'honey', ida: 'cobalt' };

function tag(who, lang, at) {
  const name = t(`household-sync.member.${who}`, lang);
  return `<p class="tag" style="left:calc(${at.x} * var(--u));top:calc(${at.y} * var(--u))"><span class="hxp av hxp--${AV[who]}"><b>${esc(name[0])}</b></span>${esc(name)}</p>`;
}

function avatars(who, lang) {
  return who.split('+').map((w) => `<span class="hxp av hxp--${AV[w]}"><b>${esc(t(`household-sync.member.${w}`, lang)[0])}</b></span>`).join('');
}

export function compose({ fmt, lang, events, p }) {
  const L = LAYOUT[fmt];
  const body = [];
  const tweens = [];
  const phones = {};
  for (const m of MEMBERS) {
    const P = L.phones[m];
    phones[m] = phone({ id: m, box: P.box, appTop: P.appTop, z: P.z, fadeTop: P.fadeTop, quiet: m !== 'mia', src: `assets/${m}.mp4`, start: 0, duration: p.duration, mediaStart: p.a + p.offsets[m] });
    body.push(phones[m].html);
  }
  for (const m of ['mia', 'noah']) {
    const d = touches({ id: `tap-${m}`, events, client: m, toStage: phones[m].at, toTime: (ms) => ms / 1000 - p.a, from: 0, to: p.duration });
    body.push(d.html);
    tweens.push(...d.tweens);
  }
  for (const [who, at] of Object.entries(L.tags)) body.push(tag(who, lang, at));
  const caps = captions({ id: 'cap', cues: p.cues.map((c) => ({ ...c, iconHtml: avatars(c.who, lang) })), slot: L.caption.slot, align: L.caption.align });
  body.push(caps.html);
  tweens.push(...caps.tweens);
  return page({ fmt, duration: p.duration, title: `household-sync ${lang} ${fmt}`, body: body.join('\n'), tweens });
}
