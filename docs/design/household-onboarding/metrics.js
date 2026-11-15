// The comparison numbers, computed from the paths so the tables can't drift from the phones.
// A path is a list of steps `{ s, via, n }`: the state shown and how the user got there.
// `tap` and `scan` count as actions (`n` of them, default 1: "open the App Store and search" is 2).
// `type` (typing text), `wait` (someone else acts) and `auto` (the system or app moves on) count none.
// Screens: the distinct screens after the entry (a state's `scr` groups states that are one screen).

export const counted = (step) => (step.via === 'tap' || step.via === 'scan' ? (step.n ?? 1) : 0);

const screenKey = (option, s) => option.meta[s]?.scr ?? s;

export const measure = (option, path) => {
  const taps = path.reduce((n, st) => n + counted(st), 0);
  let screens = 0;
  let prev = screenKey(option, path[0].s);
  for (const st of path.slice(1)) {
    const k = screenKey(option, st.s);
    if (k !== prev) screens += 1;
    prev = k;
  }
  const typed = path.filter((st) => st.via === 'type').length;
  return { taps, screens, typed };
};

// Everything up to and including the first state that carries `step`.
export const upTo = (option, path, step) => {
  const i = path.findIndex((st) => stepsOf(option, st.s).includes(step));
  return i < 0 ? null : path.slice(0, i + 1);
};

export const stepsOf = (option, s) => {
  const m = option.meta[s];
  if (!m) throw new Error(`${option.id}: no meta for state ${s}`);
  return [m.step].flat();
};

// All scenario combinations of a round, as objects ({ entry: 'link', app: 'missing', approval: 'off' }).
export const combos = (scenarios) =>
  Object.entries(scenarios).reduce((acc, [k, { values }]) => acc.flatMap((o) => values.map((v) => ({ ...o, [k]: v }))), [{}]);

export const scenKey = (scen) => Object.values(scen).join('.');
