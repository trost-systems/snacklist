// Five rules for .github/workflows/*.yml and .github/actions/*/action.yml (job 220):
// - action-pinned: a `uses:` that is not a local path names a full commit SHA, a `docker://` image
//   its sha256 digest. A tag or branch can be moved to other code, which then runs with the job's
//   token and secrets.
// - secret-in-step: `secrets.X` is read only in a step's `env:` or `with:`. From a job's or the
//   workflow's `env:` every step and every action of the job gets it.
// - secret-needs-environment: a job that reads a secret declares `environment:`. A workflow file on
//   any pushed branch can read a repository-level secret; an environment can be limited to main,
//   and its secrets go only to its jobs. `release` is the store release's environment, `ops` the
//   one of the scheduled production jobs (backup, RevenueCat deletion, price drift); any other
//   name fails, since GitHub would create that environment empty on the first run.
// - no-cache-in-trusted-job: a job that reads a secret, is in an environment or holds a write
//   permission restores no Actions cache. Any run on main can write an entry, which such a job
//   would unpack and run next to its secrets and its token.
// - runner-pinned: `runs-on:` names a numbered image (ubuntu-24.04), not a `-latest` label. GitHub
//   moves `-latest` to a new image without a commit: ubuntu-latest became 26.04 on 2026-11-18, and
//   main's own commit then failed lint (a newer shellcheck), goldens and WebKit e2e (job 302).
// `secrets.GITHUB_TOKEN` is the run's own token and not a secret here. Every exception is an entry
// (file, job, rule, reason, and what it covers: `secrets` for the secret rules, "*" for the whole
// context, `actions` for the others: the action, or the label for runner-pinned) in
// scripts/workflow-hardening.allow.json; an entry or a listed secret or action that covers no
// finding any more is stale.
// Usage: deno run --allow-read --config scripts/deno.json scripts/workflow-hardening.ts [repo-dir]
import { parse } from '@std/yaml';

const ALLOW_FILE = 'scripts/workflow-hardening.allow.json';
const RULES = [
  'action-pinned',
  'secret-in-step',
  'secret-needs-environment',
  'no-cache-in-trusted-job',
  'runner-pinned',
] as const;
const SECRET_RULES: readonly string[] = ['secret-in-step', 'secret-needs-environment'];
type Rule = (typeof RULES)[number];

interface Finding {
  file: string;
  /** null outside a job: the workflow's own keys, or a composite action. */
  job: string | null;
  rule: Rule;
  /** What an entry lists to allow this: the secrets read, as written (ALL for the whole context),
   * or the action. */
  covers: string[];
  message: string;
}

interface Entry {
  file: string;
  job: string | null;
  rule: string;
  covers: string[];
  reason: string;
}

type Path = readonly (string | number)[];

