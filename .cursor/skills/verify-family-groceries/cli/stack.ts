/** The local Supabase stack: generated workdir, status, SQL, auth and the seed. */

import { type Ctx, FgError, type JsonObject, type Result, type RunResult, type Shell } from './core.ts';
import { HOUSEHOLD, type Instance, USERS } from './instance.ts';

/** The repo's config.toml with this instance's port block and project id; URLs (e.g. the test OIDC issuer) stay as they are. */
export function rewriteConfig(toml: string, prefix: string, projectId: string): string {
  return toml
    .replace(/^(\s*\w*port\s*=\s*)543(\d\d)\b/gm, `$1${prefix}$2`)
    .replace(/^project_id = .*$/m, `project_id = "${projectId}"`);
}

/**
 * Supabase runs from a generated workdir so parallel agents never edit the
 * tracked config.toml: only the ports and project id differ; migrations,
 * functions and tests are symlinks into the checkout, the email templates a copy.
 */
export async function writeWorkdir(ctx: Ctx, inst: Instance): Promise<void> {
  const target = `${inst.workdir}/supabase`;
  const config = await ctx.sh.readText(`${inst.repo}/supabase/config.toml`);
  await ctx.act(`write ${target}/config.toml (ports ${inst.prefix}xx, project ${inst.projectId})`, async () => {
    await ctx.sh.mkdir(target);
    await ctx.sh.writeText(`${target}/config.toml`, rewriteConfig(config, inst.prefix, inst.projectId));
    // On the checkout's own stack (FG_STACK_WORKDIR = the repo) the dirs are already there; a link
    // would land inside them (supabase/functions/functions).
    if (inst.workdir === inst.repo) return;
    for (const dir of ['migrations', 'functions', 'tests']) {
      await mustRun(ctx.sh, ['ln', '-sfn', `${inst.repo}/supabase/${dir}`, `${target}/${dir}`]);
    }
    // supabase start refuses an auth email template that resolves outside the workdir.
    await mustRun(ctx.sh, ['rm', '-rf', `${target}/templates`]);
    await mustRun(ctx.sh, ['cp', '-r', `${inst.repo}/supabase/templates`, `${target}/templates`]);
    const seed = `${inst.repo}/supabase/seed.sql`;
    if (await ctx.sh.exists(seed)) await mustRun(ctx.sh, ['ln', '-sfn', seed, `${target}/seed.sql`]);
  });
}

/** Edge Functions in the checkout: every directory under supabase/functions except _shared. */
export async function functionNames(sh: Shell, inst: Instance): Promise<string[]> {
  const res = await sh.run([
    'find',
    `${inst.repo}/supabase/functions`,
    '-mindepth',
    '1',
    '-maxdepth',
    '1',
    '-type',
    'd',
    '-printf',
    '%f\n',
  ]);
  return res.stdout.split('\n').filter((n) => n && !n.startsWith('_') && !n.startsWith('.')).sort();
}

/**
 * What a running stack depends on but does not reload: the config and the set
 * of functions. A stack started before either changed serves stale settings
 * (for example "Function not found" for a new function).
 */
export async function stackSignature(sh: Shell, inst: Instance): Promise<string> {
  const config = rewriteConfig(await sh.readText(`${inst.repo}/supabase/config.toml`), inst.prefix, inst.projectId);
  const text = `${config}\0${(await functionNames(sh, inst)).join(',')}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function mustRun(
  sh: Shell,
  cmd: string[],
  opts: { cwd?: string; stdin?: string; timeoutMs?: number; signal?: AbortSignal | undefined } = {},
): Promise<RunResult> {
  const res = await sh.run(cmd, opts);
  if (res.code !== 0) {
    throw new FgError(
      'command_failed',
      `\`${cmd.join(' ')}\` exited ${res.code}: ${(res.stderr || res.stdout).trim().slice(-800)}`,
      'Read the message above; `fg doctor` shows which part of the instance is unhealthy.',
    );
  }
  return res;
}

