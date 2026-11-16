// Job 253: nobody outside a household makes its members wait. Two households are filled until
// each of their tables holds a row, and a side connection holds every row that names an id of the
// first one and every advisory lock on them. Then the owner of the second one, and a signed-out
// caller, call every function the API roles may execute and write to every table they may write,
// with the ids of both households, the words the functions take and the first one's invite code
// as arguments. A call that asks for one of the held locks ends in lock_not_available (55P03)
// after LOCK_WAIT, and only joining with the invite code may (WITH_CODE): what refuses someone
// outside a household comes before the first lock. Each call runs in a subtransaction that is
// rolled back, all of them in one statement on the server.
//
// A new function is swept without a line here. The test names what it cannot see: a table that
// references households without a row of this one (its row goes into fill), a table the API
// roles may write without a held row, a table without a held row that NO_ROW does not list, an
// advisory lock that is not on a name and an id, a call that is none, and a function every call
// of which ends on its arguments. Runs like add_paths_integration_test.ts (FG_DB_TEST=1,
// SUPABASE_DB_URL).
import { assert, assertEquals, assertExists } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

/** How long a call waits for a held lock before it ends as one that asked for it. */
const LOCK_WAIT = '100ms';

const ROLES = ['authenticated', 'anon'] as const;
type Role = typeof ROLES[number];

/**
 * What the calls name: the household, its people (its owner, a member and a guest who asked to
 * join) and one row of each of its tables that has an id, by table.
 */
type Household = {
  id: string;
  owner: string;
  member: string;
  guest: string;
  rows: Record<string, string>;
  /** The code of its open invite. */
  code: string;
};
/** The caller: their own household is filled like the other one, and none of it is held. */
type Outsider = { household: string; user: string; rows: Record<string, string> };

/** An id no row has. */
const UNKNOWN = '00000000-0000-4000-8000-000000000253';

type Fn = { name: string; types: string[]; names: string[]; roles: Role[] };
type Column = {
  name: string;
  type: string;
  required: boolean;
  references: string | null;
  writable: Role[];
};
type Table = {
  name: string;
  columns: Column[];
  inserts: Role[];
  updates: Role[];
  deletes: Role[];
};

const uuid = (id: string) => `'${id}'::uuid`;
const codeOf = (household: Household) => `'${household.code}'::text`;

/**
 * The calls that may wait: whoever holds a household's invite code writes to it. Joining takes
 * the household's row, and the preview counts itself on the invite. Without the code nobody waits.
 */
const WITH_CODE: Record<Role, string[]> = {
  authenticated: ['public.accept_invite', 'public.join_household', 'public.preview_invite_public'],
  anon: ['public.preview_invite_public'],
};

/**
 * Tables no row of which the side connection holds: the ones without an owner (switches, the
 * classifier's words, rate windows by a hash) and the ones keyed by a user or a key that only the
 * server's roles write, where the fixture has no row. A function that locks one of them by an id
 * the caller passes is not seen here. A new table is held, or it is added with that in mind.
 */
const NO_ROW = [
  'alexa_links',
  'alexa_rate',
  'analytics_consents',
  'api_auth_failures',
  'api_idempotency',
  'api_token_buckets',
  'app_switches',
  'brands',
  'catalog_snapshots',
  'classifier_lexicon',
  'classifier_synonyms',
  'classifier_terms',
  'feedback_digest_state',
  'feedback_screenshot_removals',
  'invite_attempts',
  'invite_preview_rate',
  'invite_preview_salt',
  'oauth_app_devices',
  'oauth_cimd_clients',
  'oauth_cimd_rate',
  'purchase_rate',
  'purchase_tombstones',
  'purchases',
  'revenuecat_customers',
  'revenuecat_deletions',
  'revenuecat_events',
  'revenuecat_households',
  'user_entitlements',
  'waitlist',
  'waitlist_consent_proof',
  'waitlist_rate',
];

