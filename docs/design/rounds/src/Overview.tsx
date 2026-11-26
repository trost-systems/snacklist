import { useEffect } from 'react';

const PR = 'https://github.com/trost-systems/snacklist/pull/';

// Rounds hosted on this deployment link to their page; older rounds live on their own draft PR.
const ROUNDS = [
  {
    href: '/reminders/sr/',
    code: 'SR1–SR5',
    title: 'Shopping reminders',
    date: '26 November 2026',
    question: 'How should a person add and manage several shopping reminders, each with its own day and time?',
  },
  {
    href: '/round',
    code: 'T1–T5',
    title: 'Onboarding transitions',
    date: '25 November 2026',
    question: 'How should onboarding move between steps?',
  },
  { href: `${PR}646`, code: 'SC', title: 'After a store’s last item', date: '22 November 2026', question: 'What should the card say once a store’s last item is ticked?' },
  { href: `${PR}630`, code: 'AI', title: 'App icon without the hexagon', date: '22 November 2026', question: 'What should the app icon look like without the hexagon?' },
  { href: `${PR}614`, code: 'RU', title: 'Recently used, expanded', date: '21 November 2026', question: 'How should the recently used items open up?' },
  { href: `${PR}611`, code: 'RD', title: 'Redesign without hexagons', date: '21 November 2026', question: 'What does the app look like with soft shapes instead of hexagons?' },
  { href: `${PR}604`, code: 'IO', title: 'Item order', date: '21 November 2026', question: 'How should items be ordered in the list?' },
  { href: `${PR}602`, code: 'TE', title: 'Totals with missing prices', date: '21 November 2026', question: 'How should a total read when some prices are missing?' },
  { href: `${PR}571`, code: 'AM', title: 'Add-match', date: '20 November 2026', question: 'How should adding show an item that already matches?' },
  { href: `${PR}568`, code: 'AS', title: 'After-add sheet', date: '19 November 2026', question: 'What should the sheet do right after an add?' },
  { href: `${PR}567`, code: 'OB', title: 'Onboarding stores', date: '19 November 2026', question: 'How should onboarding ask for stores?' },
  { href: `${PR}551`, code: 'OS · SS', title: 'Store app', date: '18 November 2026', question: 'How should the store pages work?' },
  { href: `${PR}531`, code: 'DN · DE', title: 'Display name', date: '17 November 2026', question: 'How should a person set and edit their display name?' },
  { href: `${PR}513`, code: 'RC1–RC3', title: 'Report content entry', date: '16 November 2026', question: 'Where should reporting content start?' },
  { href: `${PR}508`, code: 'AF · RI', title: 'Add feedback and reload indicator', date: '15 November 2026', question: 'How should an add confirm itself, and how should a reload show?' },
  { href: `${PR}494`, code: 'JH · CH', title: 'Join and create household', date: '15 November 2026', question: 'How should onboarding join or create a household?' },
  { href: `${PR}492`, code: 'FB1–FB5', title: 'Feedback experience', date: '15 November 2026', question: 'How should people send feedback?' },
  { href: `${PR}430`, code: 'TM1–TM5', title: 'Trip mode', date: '14 November 2026', question: 'How should the app ask about and time a shopping trip?' },
  { href: `${PR}414`, code: 'LD', title: 'List screen declutter', date: '13 November 2026', question: 'What can the list screen lose?' },
  { href: `${PR}401`, code: 'HL', title: 'Household and list in the top bar', date: '13 November 2026', question: 'How should the top bar show the household and the list?' },
  { href: `${PR}297`, code: 'S1–S5', title: 'Sync indicator', date: '6 November 2026', question: 'How should the app show that it is syncing?' },
] as const;

export function Overview() {
  useEffect(() => {
    document.title = 'Snacklist · Prototype rounds';
    document.documentElement.lang = 'en';
  }, []);

  return (
    <div className="overview">
      <header className="overview-hero">
        <p className="overview-kicker">Snacklist</p>
        <h1>Prototype rounds</h1>
        <p className="overview-lede">
          Each round answers one design question with five distinct options. Newest first. The two newest open here; older rounds open their draft pull request.
        </p>
      </header>
      <ol className="overview-list">
        {ROUNDS.map((round) => (
          <li key={round.href}>
            <a className="overview-card" href={round.href}>
              <span className="overview-code">{round.code}</span>
              <span className="overview-meta">
                <span className="overview-title">{round.title}</span>
                <span className="overview-date">{round.date}</span>
              </span>
              <span className="overview-q">{round.question}</span>
              <span className="overview-go">Open this round</span>
            </a>
          </li>
        ))}
      </ol>
    </div>
  );
}
