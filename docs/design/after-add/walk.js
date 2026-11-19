// Each option's way through the same story, as reducer actions. The verify script replays the same actions as
// clicks on the live phone, so a tap count here is the number of clicks it took there.
export const storeCat = {
  today: ['open:store', 'store:lidl', 'open:cat', 'cat:chilled'],
  AS1: ['open:store', 'store:lidl', 'open:cat', 'cat:chilled'],
  AS2: ['open:where', 'store:lidl', 'cat:chilled'],
  AS3: ['open:store', 'store:lidl', 'open:cat', 'cat:chilled'],
  AS4: ['open:store', 'store:lidl', 'open:cat', 'cat:chilled'],
  AS5: ['store:lidl', 'cat:chilled'],
};
const openStore = { AS1: ['open:store'], AS2: ['open:where'], AS3: ['open:store'], AS4: ['open:store'], AS5: [] };
const openCat = { AS1: ['open:cat'], AS2: ['open:where'], AS3: ['open:cat'], AS4: ['open:cat'], AS5: [] };
const detailsActs = {
  AS1: ['open:details', 'details:Bio, 1 l'],
  AS2: ['brand:Hafergold', 'details:Bio, 1 l'],
  AS3: ['brand:Hafergold', 'details:Bio, 1 l'],
  AS4: ['open:details', 'details:Bio, 1 l'],
  AS5: ['details:Bio, 1 l'],
};
const typeFirst = ['type:Oat', 'enter'];
const typeFirstDe = ['type:Hafer', 'enter'];

// Frames: [key, actions from the start, gesture mark].
export const frames = (id, lang) => {
  const first = lang === 'de' ? typeFirstDe : typeFirst;
  const edited = [...first, 'qty+', ...storeCat[id]];
  const detailed = [...edited, ...detailsActs[id]];
  const after = [...edited, ...detailsActs[id].filter((a) => a !== 'open:details')];
  const second = [...after, 'type:Br'];
  const third = [...second, 'enter', 'type:E', 'enter'];
  return [
    ['open', [], null],
    ['added', first, null],
    ['picking', [...first, ...openStore[id]], null],
    ['pickingCat', [...first, ...openCat[id]], null],
    ['edited', edited, null],
    ['details', detailed, null],
    ['typing', second, null],
    ['second', [...second, 'enter'], null],
    ['third', third, null],
    ['dismiss', third, 'swipe'],
    ['closed', [...third, 'dismiss'], null],
  ];
};

export const todayFrame = (lang) => (lang === 'de' ? typeFirstDe : typeFirst);

// The recommendation (RECOMMENDATION.md explains it).
export const verdict = { pick: 'AS1', runner: 'AS2' };