/** How a call ends when the sweep wrote something that is no call: a hole in the sweep. */
const NO_CALL = ['42883', '42725', '42601', '42P01', '42703', '42804'];

/**
 * The functions every call of which ends on its arguments (a data or constraint error), so the
 * sweep never gets to what they lock. This one only reads. Another one here means the sweep
 * lacks a word the function asks for: add it to the texts in values.
 */
const ENDS_ON_ARGUMENTS = ['public.assert_category_permutation'];

/** A finished trip as the app saves it, with one bought line. */
const session = (id: string) =>
  `jsonb_build_object('id', '${id}', 'started_at', '2026-11-14T09:00:00Z',
     'ended_at', '2026-11-14T09:20:00Z', 'active_seconds', 1200, 'end_reason', 'user',
     'source', 'manual', 'currency', 'EUR', 'shopped_on', '2026-11-14', 'pauses', '[]'::jsonb,
     'lines', jsonb_build_array(jsonb_build_object(
       'key', 'k', 'name', 'Brot', 'planned', false, 'bought', true)))`;

/** The values tried for an argument or column of [type], the first one its default. */
function values(type: string, household: Household, outsider: Outsider): string[] | undefined {
  const all = [
    household.id,
    household.owner,
    household.member,
    household.guest,
    ...Object.values(household.rows),
    outsider.household,
    outsider.user,
    ...Object.values(outsider.rows),
    UNKNOWN,
  ];
  const known: Record<string, string[]> = {
    uuid: all.map(uuid),
    'uuid[]': [`array[${all.map(uuid).join(', ')}]`],
    // A name, then the words the functions take (roles, kinds of invite, how to join, where to
    // place an item) and the household's invite code.
    text: [
      ...['Milch', 'admin', 'member', 'person', 'group', 'add', 'before', 'after'].map((t) =>
        `'${t}'::text`
      ),
      codeOf(household),
    ],
    'text[]': ["array['Milch']::text[]"],
    boolean: ['true', 'false'],
    integer: ['1'],
    'double precision': ['1::double precision'],
    numeric: ['1::numeric'],
    date: ["'2026-01-01'::date"],
    'timestamp with time zone': ["'2026-01-01T00:00:00Z'::timestamptz"],
    jsonb: [
      "'{}'::jsonb",
      "'[]'::jsonb",
      `'[{"name": "Brot"}]'::jsonb`,
      ...[household.rows['trip_sessions'], UNKNOWN].flatMap((id) =>
        id === undefined ? [] : [session(id)]
      ),
    ],
  };
  return known[type];
}

/** The household's id an argument is named after (p_list: its list, p_merge: its merge). */
function named(name: string | undefined, household: Household): string | undefined {
  const stem = name?.replace(/^p_/, '');
  if (stem === undefined) return undefined;
  if (stem === 'household') return uuid(household.id);
  if (stem === 'user') return uuid(household.owner);
  const plural = `${stem.replace(/y$/, 'ie')}s`;
  const tables = Object.keys(household.rows);
  const table = tables.find((t) => t === plural) ?? tables.find((t) => t.endsWith(`_${plural}`));
  const id = table === undefined ? undefined : household.rows[table];
  return id === undefined ? undefined : uuid(id);
}

/**
 * Calls of [fn]: every argument at its default, then every value of each argument, then every
 * pair of values of each two arguments, the others at their defaults. All of it twice: with the
 * household's rows as the defaults of the ids, and with an id no row has.
 */
function callsOf(fn: Fn, household: Household, outsider: Outsider): string[] {
  const tried = fn.types.map((type) => {
    const found = values(type, household, outsider);
    if (found === undefined) throw new Error(`${fn.name}: no values for an argument of ${type}`);
    return found;
  });
  const calls = new Set<string>();
  const add = (args: string[]) =>
    calls.add(`select count(*) from public.${fn.name}(${args.join(', ')})`);
  const starts = [
    tried.map((v, i) =>
      (fn.types[i] === 'uuid' ? named(fn.names[i], household) : undefined) ?? v[0] ?? 'null'
    ),
    tried.map((v, i) => fn.types[i] === 'uuid' ? uuid(UNKNOWN) : v[0] ?? 'null'),
  ];
  for (const defaults of starts) {
    add(defaults);
    tried.forEach((first, i) => {
      for (const a of first) {
        add(defaults.with(i, a));
        tried.slice(i + 1).forEach((second, offset) => {
          for (const b of second) add(defaults.with(i, a).with(i + 1 + offset, b));
        });
      }
    });
  }
  return [...calls];
}

