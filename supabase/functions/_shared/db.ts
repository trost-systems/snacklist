// Direct Postgres access for edge functions. Requests run as the signed-in user (role
// authenticated, auth.uid() = the user), so RLS, triggers and classify_item behave exactly as
// they do for the app. Only credential lookups run with the connection's own privileges.
import postgres from 'postgres';
import type { ResolvedToken, Scope } from './auth.ts';

export type Sql = postgres.Sql;
export type Tx = postgres.TransactionSql;

/** The row of a query that always returns exactly one, such as `select f() as x`. */
export function oneRow<T>(rows: readonly T[], query: string): T {
  const [row] = rows;
  if (row === undefined) throw new Error(`${query} returned no row`);
  return row;
}

let pool: Sql | undefined;

export function databaseUrl(): string {
  const configured = Deno.env.get('SUPABASE_DB_URL');
  if (configured === undefined) throw new Error('SUPABASE_DB_URL is not set');
  return configured;
}

function db(): Sql {
  pool ??= (() => {
    const url = new URL(databaseUrl());
    // The local stack names the database container supabase_db_<project>; Deno's resolvers
    // refuse underscores in hostnames. The container's network alias "db" points at the same
    // host. Hosted database URLs have no underscores.
    if (url.hostname.includes('_')) url.hostname = 'db';
    // prepare: false keeps it working behind Supavisor's transaction pooler.
    return postgres(url.toString(), { max: 3, prepare: false, idle_timeout: 30 });
  })();
  return pool;
}

/** The service connection, for credential and bookkeeping tables no client may touch. */
export const serviceDb = (): Sql => db();

/**
 * How long one statement of a request may run: the limit the role authenticated carries for the
 * app's own requests. A role switch inside a transaction does not apply it, so it is set here.
 */
export const STATEMENT_TIMEOUT = '8s';

/** A request that ran out of its time. Thrown before or between two steps: nothing is kept. */
export class OutOfTime extends Error {
  constructor() {
    super('the request ran out of its time');
  }
}

/** Whether [e] ended a request for its time: OutOfTime, or a statement at STATEMENT_TIMEOUT. */
export function ranOutOfTime(e: unknown): boolean {
  if (e instanceof OutOfTime) return true;
  const { name, code } = (e ?? {}) as { name?: unknown; code?: unknown };
  return name === 'PostgresError' && code === '57014';
}

/**
 * Whether [e] is a statement that did not get a row's lock (lock_not_available): the key, the
 * household or the account is being deleted or changed by another transaction right now.
 */
export function rowBusy(e: unknown): boolean {
  const { name, code } = (e ?? {}) as { name?: unknown; code?: unknown };
  return name === 'PostgresError' && code === '55P03';
}

/** How long a request waits for its caller's earlier requests in this worker. */
export const TURN_WAIT_MS = 5000;

const turns = new Map<string, Promise<void>>();

/**
 * Runs `work` once the earlier work of the same `caller` in this worker has ended, in the order
 * of arrival: however many requests one caller sends at once, they hold one of the pool's
 * connections, and the others stay free for everyone else. A request that waited `waitMs` gives
 * up as OutOfTime without running.
 */
export async function inTurn<T>(
  caller: string,
  work: () => Promise<T>,
  waitMs: number = TURN_WAIT_MS,
): Promise<T> {
  const earlier = turns.get(caller) ?? Promise.resolve();
  let ended = () => {};
  const mine = new Promise<void>((resolve) => {
    ended = resolve;
  });
  const queue = earlier.then(() => mine);
  turns.set(caller, queue);
  void queue.then(() => {
    if (turns.get(caller) === queue) turns.delete(caller);
  });
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<false>((resolve) => {
    timer = setTimeout(() => resolve(false), waitMs);
  });
  try {
    if (!await Promise.race([earlier.then(() => true), late])) throw new OutOfTime();
    return await work();
  } finally {
    clearTimeout(timer);
    ended();
  }
}

/** Makes the rest of transaction [tx] run as `userId` (role authenticated), under RLS. */
async function becomeUser(tx: Tx, userId: string): Promise<void> {
  const claims = JSON.stringify({ sub: userId, role: 'authenticated' });
  await tx`select set_config('role', 'authenticated', true),
                  set_config('request.jwt.claims', ${claims}, true),
                  set_config('statement_timeout', ${STATEMENT_TIMEOUT}, true)`;
}