export interface StackEnv {
  apiUrl: string;
  publishableKey: string;
  secretKey: string;
  mailUrl: string;
}

export async function stackEnv(sh: Shell, inst: Instance): Promise<StackEnv> {
  const res = await sh.run(['supabase', 'status', '-o', 'json', '--workdir', inst.workdir]);
  const start = res.stdout.indexOf('{');
  if (res.code !== 0 || start < 0) {
    throw new FgError(
      'stack_down',
      `The local Supabase stack ${inst.projectId} is not running.`,
      'Run `fg up` (or `fg up --only stack`) to start it.',
    );
  }
  const env = JSON.parse(res.stdout.slice(start));
  return {
    apiUrl: env.API_URL,
    publishableKey: env.PUBLISHABLE_KEY,
    secretKey: env.SECRET_KEY,
    mailUrl: env.MAILPIT_URL ?? env.INBUCKET_URL,
  };
}

/** Runs SQL in the stack's database container; read-only unless write is set. */
export async function sql(
  sh: Shell,
  inst: Instance,
  text: string,
  opts: { write?: boolean; asUser?: string | undefined } = {},
): Promise<string> {
  const prelude: string[] = [];
  if (!opts.write) prelude.push('set default_transaction_read_only = on;');
  let body = text.trim().replace(/;\s*$/, '');
  if (opts.asUser) {
    const claims = JSON.stringify({ sub: opts.asUser, role: 'authenticated' }).replaceAll("'", "''");
    body = `begin;\nset local role authenticated;\nset local request.jwt.claims = '${claims}';\n${body};\ncommit`;
  }
  const res = await sh.run(
    ['docker', 'exec', '-i', inst.dbContainer, 'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'],
    { stdin: `${prelude.join('\n')}\n${body};\n` },
  );
  if (res.code !== 0) {
    const message = res.stderr.trim() || res.stdout.trim();
    if (/No such container|is not running/.test(message)) {
      throw new FgError('stack_down', `Database container ${inst.dbContainer} is not running.`, 'Run `fg up --only stack`.');
    }
    const readOnly = /read-only transaction/.test(message);
    throw new FgError(
      readOnly ? 'read_only' : 'sql_failed',
      message,
      readOnly
        ? 'This statement writes. Rerun with --write (and --dry-run first to see it).'
        : 'Fix the SQL; `fg db query "select ..."` takes one statement.',
    );
  }
  return res.stdout;
}

/** One SELECT (or WITH) as a JSON array of row objects. */
export async function sqlRows(sh: Shell, inst: Instance, query: string, asUser?: string): Promise<JsonObject[]> {
  const inner = query.trim().replace(/;\s*$/, '');
  const out = await sql(sh, inst, `select coalesce(jsonb_agg(q), '[]'::jsonb) from (${inner}) q`, { asUser });
  const line = out.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('[')).pop();
  return JSON.parse(line ?? '[]');
}

export interface Session {
  accessToken: string;
  userId: string;
}

export async function signIn(sh: Shell, env: StackEnv, user: { email: string; password: string }): Promise<Session> {
  const { email, password } = user;
  const res = await sh.fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json();
  if (!res.ok) {
    throw new FgError(
      'login_failed',
      `${email} cannot sign in: ${body.msg ?? body.error_description ?? res.status}.`,
      email.endsWith('@fg.test')
        ? 'Run `fg seed` to recreate the test users (it resets the database).'
        : 'The fixture run may be torn down: `fg runs`.',
    );
  }
  return { accessToken: body.access_token, userId: body.user.id };
}

