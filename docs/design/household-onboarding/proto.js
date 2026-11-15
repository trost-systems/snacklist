import { measure, upTo, stepsOf, combos, counted } from './metrics.js';
import { esc, ic } from './ui.js';

const roundId = document.body.dataset.round;
const { round } = await import(`./${roundId}/flows.js`);
const { options, scenarios, goals, page, steps: stepNames } = round;

const params = new URLSearchParams(location.search);
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ['100', '130', '200'].includes(params.get('ts')) ? params.get('ts') : '100',
  scen: Object.fromEntries(Object.entries(scenarios).map(([k, d]) => [k, d.values.includes(params.get(k)) ? params.get(k) : d.values[0]])),
  view: 'overview',
};
const byId = Object.fromEntries(options.map((o) => [o.id, o]));
const viewOf = (h) => (byId[h] ? h : h === 'rec' ? 'rec' : 'overview');
S.view = viewOf(location.hash.slice(2));

const L = (o) => (o == null ? '' : typeof o === 'string' ? o : o[S.lang]);
const label = (o) => (o.id === 'today' ? (S.lang === 'de' ? 'Heute' : 'Today') : o.id);
const W = () => page[S.lang];

const pathOf = (o, goal, scen = S.scen) => o.paths(scen)[goal];
const lastGoal = goals.at(-1).key;

// The Try-it phone: one per option, walking one goal's path.
const tryit = {};
const resetTry = (o) => (tryit[o.id] = { goal: lastGoal, i: 0, trail: [], taps: 0 });
options.forEach(resetTry);

// Render context for a state: language, strings, scenario, and the state that follows on the path shown.
const ctx = (o, path, i) => ({ lang: S.lang, T: round.T[S.lang], scen: S.scen, opt: o, next: path[i + 1]?.s ?? null, step: path[i + 1] ?? null, L });

const phone = (o, path, i, { live } = {}) => {
  const st = path[i];
  const html = o.screens[st.s](ctx(o, path, i));
  return `<div class="phone th-${S.theme}" data-opt="${o.id}" data-state="${st.s}" ${live ? 'data-live="1"' : ''} style="--ts:${Number(S.ts) / 100};--tsn:${Math.min(1.5, Number(S.ts) / 100)}">${html}<div class="homeind"><i></i></div></div>`;
};

const viaText = (o, step) => {
  if (!step) return '';
  const n = counted(step);
  const what = L(step.label) || (step.via === 'tap' ? '' : L(round.via[step.via]));
  return `<span class="via">${ic('arrow_forward', 'xs')} <span class="what">${esc(what)}</span> ${n ? `<span class="tag act">${n} ${n === 1 ? W().tap : W().taps}</span>` : `<span class="tag">${L(round.via[step.via])}</span>`}</span>`;
};

const stepTags = (o, s) =>
  stepsOf(o, s)
    .map((k) => `<span class="step" data-stepname="${k}"><i>${stepNames[k].n}</i>${L(stepNames[k])}</span>`)
    .join('');

const caption = (o, path, i) => {
  const m = o.meta[path[i].s];
  return `<figcaption><span class="steps">${stepTags(o, path[i].s)}</span><span>${esc(L(m.cap))}</span>${viaText(o, path[i + 1])}</figcaption>`;
};

// One storyboard: the longest goal's path; a frame where a shorter goal is reached carries its badge.
const storyboard = (o) => {
  const path = pathOf(o, lastGoal);
  return `<div class="story" data-testid="story" data-goal="${lastGoal}">${path
    .map((st, i) => {
      const reached = goals.filter(({ key }) => pathOf(o, key).length - 1 === i);
      const badge = reached.length ? `<span class="tag goal-badge" data-goal-end="${reached.map((g) => g.key).join(' ')}">${ic('flag_outlined', 'xs')} ${esc(reached.map((g) => L(g.label)).join(' = '))}</span>` : '';
      return `<figure data-i="${i}" data-frame-state="${st.s}">${caption(o, path, i)}${badge}${phone(o, path, i)}</figure>`;
    })
    .join('')}</div>`;
};

const numbers = (o, scen = S.scen) =>
  Object.fromEntries(
    goals.map(({ key }) => {
      const p = pathOf(o, key, scen);
      return [key, measure(o, p)];
    }),
  );