/** Runs `work` in one transaction as `userId`, under RLS, in the user's turn (inTurn). */
export async function asUser<T>(userId: string, work: (tx: Tx) => Promise<T>): Promise<T> {
  const result = await inTurn(userId, () =>
    db().begin(async (tx) => {
      await becomeUser(tx, userId);
      return await work(tx);
    }));
  return result as T;
}

/**
 * Runs `work` as `userId` inside a transaction of the service connection, then switches back:
 * bookkeeping before and after it (the API's idempotency records) commits or rolls back with it.
 */
export async function asUserWithin<T>(
  tx: Tx,
  userId: string,
  work: (tx: Tx) => Promise<T>,
): Promise<T> {
  await becomeUser(tx, userId);
  const result = await work(tx);
  await tx`set local role none`;
  await tx`select set_config('request.jwt.claims', '', true)`;
  return result;
}

/** The user's default household (job 169b): OAuth connections and Alexa act there. */
export async function householdOf(userId: string): Promise<string | null> {
  const sql = db();
  const [row] = await sql<{ household_id: string }[]>`
    select household_id from public.household_members where user_id = ${userId} and is_default`;
  return row?.household_id ?? null;
}

/** Whether [userId] is a member of [householdId]; false for anything that is no household id. */
export async function isMember(userId: string, householdId: string): Promise<boolean> {
  const sql = db();
  const rows = await sql<{ member: boolean }[]>`
    select exists (
      select from public.household_members
      where user_id = ${userId}::uuid and household_id::text = ${householdId.toLowerCase()}
    ) as member`;
  return oneRow(rows, 'isMember').member;
}

/** Whether the Supabase session behind a JWT still exists for this user and OAuth client. */
export async function sessionActive(
  session: { id: string; userId: string; clientId: string | null },
): Promise<boolean> {
  const sql = db();
  const rows = await sql<{ active: boolean }[]>`
    select exists (
      select from auth.sessions s
      where s.id = ${session.id}::uuid and s.user_id = ${session.userId}::uuid
        and s.oauth_client_id::text is not distinct from ${session.clientId}
        and (s.not_after is null or s.not_after > now())
    ) as active`;
  return oneRow(rows, 'sessionActive').active;
}

/** A PAT or Siri credential by its hash; nothing when unknown, revoked or no longer valid. */
export async function resolveAccessToken(tokenHash: string): Promise<ResolvedToken | null> {
  const [row] = await db()<
    {
      user_id: string;
      household_id: string;
      kind: 'pat' | 'api' | 'siri';
      scopes: string[] | null;
    }[]
  >`select user_id, household_id, kind, scopes from public.authenticate_key(${tokenHash})`;
  if (!row) return null;
  const owner = { userId: row.user_id, householdId: row.household_id };
  if (row.kind === 'siri') return { ...owner, kind: 'siri' };
  // An MCP token and an API key are one personal key (job 397); the kind stays for history.
  const scopes = (row.scopes ?? []).filter((s): s is Scope => s === 'read' || s === 'write');
  return { ...owner, kind: 'pat', scopes };
}

export async function userExists(userId: string): Promise<boolean> {
  const rows = await db()<{ exists: boolean }[]>`
    select exists (select from auth.users where id = ${userId}::uuid) as exists`;
  return oneRow(rows, 'userExists').exists;
}

/** The user's Sign in with Apple subject (identities.provider_id), if they linked Apple. */
export async function appleSubject(userId: string): Promise<string | null> {
  const [row] = await db()<{ provider_id: string }[]>`
    select provider_id from auth.identities where user_id = ${userId}::uuid and provider = 'apple'`;
  return row?.provider_id ?? null;
}

export type HouseholdFate = 'kept' | 'deleted' | 'none';

/** Deletes the user for good, in the user's turn (inTurn); see public.delete_account. */
export async function deleteAccount(userId: string): Promise<HouseholdFate> {
  const rows = await inTurn(userId, () =>
    db()<{ fate: HouseholdFate }[]>`
      select public.delete_account(${userId}::uuid) as fate`);
  return oneRow(rows, 'delete_account').fate;
}

/** One read of the shared seed dictionary: real Postgres activity that touches no user data. */
export async function databaseAnswers(): Promise<boolean> {
  const rows = await db()<{ ok: boolean }[]>`
    select exists (select from public.classifier_terms) as ok`;
  return oneRow(rows, 'databaseAnswers').ok;
}