const PINNED = /^(\.\/|docker:\/\/.+@sha256:[0-9a-f]{64}$|(?!docker:\/\/)[^@]+@[0-9a-f]{40}$)/;
// A `}}` inside a quoted string does not end the expression.
const EXPRESSION = /\$\{\{((?:'[^']*'|[^'])*?)\}\}/gs;
// `steps.secrets.outputs.x` and the string 'secrets.json' are not the secrets context.
const SECRET = /(?<![\w.'])secrets\b(?:\.(\w+)|\[\s*'(\w+)'\s*\])?/gi;
const ALL = '*';
/** The environments set up in the repository's settings; GitHub compares their names without case. */
const ENVIRONMENTS = ['release', 'ops'];
/** Actions that restore an Actions cache as they come: the input and the value that turn it off,
 * null when nothing does. */
const CACHES_BY_DEFAULT: Record<string, readonly [input: string, off: boolean] | null> = {
  'actions/setup-node': ['package-manager-cache', false],
  './.github/actions/deno': ['cache', false],
  'oven-sh/setup-bun': ['no-cache', true],
  // Runs oven-sh/setup-bun without `no-cache` (v3.0.1).
  'supabase/setup-cli': null,
};
/** The steps of each local composite action, by the path a `uses:` names it with. */
type LocalActions = ReadonlyMap<string, readonly unknown[]>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function* leaves(node: unknown, path: Path = []): Generator<[Path, string]> {
  if (typeof node === 'string') yield [path, node];
  else if (Array.isArray(node)) {
    for (const [i, child] of node.entries()) yield* leaves(child, [...path, i]);
  } else if (isRecord(node)) {
    for (const [key, child] of Object.entries(node)) {
      // GitHub evaluates an expression in a mapping's key too.
      if (key.includes('${{')) yield [[...path, key], key];
      yield* leaves(child, [...path, key]);
    }
  }
}

/** The secrets a value reads: in its `${{ }}` expressions, or all of it for an `if:`. */
function secretsIn(path: Path, text: string): string[] {
  const expressions = path.at(-1) === 'if'
    ? [text]
    : [...text.matchAll(EXPRESSION)].map(([, body = '']) => body);
  const names = expressions.flatMap((expression) =>
    [...expression.matchAll(SECRET)].map(([, dotted, indexed]) => dotted ?? indexed ?? ALL)
  );
  return [...new Set(names)].filter((name) => name.toUpperCase() !== 'GITHUB_TOKEN');
}

const show = (path: Path): string =>
  path.map((part) => typeof part === 'number' ? `[${part}]` : `.${part}`).join('').slice(1);

const secret = (name: string): string =>
  name === ALL ? 'the whole secrets context' : `secrets.${name}`;

/** Inputs that turn a cache on and do not end in `cache` (actions/setup-java). */
const OTHER_CACHE_SWITCHES = ['cache-jdk'];

/** The action a `uses:` names, without its ref, as GitHub compares it. */
const actionOf = (uses: string): string =>
  (uses.split('@')[0] ?? '').toLowerCase().replace(/\/+$/, '');

const is = (value: unknown, flag: boolean): boolean => value === flag || value === String(flag);

/** How a step uses the Actions cache, undefined when it does not. */
function cacheUse(
  step: unknown,
  local: LocalActions,
  inside: readonly string[] = [],
): string | undefined {
  if (!isRecord(step) || typeof step['uses'] !== 'string') return undefined;
  const action = actionOf(step['uses']);
  if (action.includes('cache')) return `runs '${action}'`;
  const inputs = isRecord(step['with']) ? step['with'] : {};
  for (const [key, value] of Object.entries(inputs)) {
    // `cache: npm` and `bundler-cache: true` turn a cache on, `no-cache: false` leaves one on.
    const [named, no] = /^(no-)?(?:.+-)?cache$/i.exec(key) ?? [];
    const switches = named !== undefined || OTHER_CACHE_SWITCHES.includes(key.toLowerCase());
    if (switches && !is(value, no !== undefined)) {
      return `gives '${action}' the input '${key}: ${JSON.stringify(value)}'`;
    }
  }
  const byDefault = CACHES_BY_DEFAULT[action];
  if (byDefault === null) {
    return `runs '${action}', which restores an Actions cache and has no input to turn that off`;
  }
  if (byDefault !== undefined) {
    const [input, off] = byDefault;
    return is(inputs[input], off) ? undefined : `runs '${action}' without '${input}: ${off}'`;
  }
  if (inside.includes(action)) return undefined;
  for (const inner of local.get(action) ?? []) {
    const use = cacheUse(inner, local, [...inside, action]);
    if (use !== undefined) return `runs '${action}', which ${use}`;
  }
  return undefined;
}

/** What a job's token may write, undefined for a token that only reads. */
function writes(permissions: unknown): string | undefined {
  if (permissions === undefined) return 'declares no permissions, so its token may write';
  if (!isRecord(permissions)) {
    return permissions === 'read-all' ? undefined : `holds 'permissions: ${permissions}'`;
  }
  const scopes = Object.entries(permissions).filter(([, level]) => level === 'write');
  return scopes.length === 0
    ? undefined
    : `holds ${scopes.map(([scope]) => `'${scope}: write'`).join(', ')}`;
}

function findingsIn(file: string, doc: Record<string, unknown>, local: LocalActions): Finding[] {
  const findings: Finding[] = [];
  const readBy = new Map<string | null, Set<string>>();
  for (const [path, text] of leaves(doc)) {
    const [top, name] = path;
    const job = top === 'jobs' && typeof name === 'string' ? name : null;
    const inside = job !== null ? path.slice(2) : top === 'runs' ? path.slice(1) : path;
    const at = job === null ? file : `${file}: job '${job}'`;
    const [first, second, third] = inside;
    const ofStep = first === 'steps' && typeof second === 'number';

    const isUses = inside.at(-1) === 'uses' && inside.length === (ofStep ? 3 : 1);
    if (isUses && !PINNED.test(text)) {
      findings.push({
        file,
        job,
        rule: 'action-pinned',
        covers: [actionOf(text)],
        message: `${at}: 'uses: ${text}' is not pinned. ` +
          (text.startsWith('docker://')
            ? `Name the image by its digest: docker://image@sha256:<64 hex>`
            : `Name the full 40-hex commit SHA, with the version as a comment: ` +
              `owner/action@<sha> # v1.2.3`),
      });
    }

    // A runner group's name is not an image.
    const label = job !== null && first === 'runs-on' && second !== 'group';
    if (label && /-latest$/i.test(text.trim())) {
      findings.push({
        file,
        job,
        rule: 'runner-pinned',
        covers: [text.trim()],
        message: `${at}: 'runs-on: ${text}' follows an image GitHub replaces without a commit. ` +
          `Name the image's version, as ubuntu-24.04 or macos-26, and move to a new one in a PR`,
      });
    }

    const stepInput = ofStep && (third === 'env' || third === 'with') && inside.length > 3;
    const where = job === null ? show(path) : `the job's ${show(inside)}`;
    // `secrets: inherit` hands a called workflow every secret.
    const inherits = inside.length === 1 && first === 'secrets' && text.trim() === 'inherit';
    for (const read of inherits ? [ALL] : secretsIn(path, text)) {
      readBy.set(job, (readBy.get(job) ?? new Set()).add(read));
      if (stepInput) continue;
      findings.push({
        file,
        job,
        rule: 'secret-in-step',
        covers: [read],
        message: `${at}: ${secret(read)} is read in ${where}. ` +
          `Move it to the env: (or with:) of the one step that needs it`,
      });
    }
  }

  const jobs = isRecord(doc['jobs']) ? doc['jobs'] : {};
  for (const [job, body] of Object.entries(jobs)) {
    const read = [...new Set([...readBy.get(null) ?? [], ...readBy.get(job) ?? []])];
    const environment = isRecord(body) ? body['environment'] : undefined;
    const named = isRecord(environment) ? environment['name'] : environment;
    const name = typeof named === 'string' ? named.trim() : '';

    const steps = isRecord(body) && Array.isArray(body['steps']) ? body['steps'] : [];
    const trusted = read.length > 0
      ? 'reads secrets'
      : environment !== undefined
      ? `is in the environment '${name}'`
      : writes(isRecord(body) ? body['permissions'] ?? doc['permissions'] : undefined);
    for (const step of trusted === undefined ? [] : steps) {
      const use = cacheUse(step, local);
      if (use === undefined || !isRecord(step) || typeof step['uses'] !== 'string') continue;
      findings.push({
        file,
        job,
        rule: 'no-cache-in-trusted-job',
        covers: [actionOf(step['uses'])],
        message: `${file}: job '${job}' ${trusted} and ${use}. Any run on main can write a ` +
          `cache entry, which this job would unpack and run. Turn the cache off ('cache: false'; ` +
          `'package-manager-cache: false' for setup-node; no 'bundler-cache') and install from ` +
          `the lockfile in a step, or replace an action that has no such input`,
      });
    }

    if (read.length === 0 || ENVIRONMENTS.some((known) => known === name.toLowerCase())) continue;
    const reads = `${file}: job '${job}' reads ${read.map(secret).join(', ')}`;
    findings.push({
      file,
      job,
      rule: 'secret-needs-environment',
      covers: read,
      message: name === ''
        ? `${reads} but declares no environment. Add 'environment: ops' ('release' in a release ` +
          `job; with 'deployment: false' where the job deploys nothing, as in backup.yml), so ` +
          `the secret can live in an environment that only main may use`
        : `${reads} in the environment '${name}', which is none of ${ENVIRONMENTS.join(', ')}. ` +
          `GitHub creates an unknown one on the first run, without rules or secrets. Use one ` +
          `of them, or add the new one to ENVIRONMENTS in scripts/workflow-hardening.ts`,
    });
  }
  return findings;
}

function names(dir: string): string[] {
  try {
    return [...Deno.readDirSync(dir)].map((entry) => entry.name).sort();
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
}

function read(path: string): string | undefined {
  try {
    return Deno.readTextFileSync(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound || error instanceof Deno.errors.NotADirectory) {
      return undefined;
    }
    throw error;
  }
}

function allowList(repoDir: string, problems: string[]): Entry[] {
  const text = read(`${repoDir}/${ALLOW_FILE}`);
  if (text === undefined) return [];
  const parsed: unknown = JSON.parse(text);
  const raw = isRecord(parsed) && Array.isArray(parsed['entries']) ? parsed['entries'] : [];
  const entries: Entry[] = [];
  raw.forEach((item: unknown, i) => {
    const name = `${ALLOW_FILE}: entry ${i + 1}`;
    const fields = isRecord(item) ? item : {};
    const { file, job = null, rule, reason } = fields;
    const [key, other] = SECRET_RULES.includes(String(rule))
      ? ['secrets', 'actions']
      : ['actions', 'secrets'];
    const covers = fields[key];
    const listed = Array.isArray(covers) && covers.length > 0 &&
      covers.every((c) => typeof c === 'string' && c.trim() !== '');
    if (typeof file !== 'string' || typeof rule !== 'string' || !RULES.some((r) => r === rule)) {
      problems.push(`${name}: needs a file and a rule (${RULES.join(', ')}).`);
    } else if (job !== null && typeof job !== 'string') {
      problems.push(`${name} (${file}): job must be a job's key.`);
    } else if (!listed || other in fields) {
      problems.push(
        `${name} (${file}): an entry lists what it covers and nothing else: "secrets": ["NAME"] ` +
          `for a secret rule ("*" for the whole context), "actions": ["owner/name"] for the others.`,
      );
    } else if (typeof reason !== 'string' || reason.trim() === '') {
      problems.push(`${name} (${file}): has no reason. Say why the rule cannot hold there yet.`);
    } else {
      entries.push({ file, job, rule, covers, reason });
    }
  });
  return entries;
}

/** Every problem with the repo's workflows and the allow-list, empty when they keep the rules. */
export function check(repoDir: string): string[] {
  const problems: string[] = [];
  const entries = allowList(repoDir, problems);

  const workflows = names(`${repoDir}/.github/workflows`).filter((n) => /\.ya?ml$/.test(n))
    .map((n) => `.github/workflows/${n}`);
  const actions = names(`${repoDir}/.github/actions`).flatMap((n) =>
    ['action.yml', 'action.yaml'].map((f) => `.github/actions/${n}/${f}`)
  );
  if (workflows.length === 0) problems.push(`No workflow in ${repoDir}/.github/workflows.`);

  const docs: [string, Record<string, unknown>][] = [];
  const local = new Map<string, readonly unknown[]>();
  for (const file of [...workflows, ...actions]) {
    const text = read(`${repoDir}/${file}`);
    if (text === undefined) continue;
    let doc: unknown;
    try {
      doc = parse(text);
    } catch (error) {
      problems.push(
        `${file}: is not valid YAML (${error instanceof Error ? error.message : error})`,
      );
      continue;
    }
    if (!isRecord(doc)) continue;
    docs.push([file, doc]);
    const runs = doc['runs'];
    if (isRecord(runs) && Array.isArray(runs['steps'])) {
      local.set(actionOf(`./${file.split('/').slice(0, -1).join('/')}`), runs['steps']);
    }
  }
  const findings = docs.flatMap(([file, doc]) => findingsIn(file, doc, local));

  const same = (a: string, b: string) => a.toUpperCase() === b.toUpperCase();
  const used = new Map<Entry, Set<string>>();
  for (const finding of findings) {
    const allowed = entries.filter((e) =>
      e.file === finding.file && e.job === finding.job && e.rule === finding.rule
    );
    for (const entry of allowed) {
      const covered = used.get(entry) ?? new Set();
      for (const item of finding.covers.filter((c) => entry.covers.some((e) => same(e, c)))) {
        covered.add(item.toUpperCase());
      }
      used.set(entry, covered);
    }
    const open = finding.covers.filter((item) =>
      !allowed.some((entry) => entry.covers.some((e) => same(e, item)))
    );
    if (open.length > 0) {
      const what = SECRET_RULES.includes(finding.rule)
        ? 'secret'
        : finding.rule === 'runner-pinned'
        ? 'label (under "actions")'
        : 'action';
      problems.push(
        `${finding.message} (${finding.rule}; an exception needs an entry in ${ALLOW_FILE} with ` +
          `its reason and the ${what}).`,
      );
    }
  }
  for (const entry of entries) {
    const where = entry.job === null ? entry.file : `${entry.file}, job '${entry.job}'`;
    const covered = used.get(entry);
    if (!covered) {
      problems.push(
        `${ALLOW_FILE}: the entry for ${where}, ${entry.rule} is stale, nothing there breaks the ` +
          `rule any more. Remove it.`,
      );
      continue;
    }
    const [what, does] = SECRET_RULES.includes(entry.rule)
      ? [secret, 'reads']
      : [(name: string) => `'${name}'`, 'uses'];
    for (const name of entry.covers.filter((c) => !covered.has(c.toUpperCase()))) {
      problems.push(
        `${ALLOW_FILE}: the entry for ${where}, ${entry.rule} lists ${what(name)}, which ` +
          `nothing there ${does} against the rule any more. Remove it from the entry.`,
      );
    }
  }
  return problems;
}

if (import.meta.main) {
  const repo = Deno.args[0] ?? new URL('..', import.meta.url).pathname.replace(/\/$/, '');
  const problems = check(repo);
  for (const problem of problems) console.error(problem);
  if (problems.length > 0) Deno.exit(1);
}