const btn = (k, v, text, pressed) => `<button data-set="${k}" data-v="${v}" aria-pressed="${pressed}">${text}</button>`;
const viewLink = (href, text, on) => `<a class="btn" href="#/${href}" ${on ? 'aria-current="page"' : ''}>${text}</a>`;
const controls = () => `<div class="controls">
  <div class="group">${viewLink('', W().overview, S.view === 'overview')}${options.map((o) => viewLink(o.id, label(o), S.view === o.id)).join('')}${viewLink('rec', W().rec, S.view === 'rec')}</div>
  ${Object.entries(scenarios)
    .map(([k, d]) => `<div class="group"><span class="lbl">${L(d.label)}</span>${d.values.map((v) => btn(`scen.${k}`, v, L(d.names[v]), S.scen[k] === v)).join('')}</div>`)
    .join('')}
  <div class="group">${btn('lang', 'en', 'English', S.lang === 'en')}${btn('lang', 'de', 'Deutsch', S.lang === 'de')}<span class="sep"></span>${btn('theme', 'light', W().light, S.theme === 'light')}${btn('theme', 'dark', W().dark, S.theme === 'dark')}<span class="sep"></span>${['100', '130', '200'].map((t) => btn('ts', t, `${W().text} ${t} %`, S.ts === t)).join('')}</div>
</div>`;

// The comparison table: every number measured over every scenario of the round (min–max), the rest from the options.
const range = (xs) => {
  const lo = Math.min(...xs), hi = Math.max(...xs);
  return lo === hi ? `${lo}` : `${lo}–${hi}`;
};
export const tableRows = () =>
  options.map((o) => {
    const all = combos(scenarios).map((sc) => numbers(o, sc));
    const now = numbers(o);
    return { o, all, now };
  });

const table = () => {
  const rows = tableRows();
  const cols = W().cols;
  return `<section class="rec" data-testid="comparison"><h2>${W().table}</h2><div class="table-wrap"><table class="cmp"><tr>${cols.map((c) => `<th>${c}</th>`).join('')}</tr>${rows
    .map(({ o, all, now }) => {
      const goalCells = goals
        .map(({ key }) => {
          const t = all.map((n) => n[key].taps), s = all.map((n) => n[key].screens);
          return `<td class="num" data-goal="${key}" data-taps="${now[key].taps}" data-screens="${now[key].screens}" data-taps-range="${range(t)}" data-screens-range="${range(s)}"><b>${now[key].taps}</b> / ${now[key].screens}<br><small>${W().allScen}: ${range(t)} / ${range(s)}</small></td>`;
        })
        .join('');
      return `<tr data-row="${o.id}" class="${o.id === round.rec.pick ? 'pick' : ''}"><td><b>${label(o)}</b><br><small>${esc(L(o.name))}</small></td>${goalCells}${round.facts
        .map((f) => `<td data-fact="${f}">${esc(L(o.facts[f]))}</td>`)
        .join('')}</tr>`;
    })
    .join('')}</table></div><p class="note">${W().tapsNote}</p></section>`;
};

let recHtml = { en: '', de: '' };

const pickTag = (o) =>
  o.id === round.rec.pick ? `<span class="tag pick">${W().pick}</span>` : o.id === round.rec.runnerUp ? `<span class="tag runner">${W().runnerUp}</span>` : '';

// Side by side: each option's path for the scenario as a strip of small phones.
const strips = () => `<section class="strips" data-testid="strips"><h2>${W().side}</h2><p class="note">${W().sideNote}</p>${options
  .map((o) => {
    const path = pathOf(o, lastGoal);
    const n = numbers(o);
    return `<div class="strip" data-strip="${o.id}"><a class="strip-head" href="#/${o.id}"><b>${label(o)}</b> ${esc(L(o.name))} ${pickTag(o)}<span class="muted">${goals.map(({ key, label: gl }) => `${L(gl)}: ${n[key].taps} ${W().taps} · ${n[key].screens} ${W().screens}`).join(' · ')}</span></a><div class="mini-row">${path
      .map((st, i) => `<div class="mini" title="${esc(L(o.meta[st.s].cap))}"><div class="mini-scale">${phone(o, path, i)}</div><span class="mini-cap">${stepTags(o, st.s)}</span></div>`)
      .join('')}</div></div>`;
  })
  .join('')}</section>`;

const overview = () => `<section class="cards">${options
    .map(
      (o) => `<a class="card" href="#/${o.id}" data-card="${o.id}"><span><b class="id">${label(o)}</b> ${pickTag(o)}</span><b>${esc(L(o.name))}</b><span class="muted">${esc(L(o.line))}</span><span>${o.service ? `<span class="tag svc">${esc(L(o.service))}</span>` : `<span class="tag stack">${W().stack}</span>`} ${o.pasteGone === false ? `<span class="tag">${W().pasteKept}</span>` : o.pasteGone ? `<span class="tag">${W().pasteGone}</span>` : ''}</span></a>`,
    )
    .join('')}</section>
  ${table()}${strips()}<article class="rec" data-testid="rec">${recHtml[S.lang]}</article>`;