/** The household's row of [table]; for households and users, the row of [who]. */
function rowOf(table: string | null, household: Household, who: Outsider): string | undefined {
  if (table === null) return undefined;
  if (table === 'households') return uuid(who.household);
  if (table === 'auth.users') return uuid(who.user);
  const id = household.rows[table];
  return id === undefined ? undefined : uuid(id);
}

/**
 * Writes to [table] as [role]: a new row in the household and one in the outsider's own, each
 * naming the household's rows where a column references one; the outsider's rows pointed at the
 * household's; every row the role sees rewritten, then deleted.
 */
function writesTo(table: Table, role: Role, household: Household, outsider: Outsider): string[] {
  const writes: string[] = [];
  const references = table.columns.filter((c) => c.references !== null);
  const inside = { household: household.id, user: household.owner, rows: {} };
  if (table.inserts.includes(role)) {
    for (const who of [inside, outsider]) {
      const set = table.columns.flatMap((c) => {
        const row = rowOf(c.references, household, who);
        if (row !== undefined) return [[c.name, row]];
        if (!c.required) return [];
        const value = c.type === 'uuid'
          ? 'gen_random_uuid()'
          : values(c.type, household, outsider)?.[0];
        return [[c.name, value ?? 'null']];
      });
      writes.push(
        set.length === 0
          ? `insert into public.${table.name} default values`
          : `insert into public.${table.name} (${set.map(([name]) => name).join(', ')})
             values (${set.map(([, value]) => value).join(', ')})`,
      );
    }
  }
  if (table.updates.includes(role)) {
    for (const c of table.columns.filter((c) => c.writable.includes(role))) {
      writes.push(`update public.${table.name} set ${c.name} = ${c.name}`);
    }
    for (const c of references.filter((c) => c.writable.includes(role))) {
      const row = rowOf(c.references, household, inside);
      if (row !== undefined) writes.push(`update public.${table.name} set ${c.name} = ${row}`);
    }
  }
  if (table.deletes.includes(role)) writes.push(`delete from public.${table.name}`);
  return writes;
}

const functionsOf = (sql: postgres.Sql): Promise<Fn[]> =>
  sql<Fn[]>`
    select p.proname as name, coalesce(p.proargnames[1:p.pronargs], '{}') as names,
           array(select format_type(t, null) from unnest(p.proargtypes::oid[]) with ordinality a (t, n)
                 order by n) as types,
           array(select r from unnest(${[...ROLES]}::text[]) r
                 where has_function_privilege(r, p.oid, 'execute')) as roles
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and p.prorettype <> 'trigger'::regtype
    order by p.oid::regprocedure::text`;

const tablesOf = (sql: postgres.Sql): Promise<Table[]> =>
  sql<Table[]>`
    select c.relname as name,
           array(select r from unnest(${[...ROLES]}::text[]) r
                 where has_any_column_privilege(r, c.oid, 'insert')) as inserts,
           array(select r from unnest(${[...ROLES]}::text[]) r
                 where has_any_column_privilege(r, c.oid, 'update')) as updates,
           array(select r from unnest(${[...ROLES]}::text[]) r
                 where has_table_privilege(r, c.oid, 'delete')) as deletes,
           (select jsonb_agg(jsonb_build_object(
              'name', a.attname,
              'type', format_type(a.atttypid, null),
              'required', a.attnotnull and not a.atthasdef and a.attidentity = '',
              'references', (
                select case when f.relnamespace = 'public'::regnamespace then f.relname
                            else f.oid::regclass::text end
                from pg_constraint k join pg_class f on f.oid = k.confrelid
                where k.conrelid = c.oid and k.contype = 'f' and k.conkey = array[a.attnum]
                order by f.relname limit 1),
              'writable', array(select r from unnest(${[...ROLES]}::text[]) r
                                where has_column_privilege(r, c.oid, a.attnum, 'update'))
            ) order by a.attnum)
            from pg_attribute a
            where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
              and a.attgenerated = '') as columns
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
    order by c.relname`;

