// Video 4, voice-add: Mia taps the microphone in the real add field and says a sentence. The app
// listens (red stop button, words in the field); she taps stop, the server splits the sentence and
// the three items land in their sections; in the store she ticks them off again, so the loop
// starts and ends on the same list. The video is silent: what she says appears as a speech
// caption, word by word on the recognizer's clock (app/test_driver/scripted_speech.dart: first
// word 0.7 s after listening starts, then one every 0.34 s).

import { captions, esc, frames, ICONS, page, phone, t, tBreak, touches } from '../lib.mjs';

const ONSET = 0.7;
const PER_WORD = 0.34;

export function plan(take, events, lang) {
  // Taps before the recording (the item bought in prepare) are logged at -1.
  const presses = events.filter((e) => e.kind === 'press' && e.t >= 0);
  const releases = events.filter((e) => e.kind === 'release' && e.t >= 0);
  const mic = presses[0].t / 1000;
  // The button acts on release; listening starts right after.
  const listen = releases[0].t / 1000;
  const added = events.find((e) => e.kind === 'mark' && e.text.startsWith('shown ')).t / 1000;
  const stop = presses[1].t / 1000;
  const ticks = presses.slice(2).map((e) => e.t / 1000);
  const words = take.measured.said.split(' ');
  const a = frames(mic - 1.0);
  const b = frames(ticks[ticks.length - 1] + 1.4);
  const duration = frames(b - a);
  const rel = (s) => frames(s - a);
  const wordAt = words.map((_, i) => rel(listen + ONSET + i * PER_WORD));
  const saidTo = rel(ticks[0] - 0.45);
  const cues = [
    { text: t('voice-add.say', lang), icon: 'mic', from: 0, to: saidTo, enter: false },
    { text: t('voice-add.tick', lang), icon: 'check', tone: 'mint', from: saidTo, to: rel(ticks[ticks.length - 1] + 0.75) },
    { text: t('voice-add.say', lang), icon: 'mic', from: rel(ticks[ticks.length - 1] + 0.75), to: duration, exit: false },
  ];
  // The captions file carries the sentence too, while it is said.
  const vttCues = [
    { text: cues[0].text, from: 0, to: wordAt[0] },
    { text: `${t('voice-add.quote', lang).replace('%s', take.measured.said)}`, from: wordAt[0], to: saidTo },
    ...cues.slice(1),
  ];
  return {
    a, b, duration, cues, vttCues, words, wordAt, saidTo,
    poster: frames(rel(added + 1.2)),
    beats: { mic: rel(mic), firstWord: wordAt[0], lastWord: wordAt[wordAt.length - 1], stop: rel(stop), added: rel(added), tick1: rel(ticks[0]), tick3: rel(ticks[ticks.length - 1]) },
    offset: (take.offsets?.mia ?? 0) / 1000,
    latency: { tapToAddedMessageMs: take.measured.addedMessageMs },
  };
}

// The crop runs from the drinks section to just under the add field, where the new rows land.
const LAYOUT = {
  wide: {
    phone: { box: { x: 296, y: -30, w: 256, h: 400 }, appTop: 283, fadeTop: [30, 64] },
    caption: 'left:calc(24 * var(--u));top:calc(40 * var(--u));width:calc(250 * var(--u))',
    align: 'left',
    said: { x: 24, y: 150, w: 252 },
  },
  compact: {
    phone: { box: { x: 47, y: 128, w: 264, h: 400 }, appTop: 361, fadeTop: [0, 30] },
    caption: 'left:calc(16 * var(--u));top:calc(14 * var(--u));width:calc(326 * var(--u))',
    align: 'center',
    said: { x: 16, y: 52, w: 326 },
  },
};

export function compose({ fmt, lang, events, p }) {
  const L = LAYOUT[fmt];
  const ph = phone({ id: 'mia', box: L.phone.box, appTop: L.phone.appTop, fadeTop: L.phone.fadeTop ?? null, src: 'assets/mia.mp4', start: 0, duration: p.duration, mediaStart: p.a + p.offset });
  const toTime = (ms) => ms / 1000 - p.a;
  const dots = touches({ id: 'tap', events, client: 'mia', toStage: ph.at, toTime, from: 0, to: p.duration });
  const ids = ['voice-add.say', 'voice-add.tick', 'voice-add.say'];
  const cues = p.cues.map((c, i) => (fmt === 'wide' ? { ...c, html: esc(tBreak(ids[i], lang)).replace('\n', '<br>') } : c));
  const caps = captions({ id: 'cap', cues, slot: L.caption, align: L.align });

  // What Mia says, as a speech caption: the words come as the recognizer reports them.
  const [open, close] = t('voice-add.quote', lang).split('%s');
  const words = p.words.map((w, i) => `<span class="w" id="w-${i}">${esc(w)}</span>`).join(' ');
  const said = `
  <div class="said${fmt === 'compact' ? ' said--center' : ''}" id="said" style="left:calc(${L.said.x} * var(--u));top:calc(${L.said.y} * var(--u));width:calc(${L.said.w} * var(--u))">
    <p class="said-bubble" id="said-bubble"><i class="mi">&#x${ICONS.mic};</i><span><span class="w" id="w-open">${esc(open)}</span>${words}<span class="w" id="w-close">${esc(close)}</span></span></p>
  </div>`;
  const tw = [];
  const first = p.wordAt[0];
  // The bubble arrives with the first word in it, never empty.
  tw.push(`tl.set('#w-open, #w-0', { opacity: 1 }, ${first.toFixed(3)});`);
  tw.push(`tl.fromTo('#said-bubble', { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.2, ease: 'power2.out' }, ${first.toFixed(3)});`);
  p.wordAt.forEach((at, i) => {
    if (i > 0) tw.push(`tl.to('#w-${i}${i === p.wordAt.length - 1 ? ', #w-close' : ''}', { opacity: 1, duration: 0.12, ease: 'power1.out' }, ${at.toFixed(3)});`);
  });
  tw.push(`tl.to('#said', { opacity: 0, y: -14, duration: 0.2, ease: 'power1.in' }, ${(p.saidTo - 0.2).toFixed(3)});`);
  return page({
    fmt,
    duration: p.duration,
    title: `voice-add ${lang} ${fmt}`,
    body: [ph.html, dots.html, said, caps.html].join('\n'),
    tweens: [...dots.tweens, ...tw, ...caps.tweens],
  });
}
