// Video 1, add-tick: Anna types two items into the real add sheet, closes it, the view follows
// them to the top of the list, where they sit in the Wochenmarkt under „Unser Haushalt“, and
// she ticks both off again. One take, one phone; the view returns to the add field and the loop
// starts and ends on the same list.

import { captions, esc, frames, page, phone, t, tBreak, touches } from '../lib.mjs';

const PAN = 0.7;

/** Where the loop sits in the take, from its event log (seconds on the footage clock). */
export function plan(take, events, lang) {
  const at = (pred) => events.find(pred).t / 1000;
  const presses = events.filter((e) => e.kind === 'press' && e.t >= 0).map((e) => e.t / 1000);
  const open = presses[0];
  const close = at((e) => e.kind === 'mark' && e.text === 'close');
  const closed = presses.find((s) => s > close);
  const ticks = presses.slice(-2);
  // Calm list before the first tap. After the last tick its row leaves (260 ms), the view goes
  // back down to the add field and holds there: the frame the loop starts on.
  const a = frames(open - 1.0);
  const up = closed + 0.35;
  const down = ticks[1] + 0.9;
  const b = frames(down + PAN + 1.0);
  const duration = frames(b - a);
  const rel = (s) => frames(s - a);
  // The add caption holds until just before the first tick, so the poster (the new rows in place)
  // carries it.
  const cues = [
    { text: t('add-tick.add', lang), icon: 'add', from: 0, to: rel(ticks[0] - 0.45), enter: false },
    { text: t('add-tick.tick', lang), icon: 'check', tone: 'mint', from: rel(ticks[0] - 0.45), to: rel(ticks[1] + 0.75) },
    { text: t('add-tick.add', lang), icon: 'add', from: rel(ticks[1] + 0.75), to: duration, exit: false },
  ];
  // Poster: the two new rows under the household name, the sheet closed, before the first tick.
  const poster = frames(rel((up + PAN + ticks[0]) / 2));
  const enters = events.filter((e) => e.kind === 'key').map((e) => e.t / 1000);
  const beats = { open, enter1: enters[0], enter2: enters[1], close: closed + 0.3, up: up + PAN, tick1: ticks[0], tick2: ticks[1], down: down + PAN };
  return {
    a, b, duration, cues, poster,
    pans: [{ at: rel(up), dur: PAN, to: 'list' }, { at: rel(down), dur: PAN, to: 'field' }],
    beats: Object.fromEntries(Object.entries(beats).map(([k, v]) => [k, rel(v)])),
    offset: (take.offsets?.anna ?? 0) / 1000,
  };
}

// `field`: the view ends under the floating tab pill (logical y 855) with the add field and the
// open sheet in view. `list`: the top of the list, the household name „Unser Haushalt“ and the
// Wochenmarkt rows where the new items land.
const LAYOUT = {
  wide: { box: { x: 24, y: -40, w: 333, h: 400 }, field: 420, list: -48, caption: 'left:calc(381 * var(--u));top:calc(112 * var(--u));width:calc(171 * var(--u))', align: 'left' },
  compact: { box: { x: 24, y: -20, w: 310, h: 516 }, fadeTop: [82, 130], field: 229, list: -148, caption: 'left:calc(24 * var(--u));top:calc(22 * var(--u));width:calc(310 * var(--u))', align: 'center' },
};

export function compose({ fmt, lang, events, p }) {
  const L = LAYOUT[fmt];
  const pans = p.pans.map((x) => ({ at: x.at, dur: x.dur, appTop: L[x.to] }));
  const ph = phone({ id: 'anna', box: L.box, appTop: L.field, fadeTop: L.fadeTop, pans, src: 'assets/anna.mp4', start: 0, duration: p.duration, mediaStart: p.a + p.offset });
  const toTime = (ms) => ms / 1000 - p.a;
  const dots = touches({ id: 'tap', events, client: 'anna', toStage: ph.at, toTime, from: 0, to: p.duration });
  const ids = ['add-tick.add', 'add-tick.tick', 'add-tick.add'];
  const cues = p.cues.map((c, i) => (fmt === 'wide' ? { ...c, html: esc(tBreak(ids[i], lang)).replace('\n', '<br>') } : c));
  const caps = captions({ id: 'cap', cues, slot: L.caption, align: L.align });
  return page({
    fmt,
    duration: p.duration,
    title: `add-tick ${lang} ${fmt}`,
    body: [ph.html, dots.html, caps.html].join('\n'),
    tweens: [...ph.tweens, ...dots.tweens, ...caps.tweens],
  });
}