/**
 * One row of each table that references households, by table: its id where the table's key is
 * one uuid, else null. Such a table without a row of the household is a failure: the sweep
 * would not know its rows.
 */
async function rowsOf(sql: postgres.Sql, household: string): Promise<Record<string, string>> {
  const tables = await sql<{ name: string; column: string; key: string | null }[]>`
    select c.relname as name, a.attname as column,
           (select pa.attname from pg_constraint pk
            join pg_attribute pa on pa.attrelid = pk.conrelid and pa.attnum = pk.conkey[1]
            where pk.conrelid = c.oid and pk.contype = 'p' and cardinality(pk.conkey) = 1
              and pa.atttypid = 'uuid'::regtype) as key
    from pg_constraint k
    join pg_class c on c.oid = k.conrelid
    join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
    where k.contype = 'f' and cardinality(k.conkey) = 1
      and c.relnamespace = 'public'::regnamespace
      and k.confrelid = 'public.households'::regclass
    order by c.relname`;
  const rows: Record<string, string> = {};
  const empty: string[] = [];
  for (const { name, column, key } of tables) {
    const [row] = await sql.unsafe<{ id: string | null }[]>(
      `select ${key ?? 'null'}::text as id from public.${name} where ${column} = $1 limit 1`,
      [household],
    );
    if (row === undefined) empty.push(name);
    else if (row.id !== null) rows[name] = row.id;
  }
  assertEquals(empty, [], 'tables that reference households, without a row of this one');
  return rows;
}

/**
 * Locks every row that names one of the household's ids in a uuid column, the rows of its people,
 * and every advisory lock the functions take, on a name and one of the ids or the invite code
 * ('items:' || household). A lock written another way fails here, and so does a table the API
 * roles may write that holds no row to lock: the sweep would not see who waits for it.
 */
async function holdAll(
  tx: postgres.TransactionSql,
  household: Household,
  tables: Table[],
): Promise<void> {
  const ids = [
    household.id,
    household.owner,
    household.member,
    household.guest,
    ...Object.values(household.rows),
  ];
  const columns = await tx<{ at: string; column: string }[]>`
    select case when c.relnamespace = 'public'::regnamespace then c.relname
                else c.oid::regclass::text end as at,
           a.attname as column
    from pg_attribute a join pg_class c on c.oid = a.attrelid
    where c.relkind = 'r' and a.atttypid = 'uuid'::regtype and a.attnum > 0 and not a.attisdropped
      and (c.relnamespace = 'public'::regnamespace
           or (c.oid = 'auth.users'::regclass and a.attname = 'id'))`;
  const held = new Set<string>();
  for (const { at, column } of columns) {
    const rows = await tx.unsafe(
      `select from ${at.includes('.') ? at : `public.${at}`}
       where ${column} = any($1::uuid[]) for update`,
      [ids],
    );
    if (rows.length > 0) held.add(at);
  }
  const all = await tx<{ name: string }[]>`
    select c.relname as name from pg_class c
    where c.relkind = 'r' and c.relnamespace = 'public'::regnamespace order by 1`;
  assertEquals(
    all.map((t) => t.name).filter((name) => !held.has(name)),
    NO_ROW,
    'tables without a held row',
  );
  const written = tables.filter((t) => t.inserts.length + t.updates.length + t.deletes.length > 0);
  assertEquals(
    written.map((t) => t.name).filter((name) => !held.has(name)),
    [],
    'tables the API roles may write, without a held row',
  );

  // The whole call: hashtext('name:' || id::text), or hashtextextended of the same with seed 0.
  const key = "'([a-z_]+:)'\\s*\\|\\|\\s*[a-z_.()]+::text\\s*";
  const site =
    `pg_advisory\\w*\\(\\s*hashtext(?:\\(\\s*${key}|extended\\(\\s*${key},\\s*0\\s*)\\)\\s*\\)`;
  const [sites] = await tx<{ all: number; known: number }[]>`
    select coalesce(sum(regexp_count(p.prosrc, 'pg_advisory')), 0)::int as all,
           coalesce(sum(regexp_count(p.prosrc, ${site})), 0)::int as known
    from pg_proc p where p.pronamespace = 'public'::regnamespace`;
  assertEquals(sites?.all, sites?.known, 'advisory locks that are not on a name and an id');
  const families = await tx<{ family: string }[]>`
    select distinct coalesce(m[1], m[2]) as family
    from pg_proc p, regexp_matches(p.prosrc, ${site}, 'g') m
    where p.pronamespace = 'public'::regnamespace`;
  const names = families.map((f) => f.family);
  for (const expected of ['items:', 'lists:', 'household_members:', 'purchase_user:']) {
    assert(names.includes(expected), `the advisory locks on ${expected} were not found: ${names}`);
  }
  await tx`
    select pg_advisory_xact_lock(hashtextextended(family || id, 0)),
           pg_advisory_xact_lock(hashtext(family || id))
    from unnest(${names}::text[]) family, unnest(${[...ids, household.code]}::text[]) id`;
}

