// Video 1, add-tick: Mia types two items into the real add sheet, closes it, the rows sit in
// their category, and she ticks both off again. One take, one phone; the loop starts and ends on
// the same list.

import { captions, esc, frames, page, phone, t, tBreak, touches } from '../lib.mjs';

/** Where the loop sits in the take, from its event log (seconds on the footage clock). */
export function plan(take, events, lang) {
  const at = (pred) => events.find(pred).t / 1000;
  const open = at((e) => e.kind === 'press');
  const close = at((e) => e.kind === 'mark' && e.text === 'close');
  const ticks = events.filter((e) => e.kind === 'press').slice(-2).map((e) => e.t / 1000);
  // Calm list before the first tap; after the last tick its row leaves (260 ms) and the list
  // holds about a second, which is the same frame the loop starts on.
  const a = frames(open - 1.0);
  const b = frames(ticks[1] + 1.4);
  const duration = frames(b - a);
  const rel = (s) => frames(s - a);
  // The add caption holds until just before the first tick, so the poster (the new rows in place)
  // carries it.
  const cues = [
    { text: t('add-tick.add', lang), icon: 'add', from: 0, to: rel(ticks[0] - 0.45), enter: false },
    { text: t('add-tick.tick', lang), icon: 'check', tone: 'mint', from: rel(ticks[0] - 0.45), to: rel(ticks[1] + 0.75) },
    { text: t('add-tick.add', lang), icon: 'add', from: rel(ticks[1] + 0.75), to: duration, exit: false },
  ];
  // Poster: the two new rows in their category, the sheet closed, before the first tick.
  const poster = frames(rel((close + ticks[0]) / 2 + 0.3));
  const enters = events.filter((e) => e.kind === 'key').map((e) => e.t / 1000);
  const beats = { open, enter1: enters[0], enter2: enters[1], close: close + 0.3, tick1: ticks[0], tick2: ticks[1] };
  return { a, b, duration, cues, poster, beats: Object.fromEntries(Object.entries(beats).map(([k, v]) => [k, rel(v)])), offset: (take.offsets?.mia ?? 0) / 1000 };
}

// The app region in view ends with the input bar (logical y 830, the tab bar stays out) and
// starts at a row edge, so the new items land in view.
const LAYOUT = {
  wide: { box: { x: 24, y: -40, w: 372, h: 400 }, appTop: 413, caption: 'left:calc(414 * var(--u));top:calc(112 * var(--u));width:calc(150 * var(--u))', align: 'left' },
  compact: { box: { x: 24, y: -20, w: 310, h: 516 }, fadeTop: [76, 126], appTop: 173, caption: 'left:calc(24 * var(--u));top:calc(22 * var(--u));width:calc(310 * var(--u))', align: 'center' },
};

export function compose({ fmt, lang, take, events, p }) {
  const L = LAYOUT[fmt];
  const ph = phone({ id: 'mia', box: L.box, appTop: L.appTop, fadeTop: L.fadeTop, src: 'assets/mia.mp4', start: 0, duration: p.duration, mediaStart: p.a + p.offset });
  const toTime = (ms) => ms / 1000 - p.a;
  const dots = touches({ id: 'tap', events, client: 'mia', toStage: ph.at, toTime, from: 0, to: p.duration });
  const ids = ['add-tick.add', 'add-tick.tick', 'add-tick.add'];
  const cues = p.cues.map((c, i) => (fmt === 'wide' ? { ...c, html: esc(tBreak(ids[i], lang)).replace('\n', '<br>') } : c));
  const caps = captions({ id: 'cap', cues, slot: L.caption, align: L.align });
  return page({
    fmt,
    duration: p.duration,
    title: `add-tick ${lang} ${fmt}`,
    body: [ph.html, dots.html, caps.html].join('\n'),
    tweens: [...dots.tweens, ...caps.tweens],
  });
}
