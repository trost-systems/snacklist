// Makes PostHog's feature flags match main (job 332, docs/ANALYTICS.md
// "Flags from main and minimum versions"). The plan is plan.ts; this file reads, prints and sends.
//   deno run --allow-read --allow-env --allow-net=eu.posthog.com scripts/posthog/sync-flags.ts [--dry-run]
import {
  type Action,
  desiredFlags,
  type Filters,
  type Group,
  InputError,
  isInternalGroup,
  parseExistingFlags,
  plan,
} from './plan.ts';

const repo = new URL('../../', import.meta.url);
const dryRun = Deno.args.includes('--dry-run');

class HttpError extends Error {}

function fail(message: string): never {
  console.error(`::error::${message}`);
  Deno.exit(1);
}

const read = (path: string): Promise<string> => Deno.readTextFile(new URL(path, repo));

async function summary(lines: readonly string[]): Promise<void> {
  const file = Deno.env.get('GITHUB_STEP_SUMMARY');
  if (file === undefined || file === '') return;
  await Deno.writeTextFile(
    file,
    ['### PostHog flag sync', '', ...lines.map((l) => `- ${l}`), ''].join('\n'),
    { append: true },
  );
}

type Method = 'GET' | 'POST' | 'PATCH';

function client(host: string, projectId: string, key: string) {
  const base = new URL(`/api/projects/${projectId}/`, host);
  const send = async (method: Method, url: URL, body?: unknown): Promise<unknown> => {
    // The key goes to the configured host only, also when PostHog's `next` names another.
    if (url.origin !== base.origin) throw new HttpError(`refusing ${method} to ${url.origin}`);
    const response = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }).catch((error: unknown) => {
      throw new HttpError(`${method} ${url.pathname} failed: ${String(error)}`);
    });
    const data: unknown = await response.json().catch(() => null);
    if (!response.ok) {
      const detail = typeof data === 'object' && data !== null && 'detail' in data
        ? `: ${String(data.detail)}`
        : '';
      throw new HttpError(`${method} ${url.pathname} answered HTTP ${response.status}${detail}`);
    }
    return data;
  };
  const list = async (path: string): Promise<unknown[]> => {
    const results: unknown[] = [];
    let url: URL | undefined = new URL(`${path}?limit=200`, base);
    while (url !== undefined) {
      const page = await send('GET', url);
      if (typeof page !== 'object' || page === null || !('results' in page)) {
        throw new HttpError(`GET ${url.pathname} answered without results`);
      }
      const { results: items } = page;
      if (!Array.isArray(items)) throw new HttpError(`GET ${url.pathname}: results not a list`);
      results.push(...items);
      const next = 'next' in page ? page.next : null;
      url = typeof next === 'string' && next !== '' ? new URL(next) : undefined;
    }
    return results;
  };
  return {
    flags: () => list('feature_flags/'),
    flag: (id: number) => send('GET', new URL(`feature_flags/${id}/`, base)),
    createFlag: (body: unknown) => send('POST', new URL('feature_flags/', base), body),
    // Only a flag's conditions ever change: nothing else is sent.
    patchFlag: (id: number, filters: Filters) =>
      send('PATCH', new URL(`feature_flags/${id}/`, base), { filters }),
  };
}

// Conditions this sync writes, by value; any other condition only counted (it may name a person).
function describeGroup(group: Group): string {
  if (isInternalGroup(group)) return 'internal';
  const shown: string[] = [];
  let others = 0;
  for (const p of group.properties ?? []) {
    const value = Array.isArray(p.value) ? p.value.join('|') : String(p.value);
    if (p.key === 'app_build' && p.operator === 'is_set') shown.push('app_build set');
    else if (p.key === 'app_version' || p.key === 'app_build' || p.key === 'platform') {
      shown.push(`${p.key} ${p.operator ?? 'exact'} ${value}`);
    } else others++;
  }
  if (others > 0) shown.push(`${others} other condition${others === 1 ? '' : 's'}`);
  const rollout = group.rollout_percentage ?? 100;
  return `${shown.length === 0 ? 'everyone' : shown.join(' and ')} at ${rollout} %`;
}

const describeGroups = (groups: readonly Group[] | undefined): string =>
  (groups ?? []).map((g) => `[${describeGroup(g)}]`).join(' ') || '[none]';

function describe(action: Action): string {
  switch (action.kind) {
    case 'create-flag':
      return `create flag ${action.key} (is_internal = true, 100 %)`;
    case 'update-flag-filters':
      return `update flag ${action.key}: ${describeGroups(action.before.groups)} -> ${
        describeGroups(action.after.groups)
      }`;
  }
}

async function main(): Promise<void> {
  const desired = desiredFlags(
    await read('app/lib/analytics/flags.dart'),
    await read('releases/flags.json'),
  );

  const key = Deno.env.get('POSTHOG_PERSONAL_API_KEY') ?? '';
  if (key === '') {
    const message = 'POSTHOG_PERSONAL_API_KEY is not set: PostHog flags were not synced ' +
      '(docs/ANALYTICS.md, "Flags from main and minimum versions")';
    console.log(`::notice::${message}`);
    await summary([message]);
    return;
  }
  const host = Deno.env.get('POSTHOG_API_HOST') || 'https://eu.posthog.com';
  const projectId = Deno.env.get('POSTHOG_PROJECT_ID') || '319492';
  if (!/^\d+$/.test(projectId)) fail('POSTHOG_PROJECT_ID must be a number');
  const posthog = client(host, projectId, key);

  const result = plan(desired, parseExistingFlags(await posthog.flags()));
  const lines = [...result.errors.map((e) => `error: ${e}`), ...result.actions.map(describe)];
  for (const line of lines) console.log(line);
  const count = (kind: Action['kind']): number =>
    result.actions.filter((a) => a.kind === kind).length;
  const total = `${count('create-flag')} flag(s) to create, ${
    count('update-flag-filters')
  } to update, ${result.errors.length} error(s)${dryRun ? '; dry run, nothing changed' : ''}`;
  console.log(total);
  await summary([...lines, total]);
  const planned = (): void => {
    if (result.errors.length === 0) return;
    const message = `${result.errors.length} flag(s) could not be planned`;
    // A bad condition in PostHog stays until someone fixes it there: a scheduled run only warns,
    // so it does not fail every 15 minutes; a push or a run by hand still fails.
    if (Deno.env.get('GITHUB_EVENT_NAME') === 'schedule') console.log(`::warning::${message}`);
    else fail(message);
  };
  if (dryRun) return planned();

  for (const action of result.actions) {
    switch (action.kind) {
      case 'create-flag':
        await posthog.createFlag(action.body);
        break;
      case 'update-flag-filters': {
        // Planned again on the flag as it is now, so an edit since the list is not overwritten.
        const flag = desired.filter((d) => d.key === action.key);
        const fresh = plan(flag, parseExistingFlags([await posthog.flag(action.id)]));
        for (const update of fresh.actions) {
          if (update.kind === 'update-flag-filters') {
            await posthog.patchFlag(update.id, update.after);
          }
        }
        break;
      }
    }
  }
  console.log('applied');
  // The other flags are synced; the run still fails so someone looks at the errors.
  planned();
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    if (error instanceof InputError || error instanceof HttpError) fail(error.message);
    throw error;
  }
}