const tryPane = (o) => {
  const st = tryit[o.id];
  const path = pathOf(o, st.goal);
  const next = path[st.i + 1];
  const done = !next;
  const outside = next && (next.via !== 'tap' || next.by === 'outside');
  const n = measure(o, path);
  return `<div class="try" data-testid="try"><div>${phone(o, path, st.i, { live: true })}</div><div class="try-side">
    <h3>${W().tryIt}</h3>
    ${goals.length > 1 ? `<div class="group">${goals.map((g) => `<button class="gesture ${st.goal === g.key ? 'on' : ''}" data-goal="${g.key}">${esc(L(g.label))}</button>`).join('')}</div>` : ''}
    <p>${W().goalNow(L(goals.find((g) => g.key === st.goal).label), n.taps, n.screens)}</p>
    ${outside ? `<button class="gesture" data-advance="1" data-testid="advance">${ic(round.viaIcon[next.via], 'sm')} ${esc(L(next.label) || L(round.via[next.via]))}${counted(next) ? ` (${counted(next)} ${counted(next) === 1 ? W().tap : W().taps})` : ''}</button>` : done ? '' : `<p class="muted">${W().tapHint}</p>`}
    <p class="trail" data-testid="trail" data-taps="${st.taps}" data-i="${st.i}" data-done="${done}">${done ? W().doneAfter(st.taps, st.i) : W().soFar(st.taps)}${st.trail.length ? `: ${st.trail.map(esc).join(' → ')}` : ''}</p>
    <button class="gesture" data-reset="1">${ic('undo', 'sm')} ${W().reset}</button></div></div>`;
};

const optionView = (o) => {
  const n = numbers(o);
  return `<section class="opt-head"><h2>${label(o)} · ${esc(L(o.name))} ${pickTag(o)}</h2><p>${esc(L(o.line))}</p>
  <p class="nums" data-testid="nums">${goals.map(({ key, label: gl }) => `<span data-goal="${key}"><b>${L(gl)}</b>: ${n[key].taps} ${W().taps}, ${n[key].screens} ${W().screens}${n[key].typed ? `, ${W().typed}` : ''}</span>`).join('')}</p>
  <details class="facts-box" ${matchMedia('(max-width: 440px)').matches ? '' : 'open'}><summary>${W().factsTitle}</summary><dl class="facts">${round.detail
    .map((k) => `<dt>${esc(L(round.detailNames[k]))}</dt><dd data-detail="${k}">${esc(L(o.detail[k]))}</dd>`)
    .join('')}</dl></details></section>
  ${storyboard(o)}${tryPane(o)}`;
};

const markHits = () => {
  // In every phone, outline what leads on: the storyboard shows where the tap goes, the Try-it phone where to tap next.
  document.querySelectorAll('.phone').forEach((p) => {
    const fig = p.closest('figure[data-i], .mini, .try');
    let nextState = null;
    if (p.dataset.live) {
      const o = byId[p.dataset.opt];
      const st = tryit[o.id];
      nextState = pathOf(o, st.goal)[st.i + 1];
    } else if (fig) {
      const o = byId[p.dataset.opt];
      const story = p.closest('[data-goal]');
      const goal = story ? story.dataset.goal : lastGoal;
      const path = pathOf(o, goal);
      const i = fig.dataset.i != null ? Number(fig.dataset.i) : [...fig.parentElement.children].indexOf(fig);
      nextState = path[i + 1];
    }
    const hit = nextState?.via === 'tap' ? p.querySelector(`[data-go="${nextState.s}"]`) : null;
    hit?.classList.add('next');
    // A tap step without its own label is named after the control it hits.
    const what = fig?.querySelector?.('figcaption .what');
    if (hit && what && !what.textContent) what.textContent = (hit.getAttribute('aria-label') || hit.textContent).replace(/\s+/g, ' ').trim().slice(0, 48);
  });
};

const render = () => {
  document.documentElement.lang = S.lang;
  document.title = W().title;
  const o = byId[S.view];
  const body = o ? optionView(o) : S.view === 'rec' ? `${table()}<article class="rec" data-testid="rec">${recHtml[S.lang]}</article>` : overview();
  const overviewHref = document.body.dataset.overview;
  document.getElementById('app').innerHTML = `<header class="page-head"><div class="title-row"><a class="back-link" href="${overviewHref}${S.lang === 'de' ? '?lang=de' : ''}" data-testid="back">← ${W().back}</a><h1>${W().title}</h1></div><p class="note compare">${W().compare}</p>${controls()}</header><main class="view" data-view="${S.view}" data-scen="${Object.values(S.scen).join('.')}">${body}</main>`;
  markHits();
};