type Swept = {
  /** The calls that asked for a held lock. */
  waited: string[];
  /** The ones that were no call at all, with how they ended. */
  noCall: string[];
  /** The statements every call of which ended on its arguments. */
  onArguments: string[];
};

/** How [calls] went, made as [role] (signed in as [user]). */
async function sweep(
  sql: postgres.Sql,
  role: Role,
  user: string | null,
  calls: string[],
): Promise<Swept> {
  const claims = user === null ? '' : JSON.stringify({ sub: user, role });
  const rows = await sql<{ state: string; call: string }[]>`
    select state, call
    from pg_temp.sweep(${role}, ${claims}, ${calls}::text[], ${NO_CALL}::text[])`;
  const ends = rows.filter((r) => r.state === 'ends').map((r) => r.call);
  return {
    waited: rows.filter((r) => r.state === '55P03').map((r) => r.call),
    noCall: rows.filter((r) => r.state !== '55P03' && r.state !== 'ends')
      .map((r) => `${r.state} ${r.call}`),
    onArguments: ends.filter((end) => /^[^|]+(\|2[23]...)+$/.test(end))
      .map((end) => end.replace(/\|.*$/, '')).sort(),
  };
}

/** [calls] by what they call, each with its count and its first call, for a failure to read. */
function byStatement(calls: string[]): Record<string, { calls: number; first: string }> {
  const found: Record<string, { calls: number; first: string }> = {};
  for (const call of calls) {
    const statement = call.replace(/\s+/g, ' ').replace('select count(*) from ', '')
      .replace(/ ?\(.*$/, '').replace(/ set .*$/, '');
    const entry = found[statement] ?? { calls: 0, first: call };
    found[statement] = { calls: entry.calls + 1, first: entry.first };
  }
  return found;
}

/** A household of [owner] with a list, stores, categories and the item Milch. */
const newHousehold = (owner: string): Promise<string> =>
  asUser(owner, async (tx) => {
    const [row] = await tx<{ id: string }[]>`
      select id from public.create_household(p_name => '253', p_default_stores => true)`;
    assertExists(row);
    await tx`insert into public.items (household_id, list_id, name)
             values (${row.id}, public.first_list(${row.id}), 'Milch')`;
    return row.id;
  });

/** Fills every table of [household]: what its [owner] did in the app, then what the server keeps. */
async function fill(
  sql: postgres.Sql,
  household: string,
  owner: string,
  member: string,
  guest: string,
): Promise<void> {
  await sql`insert into public.household_members (household_id, user_id, role)
            values (${household}, ${member}, 'member')`;
  await asUser(owner, async (tx) => {
    for (const name of ['Brot', 'Möhren', 'Karotten']) {
      await tx`insert into public.items (household_id, list_id, name)
               values (${household}, public.first_list(${household}), ${name})`;
    }
    await tx`
      update public.items
      set category_id = (select id from public.categories
                         where household_id = ${household} and seed_key = 'drinks'),
          store_id = public.add_store(${household}, 'Supermarkt'),
          brand = 'Hofbäckerei Kurz'
      where household_id = ${household} and name = 'Brot'`;
    // A store changed to none is recorded (item_store_cleared, job 272).
    await tx`insert into public.items (household_id, list_id, name, store_id)
             select ${household}, public.first_list(${household}), 'Salz', id
             from public.stores where household_id = ${household} and name = 'Supermarkt'`;
    await tx`update public.items set store_id = null
             where household_id = ${household} and name = 'Salz'`;
    await tx`
      select public.merge_items(gen_random_uuid(),
        (select id from public.items where household_id = ${household} and name = 'Möhren'),
        (select id from public.items where household_id = ${household} and name = 'Karotten'))`;
    await tx`select public.claim_item(
      (select id from public.items where household_id = ${household} and name = 'Milch'), null)`;
    await tx`select public.save_trip(${household}, gen_random_uuid(), null, current_date,
                                     '[{"name": "Brot"}]')`;
    await tx.unsafe(
      `select public.save_trip_session($1, ${session(crypto.randomUUID())}, false)`,
      [household],
    );
    await tx`select public.create_personal_access_token('test')`;
    await tx`select public.create_invite(${household}, 'person')`;
    await tx`insert into public.feedback
               (id, message, app_version, build, platform, os_version, locale, screen)
             values (gen_random_uuid(), 'Test', '0.1.0', '1', 'web', 'Chrome', 'de', 'list')`;
  });
  await sql`insert into public.join_requests (household_id, user_id) values (${household}, ${guest})`;
  await sql`insert into public.household_removals (household_id, user_id)
            values (${household}, ${guest})`;
  await sql`insert into public.household_departures (household_id, user_id, joined_at)
            values (${household}, ${guest}, now())`;
  await sql`insert into public.invite_uses (invite_id, household_id, user_id)
            select id, household_id, ${guest} from public.invites where household_id = ${household}`;
  await sql`insert into public.integration_blocks (household_id, integration, reported_at)
            values (${household}, 'siri', now())`;
  await sql`insert into public.api_household_days (household_id, day, requests)
            values (${household}, current_date, 3)`;
  await sql`insert into public.entitlements (household_id, kind, source, premium_source)
            values (${household}, 'premium', 'promotional', 'promotional')`;
  await sql`insert into public.purchase_claims (store, transaction_id, user_id, claimed_for)
            values ('apple', ${crypto.randomUUID()}, ${owner}, ${household})`;
}

async function withHousehold(
  work: (sql: postgres.Sql, household: Household, outsider: Outsider) => Promise<void>,
) {
  const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
  const owner = crypto.randomUUID();
  const member = crypto.randomUUID();
  const guest = crypto.randomUUID();
  const other = crypto.randomUUID();
  const otherMember = crypto.randomUUID();
  const otherGuest = crypto.randomUUID();
  const users = [owner, member, guest, other, otherMember, otherGuest];
  const log = console.log;
  console.log = () => {};
  try {
    for (const user of users) {
      await sql`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
    }
    const household = await newHousehold(owner);
    const away = await newHousehold(other);
    await fill(sql, household, owner, member, guest);
    await fill(sql, away, other, otherMember, otherGuest);
    const [invite] = await sql<{ code: string }[]>`
      select code from public.invites where household_id = ${household}`;
    assertExists(invite);
    // One row per call that waited (55P03) or was no call, then one per statement with the ways
    // its calls ended ('ends', 'public.put_item|23514|42501'); P0253 is a call that went through.
    await sql.unsafe(`
      create function pg_temp.sweep(p_role text, p_claims text, p_calls text[], p_no_call text[])
      returns table (state text, call text) language plpgsql as $$
      declare
        v_call text;
        v_statement text;
        v_ends jsonb := '{}';
      begin
        foreach v_call in array p_calls loop
          begin
            perform set_config('lock_timeout', '${LOCK_WAIT}', true);
            perform set_config('request.jwt.claims', p_claims, true);
            perform set_config('role', p_role, true);
            execute v_call;
            raise exception 'undone' using errcode = 'P0253';
          exception when others then
            if sqlstate = '55P03' or sqlstate = any(p_no_call) then
              return query select sqlstate, v_call;
            end if;
            v_statement := coalesce(
              substring(v_call from '^select count\\(\\*\\) from (public\\.\\w+)'),
              substring(v_call from '^(\\w+ (?:\\w+ )?public\\.\\w+)'));
            v_ends := v_ends || jsonb_build_object(
              v_statement, coalesce(v_ends -> v_statement, '{}') || jsonb_build_object(sqlstate, true));
          end;
        end loop;
        return query
          select 'ends', e.key || '|' || (select string_agg(k, '|' order by k) from jsonb_object_keys(e.value) k)
          from jsonb_each(v_ends) e;
      end $$`);
    await work(
      sql,
      {
        id: household,
        owner,
        member,
        guest,
        rows: await rowsOf(sql, household),
        code: invite.code,
      },
      { household: away, user: other, rows: await rowsOf(sql, away) },
    );
  } finally {
    console.log = log;
    for (const user of users) {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${user})`;
      await sql`delete from auth.users where id = ${user}`;
    }
    await sql.end();
  }
}

Deno.test({
  name: "no call from outside a household asks for a lock on what is the household's",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: () =>
    withHousehold(async (sql, household, outsider) => {
      const functions = await functionsOf(sql);
      const tables = await tablesOf(sql);
      const side = postgres(databaseUrl(), { max: 1, prepare: false });
      try {
        await side.begin(async (held) => {
          await holdAll(held, household, tables);

          const members = [
            `select public.set_member_role(${uuid(household.id)}, ${
              uuid(household.member)
            }, 'admin')`,
            `select public.lock_household_items(${uuid(household.id)})`,
            `update public.items set name = name`,
          ];
          assertEquals(
            (await sweep(sql, 'authenticated', household.owner, members)).waited,
            members,
            "the locks are held: the owner's own calls end as waiting for them",
          );

          for (const role of ROLES) {
            const calls = [
              ...functions.filter((f) => f.roles.includes(role))
                .flatMap((f) => callsOf(f, household, outsider)),
              ...tables.flatMap((t) => writesTo(t, role, household, outsider)),
            ];
            // Signed out, the grants leave one function and no table: a handful of calls.
            assert(calls.length > (role === 'anon' ? 0 : 1000), `${calls.length} calls as ${role}`);
            const user = role === 'anon' ? null : outsider.user;
            const { waited, noCall, onArguments } = await sweep(sql, role, user, calls);
            assertEquals(noCall, [], `what the sweep wrote as ${role} that is no call`);
            assertEquals(
              onArguments,
              role === 'anon' ? [] : ENDS_ON_ARGUMENTS,
              `as ${role}, the statements every call of which ended on its arguments`,
            );
            const invited = waited.filter((call) => call.includes(codeOf(household)));
            assertEquals(
              byStatement(waited.filter((call) => !invited.includes(call))),
              {},
              `calls as ${role} without the household's invite code`,
            );
            assertEquals(
              Object.keys(byStatement(invited)).sort(),
              WITH_CODE[role],
              `calls as ${role} with the household's invite code`,
            );
          }
        });
      } finally {
        await side.end();
      }
    }),
});