export async function restAs(sh: Shell, env: StackEnv, session: Session, path: string, init: RequestInit = {}): Promise<unknown> {
  const res = await sh.fetch(`${env.apiUrl}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.publishableKey,
      authorization: `Bearer ${session.accessToken}`,
      'content-type': 'application/json',
      prefer: 'return=representation',
      ...(init.headers as Record<string, string> | undefined),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new FgError(
      'rest_failed',
      `${init.method ?? 'GET'} /rest/v1/${path}: ${res.status} ${text}`,
      'Check `fg doctor`; the user may not be in a household (`fg seed`).',
    );
  }
  return text ? JSON.parse(text) : null;
}

/** Recreates the database from migrations, then the two users in one household through the real RPCs. */
export async function seed(ctx: Ctx, inst: Instance): Promise<Result> {
  await ctx.act(
    `supabase db reset --workdir ${inst.workdir} (drops all data in ${inst.projectId})`,
    () => mustRun(ctx.sh, ['supabase', 'db', 'reset', '--workdir', inst.workdir], { timeoutMs: 300_000 }),
  );
  if (ctx.dryRun) {
    ctx.actions.push(
      `create users ${USERS.peter.email} and ${USERS.lea.email}; peter creates "${HOUSEHOLD}", lea joins it with an invite code`,
    );
    return { users: Object.fromEntries(Object.entries(USERS).map(([k, u]) => [k, u.email])) };
  }
  const env = await stackEnv(ctx.sh, inst);
  await untilReady(ctx.sh, env);
  for (const user of Object.values(USERS)) {
    const res = await ctx.sh.fetch(`${env.apiUrl}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { apikey: env.secretKey, authorization: `Bearer ${env.secretKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ email: user.email, password: user.password, email_confirm: true, user_metadata: { full_name: user.name } }),
    });
    if (!res.ok) {
      throw new FgError('seed_failed', `Creating ${user.email}: ${res.status} ${await res.text()}`, 'Check `fg logs --service auth`.');
    }
    await res.body?.cancel();
  }
  const peter = await signIn(ctx.sh, env, USERS.peter);
  const lea = await signIn(ctx.sh, env, USERS.lea);
  const household = (await restAs(ctx.sh, env, peter, 'rpc/create_household', {
    method: 'POST',
    body: JSON.stringify({ p_name: HOUSEHOLD }),
  })) as JsonObject;
  const invite = (await restAs(ctx.sh, env, peter, 'rpc/create_invite', {
    method: 'POST',
    body: JSON.stringify({ p_household: household.id }),
  })) as JsonObject;
  await restAs(ctx.sh, env, lea, 'rpc/join_household', { method: 'POST', body: JSON.stringify({ p_code: invite.code }) });
  ctx.actions.push(`created ${USERS.peter.email} and ${USERS.lea.email} in household "${HOUSEHOLD}"`);
  return {
    household: { id: household.id, name: HOUSEHOLD },
    users: {
      peter: { email: USERS.peter.email, password: USERS.peter.password, id: peter.userId },
      lea: { email: USERS.lea.email, password: USERS.lea.password, id: lea.userId },
    },
  };
}

/** After a reset, PostgREST reconnects to the new database for a few seconds and answers 503 meanwhile. */
async function untilReady(sh: Shell, env: StackEnv): Promise<void> {
  const ok = async (url: string) => {
    const res = await sh.fetch(url, { headers: { apikey: env.publishableKey } }).catch(() => null);
    await res?.body?.cancel();
    return res?.ok ?? false;
  };
  for (let i = 0; i < 120; i++) {
    if ((await ok(`${env.apiUrl}/rest/v1/`)) && (await ok(`${env.apiUrl}/auth/v1/health`))) return;
    await sh.sleep(500);
  }
  throw new FgError(
    'stack_not_ready',
    'REST or auth did not answer within 60 s after the database reset.',
    '`fg logs --service rest`, then `fg down && fg up`.',
  );
}

export async function householdOf(sh: Shell, inst: Instance, email: string): Promise<string | null> {
  const rows = await sqlRows(
    sh,
    inst,
    `select m.household_id from public.household_members m join auth.users u on u.id = m.user_id where u.email = '${
      email.replaceAll("'", "''")
    }'`,
  );
  return (rows[0]?.household_id as string | undefined) ?? null;
}
