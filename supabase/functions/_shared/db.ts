// Direct Postgres access for edge functions. Requests run as the signed-in user (role
// authenticated, auth.uid() = the user), so RLS, triggers and classify_item behave exactly as
// they do for the app. Only credential lookups run with the connection's own privileges.
import postgres from 'postgres';

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

/** Makes the rest of transaction [tx] run as `userId` (role authenticated), under RLS. */
async function becomeUser(tx: Tx, userId: string): Promise<void> {
  const claims = JSON.stringify({ sub: userId, role: 'authenticated' });
  await tx`select set_config('role', 'authenticated', true),
                  set_config('request.jwt.claims', ${claims}, true)`;
}

/** Runs `work` in one transaction as `userId`, under RLS. */
export async function asUser<T>(userId: string, work: (tx: Tx) => Promise<T>): Promise<T> {
  const result = await db().begin(async (tx) => {
    await becomeUser(tx, userId);
    return await work(tx);
  });
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
export async function resolveAccessToken(
  tokenHash: string,
): Promise<{ userId: string; householdId: string; kind: 'pat' | 'siri' } | null> {
  const sql = db();
  const [row] = await sql<{ user_id: string; household_id: string; kind: 'pat' | 'siri' }[]>`
    select user_id, household_id, kind from public.authenticate_access_token(${tokenHash})`;
  return row ? { userId: row.user_id, householdId: row.household_id, kind: row.kind } : null;
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

/** Deletes the user for good; see public.delete_account. */
export async function deleteAccount(userId: string): Promise<HouseholdFate> {
  const rows = await db()<{ fate: HouseholdFate }[]>`
    select public.delete_account(${userId}::uuid) as fate`;
  return oneRow(rows, 'delete_account').fate;
}

/** One read of the shared seed dictionary: real Postgres activity that touches no user data. */
export async function databaseAnswers(): Promise<boolean> {
  const rows = await db()<{ ok: boolean }[]>`
    select exists (select from public.classifier_terms) as ok`;
  return oneRow(rows, 'databaseAnswers').ok;
}
