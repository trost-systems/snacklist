// Video 2, household-sync: the two members of „Unser Haushalt“, two real app instances filmed
// on one clock. Anna puts an item on the list; it arrives on Jonas's phone at the measured
// latency, under the household name; Anna's view follows it to the top of her list; Jonas ticks
// it off and it leaves both lists. The loop starts and ends on the same lists.

import { captions, esc, frames, page, phone, t, touches } from '../lib.mjs';

const MEMBERS = ['anna', 'jonas'];
const PAN = 0.6;

export function plan(take, events, lang) {
  const first = (pred) => events.find(pred).t / 1000;
  const presses = (who) => events.filter((e) => e.client === who && e.kind === 'press' && e.t >= 0).map((e) => e.t / 1000);
  const [open, closed] = presses('anna');
  const enter = first((e) => e.client === 'anna' && e.kind === 'key');
  const shown = first((e) => e.kind === 'mark' && e.text.startsWith('shown'));
  const tick = presses('jonas')[0];
  const goneAll = Math.max(...events.filter((e) => e.kind === 'mark' && e.text.startsWith('gone')).map((e) => e.t / 1000));
  const a = frames(open - 1.5);
  const up = closed + 0.3;
  const down = goneAll + 0.7;
  const b = frames(down + PAN + 1.0);
  const duration = frames(b - a);
  const rel = (s) => frames(s - a);
  const cues = [
    { text: t('household-sync.add', lang), who: 'anna', from: 0, to: rel(enter + 0.15), enter: false },
    { text: t('household-sync.arrive', lang), who: 'jonas', from: rel(enter + 0.15), to: rel(tick - 0.25) },
    { text: t('household-sync.tick', lang), who: 'jonas', from: rel(tick - 0.25), to: rel(goneAll + 1.3) },
    { text: t('household-sync.add', lang), who: 'anna', from: rel(goneAll + 1.3), to: duration, exit: false },
  ];
  // Poster: the item on both lists under „Unser Haushalt“, the sheet closed, still fresh on Jonas's.
  const poster = frames(rel(up + PAN + 0.15));
  const offsets = Object.fromEntries(MEMBERS.map((m) => [m, (take.offsets?.[m] ?? 0) / 1000]));
  const beats = { open, enter, shown, close: closed, up: up + PAN, tick, gone: goneAll, down: down + PAN };
  return {
    a, b, duration, cues, poster, offsets, latency: take.measured,
    pans: [{ at: rel(up), dur: PAN, to: 'list' }, { at: rel(down), dur: PAN, to: 'field' }],
    beats: Object.fromEntries(Object.entries(beats).map(([k, v]) => [k, rel(v)])),
  };
}

// Anna leads: her phone runs off the top and bottom and holds the add sheet (`field`); when it
// closes, her view moves to the top of her list (`list`), where the item landed in the
// Wochenmarkt, and back at the end. Jonas's phone steps back: wide, beside hers with a gap (no
// phone covers the other) and his screen top in view (the household name, the header note and
// the new row); compact, a band in front of the foot of Anna's phone, from his header note to
// the new row.
const LAYOUT = {
  wide: {
    caption: { slot: 'left:calc(24 * var(--u));top:calc(18 * var(--u));width:calc(200 * var(--u))', align: 'left' },
    phones: {
      jonas: { box: { x: 24, y: 122, w: 250.6, h: 220 }, appTop: 0, z: 2 },
      anna: { box: { x: 284, y: -60, w: 303, h: 420 }, field: 337, list: -79, z: 3 },
    },
    tags: { jonas: { x: 34, y: 110 }, anna: { x: 484, y: 118 } },
  },
  compact: {
    caption: { slot: 'left:calc(16 * var(--u));top:calc(14 * var(--u));width:calc(326 * var(--u))', align: 'center' },
    phones: {
      anna: { box: { x: 54, y: -204.5, w: 250.6, h: 514.6 }, field: 0, list: -458, z: 3, fadeTop: [252, 266] },
      jonas: { box: { x: 40, y: 262, w: 250.6, h: 200 }, appTop: 60, z: 4 },
    },
    tags: { jonas: { x: 236, y: 318 }, anna: { x: 252, y: 158 } },
  },
};

const AV = { anna: 'tomato', jonas: 'honey' };

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
    const pans = m === 'anna' ? p.pans.map((x) => ({ at: x.at, dur: x.dur, appTop: P[x.to] })) : [];
    phones[m] = phone({ id: m, box: P.box, appTop: P.appTop ?? P.field, pans, z: P.z, fadeTop: P.fadeTop, quiet: m !== 'anna', src: `assets/${m}.mp4`, start: 0, duration: p.duration, mediaStart: p.a + p.offsets[m] });
    body.push(phones[m].html);
    tweens.push(...phones[m].tweens);
  }
  for (const m of MEMBERS) {
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
