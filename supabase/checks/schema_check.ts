// Migration and RLS guards (DECISIONS, Job 12). Run from the repository root:
//   deno run --allow-read --allow-run=git,squawk supabase/checks/schema_check.ts [base-ref]
// The base ref defaults to origin/main. scripts/lint.sh runs it.

export type Migrations = ReadonlyMap<string, string>;
export type Finding = { file: string; message: string };

const MIGRATIONS = 'supabase/migrations';
const TESTS = 'supabase/tests';
const NAME = /^(\d{14})_[a-z0-9_]+\.sql$/;

/** Migrations on main are applied in production and never change (DECISIONS 31); new ones sort
 * after main's newest, because a deploy refuses a migration older than the remote's newest. */
export function checkHistory(base: Migrations, tree: Migrations): Finding[] {
  const findings: Finding[] = [];
  const newest = [...base.keys()].sort().at(-1) ?? '';
  const seen = new Map<string, string>();
  for (const [file, sql] of base) {
    const now = tree.get(file);
    if (now === undefined) {
      findings.push({
        file,
        message:
          `is on main and was deleted: restore it (git checkout origin/main -- ${MIGRATIONS}/${file})`,
      });
    } else if (now !== sql) {
      findings.push({
        file,
        message:
          `is on main and was modified: restore it (git checkout origin/main -- ${MIGRATIONS}/${file}) ` +
          'and put the change in a new migration (supabase migration new <name>)',
      });
    }
  }
  for (const file of [...tree.keys()].sort()) {
    const version = NAME.exec(file)?.[1];
    if (version === undefined) {
      findings.push({
        file,
        message: 'is not named <14-digit UTC timestamp>_<snake_case>.sql: create migrations with ' +
          'supabase migration new <name>',
      });
      continue;
    }
    const twin = seen.get(version);
    if (twin !== undefined) {
      findings.push({ file, message: `has the same version as ${twin}: rename one of them` });
    }
    seen.set(version, file);
    if (!base.has(file) && file <= newest) {
      findings.push({
        file,
        message: `sorts before ${newest}, the newest migration on main: rename it to a fresh ` +
          'timestamp (date -u +%Y%m%d%H%M%S) and rerun supabase db reset',
      });
    }
  }
  return findings;
}

type Table = {
  /** The last migration that created, renamed or altered the table, or changed its policies:
   * the one whose statement a finding is about, and the newest place a fix can follow. */
  file: string;
  household: boolean;
  rls: boolean;
  /** Policy name -> whether it calls is_household_member(household_id). */
  policies: Map<string, boolean>;
};

/** One identifier: "quoted" (case kept, "" for a quote) or plain (already lowercased). */
const PART = String.raw`"(?:[^"]|"")+"|[a-z_][\w$]*`;
const QUALIFIED = new RegExp(String.raw`^(${PART})(?:\s*\.\s*(${PART}))?`);
const unquote = (part: string) =>
  part.startsWith('"') ? part.slice(1, -1).replaceAll('""', '"') : part;

type Name = { schema: string; name: string; rest: string };

/** The possibly schema-qualified name at the start of `text`, each part unquoted; an unqualified
 * name is in public (the migrations' search_path). */
export function qualifiedName(text: string): Name | undefined {
  const [whole, firstPart, secondPart] = QUALIFIED.exec(text) ?? [];
  if (whole === undefined || firstPart === undefined) return undefined;
  const first = unquote(firstPart);
  const second = secondPart === undefined ? undefined : unquote(secondPart);
  return {
    schema: second === undefined ? 'public' : first,
    name: second ?? first,
    rest: text.slice(whole.length).trim(),
  };
}

/** A name as SQL would write it: plain when it can be, quoted otherwise. */
const sql = (name: string) =>
  /^[a-z_][a-z0-9_$]*$/.test(name) ? name : `"${name.replaceAll('"', '""')}"`;

