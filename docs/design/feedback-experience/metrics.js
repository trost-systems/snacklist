// The comparison table, computed from the flows so it can't drift from what the phones show.
// Taps: actions on the shortest path from the list to a sent note (a shake or a long-press counts as one;
// typing doesn't count). The verify script drives every path and checks it against these numbers.
import { fields, signals } from './model.js';

export const scenKeys = ['bug', 'error', 'idea'];

const sentByDefault = (flow, scen) => flow.att(scen).filter((r) => r.fixed || flow.defaults[r.key]);

export const taps = (flow, scen) => flow.path[scen].length - 1;

// Debug value: the signals (model.js `signals`) Peter gets without the user doing more, and their weighted sum.
export const debugSignals = (flow, scen) => {
  const got = new Set([...sentByDefault(flow, scen).flatMap((r) => fields[r.key].signal ?? []), ...(flow.extraSignals ?? [])]);
  return Object.keys(signals).filter((s) => got.has(s));
};
export const debugPoints = (flow, scen) => debugSignals(flow, scen).reduce((n, s) => n + signals[s].w, 0);

// Privacy exposure, in points: each field sent by default 1; list content sent by default 2 more; a field
// that can carry list content when the user chooses (FB2's screenshot) 1 more; each new processor 2, and
// 1 more if it keeps any data in the US. Low up to 5, medium up to 8, high above.
export const exposure = (flow, scen) => {
  const rows = sentByDefault(flow, scen);
  const listOn = rows.filter((r) => fields[r.key].list && !fields[r.key].redacted).length;
  const listChoice = flow.att(scen).filter((r) => fields[r.key].redacted).length;
  const proc = flow.processors.reduce((n, p) => n + 2 + (p.usPart ? 1 : 0), 0);
  return rows.length + 2 * listOn + listChoice + proc;
};
// Whether a flow sends list content (an item name) without the user switching it on, in any scenario.
export const listByDefault = (flow) => scenKeys.some((s) => sentByDefault(flow, s).some((r) => fields[r.key].list && !fields[r.key].redacted));

export const exposureLabel = (pts) => (pts <= 5 ? 'low' : pts <= 8 ? 'medium' : 'high');

export const row = (flow) => ({
  id: flow.id,
  taps: scenKeys.map((s) => taps(flow, s)),
  debug: scenKeys.map((s) => debugPoints(flow, s)),
  exposure: Math.max(...scenKeys.map((s) => exposure(flow, s))),
  build: flow.build.days,
  service: !!flow.service,
  listByDefault: listByDefault(flow),
  answer: flow.answer,
});
