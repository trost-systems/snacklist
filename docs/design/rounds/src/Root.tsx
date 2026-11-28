import { useEffect, useState } from 'react';
import { App } from './App';
import { AeRound } from './ae/AeRound';
import { DmRound } from './dm/DmRound';
import { Overview } from './Overview';
import { FhRound } from './fh/FhRound';
import { SrRound } from './sr/SrRound';

function currentPath(): string {
  const path = window.location.pathname.replace(/\/+$/, '') || '/';
  return path === '/index.html' ? '/' : path;
}

export function Root() {
  const [path, setPath] = useState(currentPath);

  useEffect(() => {
    const onPop = () => setPath(currentPath());
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  if (path === '/' ) return <Overview />;
  if (path === '/round' || path === '/onboarding/t') return <App />;
  if (path === '/reminders/sr') return <SrRound />;
  if (path === '/focus/fh') return <FhRound />;
  if (path === '/add/ae') return <AeRound />;
  if (path === '/add/dm') return <DmRound />;

  return (
    <div className="overview">
      <header className="overview-hero">
        <p className="overview-kicker">Snacklist</p>
        <h1>Page not found</h1>
        <p className="overview-lede">
          <a href="/">Back to all rounds</a>
        </p>
      </header>
    </div>
  );
}
