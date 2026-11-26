// The release timeline, /history and /en/history (job 105): one entry per public release of
// releases/releases.json, newest first, with the stats record.mjs computed when it was recorded.
// The site never asks git (Vercel clones shallow). Every string is in HISTORY_COPY, which
// scripts/copy-needed.mjs lists in COPY_NEEDED.md. status is `draft` until approved, then `reused`.

export const HISTORY_ROUTES = { de: '/history', en: '/en/history' };
const CHANGELOG_ROUTES = { de: '/de/changelog', en: '/en/changelog' };
// How many people the entry names under "Top contributors".
export const TOP_CONTRIBUTORS = 3;

// `{name}` is filled in at build time. status is `draft` until Peter approves the string, then `reused`.
export const HISTORY_COPY = {
  'history.footer': { de: 'Chronik', en: 'History', where: 'Every page: footer link', status: 'reused' },
  'history.title': { de: 'Chronik', en: 'History', where: 'History: page title and h1', status: 'reused' },
  'history.description': {
    de: 'Jede öffentliche Version von Snacklist: Datum, Projekttag, Commits, Mitwirkende und Codezeilen.',
    en: 'Every public version of Snacklist: date, project day, commits, contributors and lines of code.',
    where: 'History: meta and og:description',
    status: 'reused',
  },
  'history.intro': {
    de: 'Jede öffentliche Version von Snacklist, die neueste zuerst, mit Zahlen aus dem Code. Tag 0 ist der {date}, der Tag des ersten Commits.',
    en: 'Every public version of Snacklist, newest first, with numbers from the code. Day 0 is {date}, the day of the first commit.',
    where: 'History: intro under the h1',
    status: 'reused',
  },
  'history.empty': {
    de: 'Noch ist keine Version von Snacklist öffentlich in den Stores. Sobald es so weit ist, steht hier jede Version mit Datum und Zahlen.',
    en: 'No version of Snacklist is public in the stores yet. Once one is, every version shows up here with its date and numbers.',
    where: 'History: empty state (no public release)',
    status: 'reused',
  },
  'history.version': { de: 'Version {version}', en: 'Version {version}', where: 'History: entry heading', status: 'reused' },
  'history.day': { de: 'Tag {day}', en: 'Day {day}', where: 'History: entry date line, after the date', status: 'reused' },
  'history.commits-since': { de: 'Commits seit Version {version}', en: 'Commits since version {version}', where: 'History: entry stat label', status: 'reused' },
  'history.commits-first': { de: 'Commits bis zu dieser Version', en: 'Commits up to this version', where: 'History: entry stat label, first release', status: 'reused' },
  'history.contributors': { de: 'Mitwirkende', en: 'Contributors', where: 'History: entry stat label (people, without bots)', status: 'reused' },
  'history.loc': { de: 'Codezeilen', en: 'Lines of code', where: 'History: entry stat label', status: 'reused' },
  'history.top': { de: 'Am meisten beigetragen', en: 'Top contributors', where: 'History: entry stat label', status: 'reused' },
  'history.top-commits': { de: '{n} Commits', en: '{n} commits', where: 'History: commits of a top contributor', status: 'reused' },
  'history.top-commit': { de: '1 Commit', en: '1 commit', where: 'History: commits of a top contributor, one', status: 'reused' },
  'history.automation': { de: 'Bots und KI-Assistenten', en: 'Bots and AI assistants', where: 'History: entry stat label, the one label for every bot', status: 'reused' },
  'history.automation-commits': {
    de: 'an {n} von {total} Commits beteiligt',
    en: 'took part in {n} of {total} commits',
    where: 'History: bots and AI assistants value',
    status: 'reused',
  },
  'history.languages': { de: 'Codezeilen nach Sprache', en: 'Lines of code by language', where: 'History: entry stat label', status: 'reused' },
  'history.changelog-link': { de: 'Neuigkeiten in Version {version}', en: "What's new in version {version}", where: 'History: entry link to the changelog', status: 'reused' },
  'history.note': {
    de: 'Commits zählen ab der vorigen Version. Codezeilen sind die nicht leeren Zeilen des Quelltexts dieser Version, ohne erzeugte Dateien, Lockfiles und Dokumentation. Bots und KI-Assistenten zählen nicht als Mitwirkende.',
    en: 'Commits count from the previous version. Lines of code are the non-blank lines of this version’s source code, without generated files, lockfiles and documentation. Bots and AI assistants do not count as contributors.',
    where: 'History: note under the entries',
    status: 'reused',
  },
};

