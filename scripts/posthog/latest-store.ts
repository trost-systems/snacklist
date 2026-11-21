// Prints the newest public release per store from releases/releases.json, as a `min_version` to
// paste into releases/flags.json when a feature becomes complete (job 332, docs/ANALYTICS.md
// "Flags from main and minimum versions"). Without a public release: the version in
// app/pubspec.yaml, which the next store build carries.
//   deno run --allow-read=. scripts/posthog/latest-store.ts
import { parseLatestStore, type Requirement } from './plan.ts';

const repo = new URL('../../', import.meta.url);
const read = (path: string): Promise<string> => Deno.readTextFile(new URL(path, repo));
const shown = (r: Requirement | undefined): string =>
  r === undefined
    ? 'no public release yet'
    : `"${r.version}${r.build === undefined ? '' : `+${r.build}`}"`;

const latest = parseLatestStore(await read('releases/releases.json'));
const pubspec = /^version:\s*(\S+)/m.exec(await read('app/pubspec.yaml'))?.[1] ?? 'unknown';
console.log(`App Store:   ${shown(latest.ios)}`);
console.log(`Google Play: ${shown(latest.android)}`);
console.log(`app/pubspec.yaml: ${pubspec} (the build number comes from the release run)`);
