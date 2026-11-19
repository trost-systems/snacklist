// Folder-level LEGO layers for app/lib (job 305, R9 of the LEGO CI report): every folder is core,
// a feature or the shell. Core imports only core; a feature imports core and itself, never another
// feature or the shell; the shell imports anything. The imports that broke a rule when the check
// came in are listed in scripts/import-direction.baseline. Each line there must still occur, and
// for every pair of folders the baseline may hold no more lines than the base branch's (lint.sh
// passes origin/main), so it can only shrink.
// Usage: deno run --allow-read --allow-run=git scripts/import-direction.ts [base-ref] [repo-dir]
//        ... --print   prints the imports that break a rule, in baseline form
export type Layer = 'core' | 'feature' | 'shell';

/** The layer of each folder of app/lib; '' is a file in app/lib itself (main.dart). */
export const LAYERS: Readonly<Record<string, Layer>> = {
  '': 'shell',
  shell: 'shell',
  more: 'shell',
  core: 'core',
  design: 'core',
  l10n: 'core',
  analytics: 'core',
  session: 'core',
  feedback: 'feature',
  'home_widget': 'feature',
  household: 'feature',
  list: 'feature',
  log: 'feature',
  oauth: 'feature',
  onboarding: 'feature',
  purchases: 'feature',
  report: 'feature',
  review: 'feature',
  settings: 'feature',
  siri: 'feature',
  tips: 'feature',
  trip: 'feature',
};

const LIB = 'app/lib';
export const BASELINE = 'scripts/import-direction.baseline';
const PACKAGE = 'package:family_groceries/';
const DIRECTIVE = /^\s*(?:import|export)\b[^;]*;/gm;
const URI = /'([^']+)'|"([^"]+)"/g;
// Strings match first, so a `//` inside one is no comment; the comments are dropped.
const NOISE = /'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|\/\/[^\n]*|\/\*[\s\S]*?\*\//g;

/** An import from one app/lib file of another, both relative to app/lib. */
export interface Import {
  from: string;
  to: string;
}

const folderOf = (path: string): string => path.includes('/') ? path.split('/')[0] ?? '' : '';
const edge = ({ from, to }: Import): string => `${from} -> ${to}`;

function* walk(dir: string): Generator<string> {
  for (
    const entry of [...Deno.readDirSync(dir)].sort((a, b) => a.name.localeCompare(b.name))
  ) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory) yield* walk(path);
    else if (entry.isFile && entry.name.endsWith('.dart')) yield path;
  }
}

function resolve(from: string, uri: string): string | undefined {
  if (uri.startsWith(PACKAGE)) return uri.slice(PACKAGE.length);
  if (uri.includes(':')) return undefined;
  const parts = from.split('/').slice(0, -1);
  for (const part of uri.split('/')) {
    if (part === '..') parts.pop();
    else if (part !== '.') parts.push(part);
  }
  return parts.join('/');
}

/** Every import and export between app/lib files, conditional ones included. */
export function importsIn(from: string, source: string): Import[] {
  const code = source.replace(NOISE, (match) => match.startsWith('/') ? '' : match);
  return [...code.matchAll(DIRECTIVE)].flatMap(([directive]) =>
    [...directive.matchAll(URI)].flatMap(([, single, double]) => {
      const to = resolve(from, single ?? double ?? '');
      return to === undefined ? [] : [{ from, to }];
    })
  );
}

/** Why the import breaks a layer rule and what to do instead, or undefined when it is allowed. */
export function ruleBroken({ from, to }: Import): string | undefined {
  const source = folderOf(from);
  const target = folderOf(to);
  const fromLayer = LAYERS[source];
  const toLayer = LAYERS[target];
  if (source === target || fromLayer === 'shell' || !fromLayer || !toLayer) {
    return undefined;
  }
  const name = (folder: string) => folder === '' ? 'app/lib' : `${folder}/`;
  if (toLayer === 'shell') {
    return `${name(source)} imports the shell (${name(target)}); only the shell does. Move what ` +
      `both need (a path constant, a type) into core/, or let the shell pass it in.`;
  }
  if (fromLayer === 'core' && toLayer === 'feature') {
    return `core folder ${name(source)} imports the feature ${name(target)}; core imports only ` +
      `core. Move the type both need into core, or have the feature pass the data in.`;
  }
  if (fromLayer === 'feature' && toLayer === 'feature') {
    return `feature ${name(source)} imports another feature, ${name(target)}; a feature imports ` +
      `only core and itself. Move what both share into core/, or let the shell wire them ` +
      `together (a builder or callback it passes in).`;
  }
  return undefined;
}

