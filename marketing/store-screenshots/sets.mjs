// The one registry of what the stores get (docs/STORE_SCREENSHOTS.md): the locales with their
// scenario, the shots in store order, and the device sets with their output size, the real
// viewport the app is captured at, the shots they carry and whether they carry words. capture.mjs
// films from it and compose.mjs frames from it; neither branches on a set's name.

export const LOCALES = {
  'de-DE': { lang: 'de', scenario: 'store-screenshots' },
  'en-US': { lang: 'en', scenario: 'store-screenshots-en' },
};

/** Every shot in store order. A set carries all of them or the subset it names. */
export const SHOTS = ['list', 'sync', 'add', 'order', 'voice', 'assist', 'api', 'invite'];
const TABLET_SHOTS = ['list', 'sync', 'order', 'add'];

/** The store rules a set's size must keep (checked by `sizeProblems`). */
const RULES = {
  // Play: each side within `sides`, the long side at most twice the short one, and 9:16 portrait
  // so the shots qualify for Play's recommendation formats.
  play: (w, h, sides) => [
    (Math.min(w, h) < sides[0] || Math.max(w, h) > sides[1]) && `sides must lie within ${sides[0]} to ${sides[1]}`,
    Math.max(w, h) > 2 * Math.min(w, h) && 'the long side may be at most twice the short one',
    w * 16 !== h * 9 && 'not 9:16',
  ],
  appstore: (w, h, sizes) => [!sizes.includes(`${w}x${h}`) && `not one of ${sizes.join(', ')}`],
};

/**
 * Device sets. `viewport` is a real device's CSS size in portrait, always under 840 dp wide, so
 * the app shows its phone layout with the bottom tabs (at 840 dp and more, More pages open beside
 * the More list, which shows the Premium row). `dpr` makes the capture at least as sharp as the
 * card it is shown on. `text: false` sets carry no words at all (Play tablets, spec D4-B).
 */
export const SETS = {
  'play-phone': { store: 'play', rule: [320, 3840], size: [1080, 1920], viewport: [432, 960], dpr: 2.5, shots: SHOTS, text: true },
  'play-tablet7': { store: 'play', rule: [320, 3840], size: [1440, 2560], viewport: [600, 960], dpr: 2, shots: TABLET_SHOTS, text: false },
  'play-tablet10': { store: 'play', rule: [1080, 7680], size: [1800, 3200], viewport: [800, 1280], dpr: 2, shots: TABLET_SHOTS, text: false },
  'appstore-iphone69': { store: 'appstore', rule: ['1320x2868', '1290x2796'], size: [1320, 2868], viewport: [440, 956], dpr: 3, shots: SHOTS, text: true },
  'appstore-ipad13': { store: 'appstore', rule: ['2064x2752', '2048x2732'], size: [2064, 2752], viewport: [768, 1024], dpr: 2.5, shots: SHOTS, text: true },
};

export const FEATURE_GRAPHIC = { size: [1024, 500], store: 'play' };
export const ICON = { size: [512, 512], store: 'play', source: 'app/web/icons/Icon-512.png' };
export const STORES = ['play', 'appstore'];

/** What breaks a set's store rule, if anything. */
export function sizeProblems(id) {
  const { store, rule, size } = SETS[id];
  return RULES[store](size[0], size[1], rule).filter(Boolean).map((p) => `${id} ${size.join('x')}: ${p}`);
}

/**
 * The frame geometry of a set in output pixels, from its size alone. `u` scales FR2's 1080 x 1920
 * design; a text set keeps the top for the headline and subline, a set without text gives the
 * card the height and the width. The card is a window of the capture standing on the canvas foot; `scale` maps
 * capture pixels to output pixels.
 */
export function layout(id) {
  const { size: [W, H], viewport, dpr, text } = SETS[id];
  const u = Math.min(W / 1080, H / 1920);
  // Without words the card is the whole screen (add bar and tabs too) and takes nearly the full
  // width, so a tablet's shorter screen still fills the canvas from the band down.
  const gutter = Math.round((text ? 110 : 40) * u);
  const cardTop = Math.round((text ? 610 : 230) * u);
  const cardW = W - 2 * gutter;
  const scale = cardW / (viewport[0] * dpr);
  return { W, H, u, gutter, cardTop, cardW, scale, span: Math.floor((H - cardTop) / scale) };
}

/** Every (locale, set, shot) a run makes, numbered per set in store order. */
export function plan({ locales, stores }) {
  return locales.flatMap((locale) =>
    Object.entries(SETS)
      .filter(([, s]) => stores.includes(s.store))
      .flatMap(([set, s]) => s.shots.map((shot, i) => ({ locale, set, shot, n: i + 1 }))));
}