const CREATE_TABLE = /^create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([\s\S]*)$/;
const ALTER_TABLE = /^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?([\s\S]*)$/;
const DROP_TABLE = /^drop\s+table\s+(?:if\s+exists\s+)?([\s\S]*)$/;
const CREATE_POLICY = new RegExp(
  String.raw`^create\s+policy\s+(${PART})\s+on\s+(?:only\s+)?([\s\S]*)$`,
);
const DROP_POLICY = new RegExp(
  String.raw`^drop\s+policy\s+(?:if\s+exists\s+)?(${PART})\s+on\s+([\s\S]*)$`,
);
const ALTER_POLICY = new RegExp(String.raw`^alter\s+policy\s+(${PART})\s+on\s+([\s\S]*)$`);
const MEMBER_CHECK =
  /\bis_household_member\s*\(\s*(?:(?:\w+|"[^"]+")\s*\.\s*)?"?household_id"?\s*\)/;
const HOUSEHOLD_COLUMN = /[(,]\s*"?household_id"?\s+\w/;
/** `like public.items` copies the columns (household_id included) but not RLS or policies. */
const LIKE = /[(,]\s*like\s+/g;

/** Every public table enables row level security, so PostgREST never serves it unfiltered. A
 * table with household_id also has a policy calling is_household_member(household_id) and a
 * cross-household case in a pgTAP test (CLAUDE.md). */
export function checkTables(tree: Migrations, tests: ReadonlyMap<string, string>): Finding[] {
  const tables = new Map<string, Table>();
  for (const [file, migration] of [...tree].sort(([a], [b]) => (a < b ? -1 : 1))) {
    for (const statement of statements(migration)) {
      apply(tables, file, statement);
    }
  }
  const crossHousehold = [...tests.values()].filter((sql) =>
    (sql.match(/\bcreate_household\s*\(/g) ?? []).length >= 2
  );
  const findings: Finding[] = [];
  for (const [name, table] of [...tables].sort(([a], [b]) => a.localeCompare(b))) {
    const qualified = `public.${sql(name)}`;
    if (!table.rls) {
      findings.push({
        file: table.file,
        message: `${qualified} does not enable row level security: add ` +
          `"alter table ${qualified} enable row level security;" and its policies`,
      });
    }
    if (!table.household) continue;
    if (![...table.policies.values()].some(Boolean)) {
      findings.push({
        file: table.file,
        message: `${qualified} has household_id but no policy using ` +
          `public.is_household_member(household_id): add one, e.g. "create policy ` +
          `${sql(`${name}_member`)} on ${qualified} for select to authenticated using ` +
          `(public.is_household_member(household_id));"`,
      });
    }
    if (!crossHousehold.some((sql) => mentions(sql, name))) {
      findings.push({
        file: table.file,
        message: `${qualified} has household_id but no pgTAP test with two households touches ` +
          `it: add a cross-household case for ${qualified} to ${TESTS}/rls.test.sql`,
      });
    }
  }
  return findings;
}

/** Whether a test's SQL names public.<name>, in any quoting, strings included (pgTAP's
 * throws_ok and lives_ok take their SQL as a string), comments excluded. */
function mentions(test: string, name: string): boolean {
  const text = statements(test, { keepStrings: true }).join(';\n').replace(
    /"(?:[^"]|"")*"|[^"]+/g,
    (s) => s.startsWith('"') ? s : s.toLowerCase(),
  );
  for (const m of text.matchAll(/(?<![\w$".])(?:public|"public")\s*\./g)) {
    const found = qualifiedName(text.slice(m.index));
    if (found?.schema === 'public' && found.name === name) return true;
  }
  return false;
}

/** The public table a statement's remainder starts with, and the text after its name. */
function publicTable(text: string | undefined): { name: string; rest: string } | undefined {
  const found = text === undefined ? undefined : qualifiedName(text);
  return found?.schema === 'public' ? found : undefined;
}

function apply(tables: Map<string, Table>, file: string, statement: string) {
  let m: RegExpExecArray | null;
  if ((m = CREATE_TABLE.exec(statement))) {
    const created = publicTable(m[1]);
    if (created === undefined) return;
    const copies = [...created.rest.matchAll(LIKE)].map((like) =>
      publicTable(created.rest.slice(like.index + like[0].length))?.name
    );
    tables.set(created.name, {
      file,
      household: HOUSEHOLD_COLUMN.test(created.rest) ||
        copies.some((source) => source !== undefined && tables.get(source)?.household === true),
      rls: false,
      policies: new Map(),
    });
  } else if ((m = ALTER_TABLE.exec(statement))) {
    const altered = publicTable(m[1]);
    const table = altered && tables.get(altered.name);
    if (altered === undefined || table === undefined) return;
    const action = altered.rest;
    table.file = file;
    const [, newName] = /^rename\s+to\s+([\s\S]*)$/.exec(action) ?? [];
    const to = newName === undefined ? undefined : qualifiedName(newName);
    if (to) {
      tables.delete(altered.name);
      tables.set(to.name, table);
    }
    const [, schema] = /^set\s+schema\s+([\s\S]*)$/.exec(action) ?? [];
    if (schema !== undefined && qualifiedName(schema)?.name !== 'public') {
      tables.delete(altered.name);
    }
    if (/\brename\s+(?:column\s+)?"?household_id"?\s+to\s/.test(action)) table.household = false;
    if (/\brename\s+(?:column\s+)?\S+\s+to\s+"?household_id"?$/.test(action)) {
      table.household = true;
    }
    if (/\benable\s+row\s+level\s+security\b/.test(action)) table.rls = true;
    if (/\bdisable\s+row\s+level\s+security\b/.test(action)) table.rls = false;
    if (/\badd\s+(?:column\s+)?(?:if\s+not\s+exists\s+)?"?household_id"?\s/.test(action)) {
      table.household = true;
    }
    if (/\bdrop\s+(?:column\s+)?(?:if\s+exists\s+)?"?household_id"?(?:\s|,|$)/.test(action)) {
      table.household = false;
    }
  } else if ((m = DROP_TABLE.exec(statement))) {
    let [, rest] = m;
    if (rest === undefined) return;
    for (let dropped = qualifiedName(rest); dropped; dropped = qualifiedName(rest)) {
      if (dropped.schema === 'public') tables.delete(dropped.name);
      if (!dropped.rest.startsWith(',')) break;
      rest = dropped.rest.slice(1).trim();
    }
  } else if ((m = CREATE_POLICY.exec(statement)) || (m = DROP_POLICY.exec(statement))) {
    const [, policy, target] = m;
    const on = publicTable(target);
    const table = on && tables.get(on.name);
    if (policy === undefined || table === undefined) return;
    table.file = file;
    if (statement.startsWith('create')) {
      table.policies.set(unquote(policy), MEMBER_CHECK.test(statement));
    } else {
      table.policies.delete(unquote(policy));
    }
  } else if ((m = ALTER_POLICY.exec(statement))) {
    const [, policy, target] = m;
    const on = publicTable(target);
    const table = on && tables.get(on.name);
    if (policy === undefined || on === undefined || table === undefined) return;
    const name = unquote(policy);
    const member = table.policies.get(name);
    if (member === undefined) return;
    table.file = file;
    const [, newName] = /^rename\s+to\s+(\S+)$/.exec(on.rest) ?? [];
    if (newName !== undefined) {
      table.policies.set(unquote(newName), member);
      table.policies.delete(name);
    } else if (/\b(?:using|with\s+check)\s*\(/.test(on.rest)) {
      table.policies.set(name, MEMBER_CHECK.test(on.rest));
    }
  }
}

/** The statements of a migration, lowercased except inside "quoted identifiers", with comments
 * (nested block comments included), string literals and dollar-quoted bodies blanked so that a
 * function body or a comment never reads as DDL. With `keepStrings`, literals and bodies stay
 * as written: pgTAP tests pass their SQL as strings. */
export function statements(sql: string, { keepStrings = false } = {}): string[] {
  const out: string[] = [];
  let current = '';
  let i = 0;
  const end = () => {
    const statement = current.trim();
    if (statement) out.push(statement);
    current = '';
  };
  while (i < sql.length) {
    const rest = sql.slice(i);
    const dollar = /^\$([a-z_]\w*)?\$/i.exec(rest);
    if (rest.startsWith('--')) {
      const end = sql.indexOf('\n', i);
      i = end < 0 ? sql.length : end;
    } else if (rest.startsWith('/*')) {
      let depth = 0;
      do {
        if (sql.startsWith('/*', i)) (depth++, i += 2);
        else if (sql.startsWith('*/', i)) (depth--, i += 2);
        else i++;
      } while (depth > 0 && i < sql.length);
      current += ' ';
    } else if (sql[i] === "'") {
      // In E'...' a backslash escapes the next character.
      const escapes = /(?:^|[^\w$])e$/i.test(sql.slice(Math.max(0, i - 2), i));
      let j = i + 1;
      while (j < sql.length) {
        if (escapes && sql[j] === '\\') j += 2;
        else if (sql[j] === "'" && sql[j + 1] === "'") j += 2;
        else if (sql[j] === "'") break;
        else j++;
      }
      current += keepStrings ? sql.slice(i, j + 1) : "''";
      i = j + 1;
    } else if (sql[i] === '"') {
      let j = i + 1;
      while (j < sql.length && !(sql[j] === '"' && sql[j + 1] !== '"')) j += sql[j] === '"' ? 2 : 1;
      current += sql.slice(i, j + 1);
      i = j + 1;
    } else if (dollar) {
      const close = sql.indexOf(dollar[0], i + dollar[0].length);
      const stop = close < 0 ? sql.length : close + dollar[0].length;
      current += keepStrings ? sql.slice(i, stop) : '$$';
      i = stop;
    } else if (sql[i] === ';') {
      end();
      i++;
    } else if (/\s/.test(sql.charAt(i))) {
      if (!current.endsWith(' ')) current += ' ';
      i++;
    } else {
      current += sql.charAt(i).toLowerCase();
      i++;
    }
  }
  end();
  return out;
}

/** squawk's rules that protect clients already in people's hands: TestFlight and Play builds lag
 * main, so a migration must keep the API an older app uses working. Lock and timeout rules stay
 * off: the database is tiny and migrations run in seconds. */
export const COMPAT_RULES: ReadonlySet<string> = new Set([
  'adding-not-nullable-field',
  'adding-required-field',
  'ban-drop-column',
  'ban-drop-database',
  'ban-drop-function',
  'ban-drop-not-null',
  'ban-drop-table',
  'ban-drop-view',
  'changing-column-type',
  'renaming-column',
  'renaming-table',
]);

type SquawkViolation = {
  file: string;
  line: number;
  level: string;
  message: string;
  'rule_name': string;
};

/** squawk's JSON report reduced to the compatibility rules, plus anything it could not parse,
 * which it could not check either. */
export function compat(report: SquawkViolation[]): Finding[] {
  return report
    .filter((v) => COMPAT_RULES.has(v.rule_name) || v.level === 'Error')
    .map((v) => ({
      file: `${v.file.replace(`${MIGRATIONS}/`, '')}:${v.line + 1}`,
      message:
        `${v.rule_name}: ${v.message} Old app builds still use the current schema: add the ` +
        `new shape next to the old one and remove the old one only once no released build reads ` +
        `it, or put "-- squawk-ignore ${v.rule_name} -- <reason>" on the line above.`,
    }));
}

/** An inline squawk exception says why, so a reviewer can judge it:
 * `-- squawk-ignore ban-drop-column -- the column moved to qty in 20261020...`. */
export function checkIgnores(tree: Migrations): Finding[] {
  const findings: Finding[] = [];
  for (const [file, sql] of tree) {
    sql.split('\n').forEach((line, i) => {
      if (
        /squawk-ignore/.test(line) &&
        !/squawk-ignore\s+[\w-]+(?:\s*,\s*[\w-]+)*\s+--\s+\S+(?:\s+\S+){2,}/.test(line)
      ) {
        findings.push({
          file: `${file}:${i + 1}`,
          message:
            'a squawk-ignore without its reason: write "-- squawk-ignore <rule> -- <why old ' +
            'app builds are not affected>"',
        });
      }
    });
  }
  return findings;
}

const MEMBERSHIP_READ = /\bfrom\s+(?:public\.)?household_members\b/gi;
const MEMBERSHIP_IGNORE = /schema-ignore\s+membership-read\s+--\s+\S+(?:\s+\S+){2,}/;

/** Since job 169b a user is in several households: a read of household_members by user that
 * names neither a household nor `is_default` gets an arbitrary row, or "more than one row" in a
 * scalar subquery or `select into`. Only new migrations: older ones are superseded, not edited. */
export function checkMembershipReads(base: Migrations, tree: Migrations): Finding[] {
  const findings: Finding[] = [];
  for (const [file, sql] of tree) {
    if (base.has(file)) continue;
    const lines = sql.split('\n');
    for (const match of sql.matchAll(MEMBERSHIP_READ)) {
      const end = sql.indexOf(';', match.index);
      const read = sql.slice(match.index, end === -1 ? undefined : end).split(/\$\$/)[0] ?? '';
      if (
        !/\buser_id\s*=/i.test(read) || /\bhousehold_id\b|\bis_default\b|\border\s+by\b/i.test(read)
      ) {
        continue;
      }
      const select = sql.slice(sql.toLowerCase().lastIndexOf('select', match.index), match.index);
      // An existence test or a count asks about every membership on purpose.
      if (/^select\s*(?:1\s*)?$|\bcount\s*\(/i.test(select.trim())) continue;
      const line = sql.slice(0, match.index).split('\n').length;
      if (MEMBERSHIP_IGNORE.test(lines[line - 2] ?? '')) continue;
      findings.push({
        file: `${file}:${line}`,
        message: 'reads household_members by user without naming a household: a user can be in ' +
          'several, so filter on household_id (the one the caller acts in) or is_default ' +
          '(public.default_household_of), or write "-- schema-ignore membership-read -- <why>" ' +
          'on the line above',
      });
    }
  }
  return findings;
}

async function run(
  cmd: string,
  args: string[],
): Promise<{ ok: boolean; out: string; err: string }> {
  const { success, stdout, stderr } = await new Deno.Command(cmd, { args }).output();
  const text = new TextDecoder();
  return { ok: success, out: text.decode(stdout), err: text.decode(stderr) };
}

async function readDir(dir: string, pattern: RegExp): Promise<Map<string, string>> {
  const files = new Map<string, string>();
  for await (const e of Deno.readDir(dir)) {
    if (e.isFile && pattern.test(e.name)) {
      files.set(e.name, await Deno.readTextFile(`${dir}/${e.name}`));
    }
  }
  return files;
}

async function baseMigrations(ref: string): Promise<Map<string, string>> {
  const listing = await run('git', ['ls-tree', '--name-only', ref, `${MIGRATIONS}/`]);
  if (!listing.ok) {
    throw new Error(
      `cannot read ${ref} (${listing.err.trim()}): fetch it first (git fetch origin main)`,
    );
  }
  const base = new Map<string, string>();
  for (const path of listing.out.split('\n').filter((p) => p.endsWith('.sql'))) {
    const show = await run('git', ['show', `${ref}:${path}`]);
    if (!show.ok) throw new Error(`git show ${ref}:${path}: ${show.err}`);
    base.set(path.slice(MIGRATIONS.length + 1), show.out);
  }
  return base;
}

if (import.meta.main) {
  const ref = Deno.args[0] ?? 'origin/main';
  const base = await baseMigrations(ref);
  const tree = await readDir(MIGRATIONS, /\.sql$/);
  const findings = [
    ...checkHistory(base, tree),
    ...checkTables(tree, await readDir(TESTS, /\.test\.sql$/)),
    ...checkIgnores(tree),
    ...checkMembershipReads(base, tree),
  ];
  const added = [...tree.keys()].filter((f) => !base.has(f)).sort();
  if (added.length > 0) {
    // squawk exits 1 whenever it reports anything, so its report decides, not its status.
    const squawk = await run('squawk', [
      '--reporter',
      'json',
      ...added.map((f) => `${MIGRATIONS}/${f}`),
    ]);
    if (!squawk.out.trim().startsWith('[')) throw new Error(`squawk failed: ${squawk.err}`);
    findings.push(...compat(JSON.parse(squawk.out)));
  }
  for (const f of findings) console.error(`${MIGRATIONS}/${f.file}: ${f.message}`);
  if (findings.length > 0) Deno.exit(1);
  console.log(
    `schema check: ${tree.size} migrations, ${added.length} new since ${ref}, no findings`,
  );
}