/** The imports in app/lib that break a layer rule, one baseline line each, sorted. */
export function violations(
  repoDir: string,
): { problems: string[]; edges: Map<string, string> } {
  const lib = `${repoDir}/${LIB}`;
  const problems: string[] = [];
  const edges = new Map<string, string>();
  for (const path of walk(lib)) {
    const from = path.slice(lib.length + 1);
    const folder = folderOf(from);
    if (!(folder in LAYERS)) {
      problems.push(
        `${LIB}/${folder}/ has no layer: add it to LAYERS in scripts/import-direction.ts ` +
          `(core, feature or shell; docs/DECISIONS.md job 305 says which is which).`,
      );
      continue;
    }
    for (const imported of importsIn(from, Deno.readTextFileSync(path))) {
      const why = ruleBroken(imported);
      if (why !== undefined) edges.set(edge(imported), why);
    }
  }
  return {
    problems: [...new Set(problems)],
    edges: new Map([...edges].sort()),
  };
}

function parseBaseline(text: string): string[] {
  return text.split('\n').map((line) => line.trim()).filter((line) =>
    line !== '' && !line.startsWith('#')
  );
}

const folderPair = (line: string): string =>
  line.split(' -> ').map((path) => folderOf(path)).join(' -> ');

function countByPair(lines: string[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const line of lines) {
    counts.set(folderPair(line), (counts.get(folderPair(line)) ?? 0) + 1);
  }
  return counts;
}

/**
 * Every problem with app/lib's imports and the baseline, empty when clean. `baseBaseline` is the
 * base branch's baseline, undefined when the base has none yet.
 */
export function check(
  repoDir: string,
  baseBaseline: string | undefined,
): string[] {
  const { problems, edges } = violations(repoDir);
  let listed: string[] = [];
  try {
    listed = parseBaseline(Deno.readTextFileSync(`${repoDir}/${BASELINE}`));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const known = new Set(listed);
  for (const [line, why] of edges) {
    if (!known.has(line)) {
      problems.push(`${LIB}/${line.replace(' -> ', ' imports ')}: ${why}`);
    }
  }
  for (const line of listed) {
    if (!edges.has(line)) {
      problems.push(
        `${BASELINE}: "${line}" no longer occurs. Delete the line.`,
      );
    }
  }
  if (baseBaseline !== undefined) {
    const before = countByPair(parseBaseline(baseBaseline));
    for (const [pair, count] of countByPair(listed)) {
      const allowed = before.get(pair) ?? 0;
      if (count > allowed) {
        problems.push(
          `${BASELINE}: ${count} lines for ${pair}, the base branch has ${allowed}. The baseline ` +
            `only shrinks: fix the new import instead of listing it.`,
        );
      }
    }
  }
  return problems;
}

async function baselineAt(
  repoDir: string,
  ref: string,
): Promise<string | undefined> {
  const exists = await new Deno.Command('git', {
    args: ['-C', repoDir, 'rev-parse', '--verify', '--quiet', `${ref}^{commit}`],
    stdout: 'null',
  }).output();
  if (!exists.success) throw new Error(`base ref ${ref} not found: git fetch origin main`);
  const { success, stdout } = await new Deno.Command('git', {
    args: ['-C', repoDir, 'show', `${ref}:${BASELINE}`],
    stdout: 'piped',
    stderr: 'null',
  }).output();
  return success ? new TextDecoder().decode(stdout) : undefined;
}

if (import.meta.main) {
  const args = Deno.args.filter((arg) => arg !== '--print');
  const base = args[0] ?? 'origin/main';
  const repo = args[1] ??
    new URL('..', import.meta.url).pathname.replace(/\/$/, '');
  if (Deno.args.includes('--print')) {
    for (const line of violations(repo).edges.keys()) console.log(line);
  } else {
    const problems = check(repo, await baselineAt(repo, base));
    for (const problem of problems) console.error(problem);
    if (problems.length > 0) Deno.exit(1);
  }
}