const syncUrl = () => {
  const q = new URLSearchParams();
  if (S.lang === 'de') q.set('lang', 'de');
  if (S.theme === 'dark') q.set('theme', 'dark');
  if (S.ts !== '100') q.set('ts', S.ts);
  for (const [k, d] of Object.entries(scenarios)) if (S.scen[k] !== d.values[0]) q.set(k, S.scen[k]);
  history.replaceState(null, '', `${location.pathname}${q.size ? `?${q}` : ''}${location.hash}`);
};

const advance = (o, how) => {
  const st = tryit[o.id];
  const path = pathOf(o, st.goal);
  const next = path[st.i + 1];
  if (!next) return;
  st.taps += counted(next);
  st.trail.push(how);
  st.i += 1;
};

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-set],[data-go],[data-advance],[data-reset],[data-goal]');
  if (!el) return;
  if (el.dataset.set) {
    const [k, sub] = el.dataset.set.split('.');
    if (sub) S.scen[sub] = el.dataset.v;
    else S[k] = el.dataset.v;
    options.forEach(resetTry);
    syncUrl();
    return render();
  }
  const o = byId[S.view];
  if (!o) return;
  if (el.dataset.reset) {
    resetTry(o);
    return render();
  }
  if (el.dataset.goal && el.classList.contains('gesture')) {
    resetTry(o);
    tryit[o.id].goal = el.dataset.goal;
    return render();
  }
  const st = tryit[o.id];
  const next = pathOf(o, st.goal)[st.i + 1];
  if (el.dataset.advance && next && (next.via !== 'tap' || next.by === 'outside')) {
    advance(o, L(next.label) || L(round.via[next.via]));
    return render();
  }
  // Only the Try-it phone moves, and only along the path: a tap on what leads on.
  if (el.dataset.go && el.closest('[data-live]') && next?.via === 'tap' && el.dataset.go === next.s) {
    e.preventDefault();
    advance(o, (L(next.label) || el.getAttribute('aria-label') || el.textContent.trim()).replace(/\s+/g, ' ').slice(0, 40));
    render();
  }
});
addEventListener('hashchange', () => {
  S.view = viewOf(location.hash.slice(2));
  render();
  scrollTo(0, 0);
});

// The phone gets both themes from the site tokens, independent of the device setting.
const themeTokens = async () => {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
};

// Just enough Markdown for the recommendation files: headings, paragraphs, bullets, numbered lists, tables, bold, code.
const inline = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`(.+?)`/g, '<code>$1</code>');
const markdown = (md) =>
  md
    .trim()
    .split(/\n{2,}/)
    .map((block) => {
      const lines = block.split('\n');
      if (block.startsWith('### ')) return `<h3>${inline(block.slice(4))}</h3>`;
      if (block.startsWith('## ')) return `<h3>${inline(block.slice(3))}</h3>`;
      if (block.startsWith('# ')) return `<h2>${inline(block.slice(2))}</h2>`;
      if (block.startsWith('<!--')) return '';
      if (lines.every((l) => /^\s*- /.test(l) || /^\s{2,}\S/.test(l))) return `<ul>${block.split(/\n(?=- )/).map((l) => `<li>${inline(l.replace(/^- /, '').replace(/\n\s+/g, ' '))}</li>`).join('')}</ul>`;
      if (/^\d+\. /.test(lines[0])) return `<ol>${block.split(/\n(?=\d+\. )/).map((l) => `<li>${inline(l.replace(/^\d+\. /, '').replace(/\n\s+/g, ' '))}</li>`).join('')}</ol>`;
      if (lines[0].startsWith('|')) {
        const cells = (l) => l.split('|').slice(1, -1).map((c) => c.trim());
        const [head, , ...rest] = lines;
        return `<div class="table-wrap"><table class="cmp"><tr>${cells(head).map((c) => `<th>${inline(c)}</th>`).join('')}</tr>${rest.map((r) => `<tr>${cells(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</table></div>`;
      }
      return `<p>${inline(block.replace(/\n/g, ' '))}</p>`;
    })
    .join('');

const loadRec = async () => {
  for (const [lang, file] of [['en', `${round.rec.file}.md`], ['de', `${round.rec.file}.de.md`]]) {
    const res = await fetch(new URL(`./${roundId}/${file}`, import.meta.url));
    // The page shows the pick, reasons and questions; the live table above replaces the file's copy.
    recHtml[lang] = res.ok ? markdown((await res.text()).replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, '')) : '';
  }
};

await Promise.all([themeTokens(), loadRec(), document.fonts.ready]);
render();
window.__proto = { round, measure, upTo, stepsOf, combos, pathOf, numbers, tableRows };