export class HistoryCopyError extends Error {}

export function t(id, locale, vars = {}) {
  const text = HISTORY_COPY[id]?.[locale];
  if (text === undefined) throw new HistoryCopyError(`history copy ${id} has no ${locale} text`);
  return text.replace(/\{(\w+)\}/g, (_match, key) => {
    if (!(key in vars)) throw new HistoryCopyError(`history copy ${id} needs {${key}}`);
    return String(vars[key]);
  });
}

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const formatDate = (iso, locale) => new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(iso));
const formatNumber = (n, locale) => new Intl.NumberFormat(locale).format(n);
export const anchor = (version) => `v${version.replaceAll('.', '-')}`;

// The people of a release: every contributor that is no bot, most commits first. Bots (identities
// with `bot: true`, `[bot]` logins, AI co-authors) are never named; they share one label.
export const people = (stats) =>
  stats.contributors
    .filter((c) => !c.bot)
    .sort((a, b) => b.commits - a.commits || b.additions - a.additions || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

// A display name and the GitHub login, never an e-mail address (the record has none).
export const personLabel = ({ name, github }) =>
  github && github.toLowerCase() !== name.toLowerCase() ? `${name} (@${github})` : github ? `@${github}` : name;

const stat = (label, value, cls = '') => `<div${cls ? ` class="${cls}"` : ''}><dt>${escapeHtml(label)}</dt><dd>${value}</dd></div>`;

function entry(release, previous, locale) {
  const { stats } = release;
  const n = (value) => escapeHtml(formatNumber(value, locale));
  const humans = people(stats);
  const rows = [
    stat(previous ? t('history.commits-since', locale, { version: previous.version }) : t('history.commits-first', locale), n(stats.commits)),
    stat(t('history.contributors', locale), n(humans.length)),
    ...('loc' in stats ? [stat(t('history.loc', locale), n(stats.loc.total))] : []),
  ];
  const top = humans.slice(0, TOP_CONTRIBUTORS).map((p) => {
    const commits = p.commits === 1 ? t('history.top-commit', locale) : t('history.top-commits', locale, { n: formatNumber(p.commits, locale) });
    return `<li><b>${escapeHtml(personLabel(p))}:</b> <span>${escapeHtml(commits)}</span></li>`;
  });
  const wide = [
    ...(top.length > 0 ? [stat(t('history.top', locale), `<ol class="history-people">${top.join('')}</ol>`, 'wide')] : []),
    ...(stats.automated_commits > 0
      ? [stat(t('history.automation', locale), escapeHtml(t('history.automation-commits', locale, { n: formatNumber(stats.automated_commits, locale), total: formatNumber(stats.commits, locale) })), 'wide')]
      : []),
    ...(stats.loc?.languages.length > 0
      ? [
          stat(
            t('history.languages', locale),
            `<ul class="history-languages">${stats.loc.languages.map((l) => `<li>${escapeHtml(l.language)} <span>${n(l.lines)}</span></li>`).join('')}</ul>`,
            'wide',
          ),
        ]
      : []),
  ];
  const id = anchor(release.version);
  return `<li class="history-entry" id="${id}">
<h2>${escapeHtml(t('history.version', locale, { version: release.version }))}</h2>
<p class="release-date"><time datetime="${release.date}">${escapeHtml(formatDate(release.date, locale))}</time> · ${escapeHtml(t('history.day', locale, { day: release.day }))}</p>
<dl class="history-stats">
${[...rows, ...wide].join('\n')}
</dl>
<p class="history-link"><a href="${CHANGELOG_ROUTES[locale]}#${id}">${escapeHtml(t('history.changelog-link', locale, { version: release.version }))}</a></p>
</li>`;
}

// The page body: `releases` are the public releases, oldest first (publicReleases).
export function historyBody(record, releases, locale) {
  const head = `<h1>${escapeHtml(t('history.title', locale))}</h1>\n`;
  if (releases.length === 0) return `${head}<p class="history-empty">${escapeHtml(t('history.empty', locale))}</p>\n`;
  const entries = releases.map((release, i) => entry(release, releases[i - 1] ?? null, locale)).reverse();
  return `${head}<p class="history-intro">${escapeHtml(t('history.intro', locale, { date: formatDate(record.project.day_zero, locale) }))}</p>
<ol class="history" role="list">
${entries.join('\n')}
</ol>
<p class="history-note">${escapeHtml(t('history.note', locale))}</p>
`;
}
