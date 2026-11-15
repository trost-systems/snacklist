// Job 253: a function that decides before its first lock decides again under it. For each case a
// side connection holds the lock the call waits for. Once the call waits (pg_stat_activity shows
// its backend waiting for a lock, so no timing), the side connection takes away what the first
// check saw and commits. The call must then answer as if it had come after the change, and a
// refused call must leave the rows as they are. Where a function takes the user's memberships
// lock first, the side connection holds that one: the delete of a membership asks for it too.
// Runs like add_paths_integration_test.ts (FG_DB_TEST=1, SUPABASE_DB_URL).
import { assertEquals, assertExists } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

/** How long a call may take to reach its lock before the case fails as one that never waited. */
const REACH_MS = 5000;

type Fixture = {
  household: string;
  owner: string;
  member: string;
  /** Someone with the household's invite code who is no member. */
  guest: string;
  code: string;
  invite: string;
  milk: string;
  bread: string;
  cheese: string;
  merge: string;
  trip: string;
  session: string;
};

type Case = {
  name: string;
  caller: (f: Fixture) => string;
  call: (f: Fixture) => string;
  /** Rows the case starts from, beyond the fixture's. */
  given?: (f: Fixture) => string;
  /** What the side connection holds while the call starts. */
  hold: (f: Fixture) => string;
  /** What the side connection changes once the call waits. */
  change: (f: Fixture) => string;
  /** How the call ends: its error, or its answer. */
  ends: string;
  /** What is read afterwards, and what it shows. */
  probe: (f: Fixture) => string;
  shows: string;
};

const connect = () => postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });

/** A finished trip as the app saves it, with one bought line. */
const session = (id: string) =>
  `jsonb_build_object('id', '${id}', 'started_at', '2026-11-14T09:00:00Z',
     'ended_at', '2026-11-14T09:20:00Z', 'active_seconds', 1200, 'end_reason', 'user',
     'source', 'manual', 'currency', 'EUR', 'shopped_on', '2026-11-14', 'pauses', '[]'::jsonb,
     'lines', jsonb_build_array(jsonb_build_object(
       'key', 'k', 'name', 'Brot', 'planned', false, 'bought', true)))`;

/** What [call] answers as [user] (the column v of its first row), or the error it ends with. */
async function answerAs(sql: postgres.Sql, user: string, call: string): Promise<string> {
  try {
    const rows = await sql.begin(async (tx) => {
      await tx`select set_config('role', 'authenticated', true),
                      set_config('request.jwt.claims', ${
        JSON.stringify({ sub: user, role: 'authenticated' })
      }, true)`;
      return await tx.unsafe<{ v: string | null }[]>(call);
    });
    return String(rows[0]?.v ?? null);
  } catch (e) {
    if (!(e instanceof postgres.PostgresError)) throw e;
    return `${e.code} ${e.message}`;
  }
}

async function must(sql: postgres.Sql, user: string, call: string): Promise<void> {
  const answer = await answerAs(sql, user, call);
  if (/^[0-9A-Z]{5} /.test(answer)) throw new Error(`${call}: ${answer}`);
}

async function fixture(sql: postgres.Sql, users: string[], households: string[]): Promise<Fixture> {
  const owner = crypto.randomUUID();
  const member = crypto.randomUUID();
  const guest = crypto.randomUUID();
  users.push(owner, member, guest);
  for (const user of [owner, member, guest]) {
    await sql`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
  }
  const household = await answerAs(
    sql,
    owner,
    `select id as v from public.create_household(p_name => '253 under lock')`,
  );
  households.push(household);
  await sql`insert into public.household_members (household_id, user_id, role)
            values (${household}, ${member}, 'member')`;
  for (const name of ['Milch', 'Brot', 'Käse', 'Möhren', 'Karotten']) {
    await must(
      sql,
      owner,
      `insert into public.items (household_id, list_id, name)
       values ('${household}', public.first_list('${household}'), '${name}')`,
    );
  }
  const items = await sql<{ name: string; id: string }[]>`
    select name, id from public.items where household_id = ${household}`;
  const item = (name: string): string => {
    const found = items.find((i) => i.name === name);
    assertExists(found, name);
    return found.id;
  };
  const merge = crypto.randomUUID();
  const trip = crypto.randomUUID();
  const sessionId = crypto.randomUUID();
  for (
    const call of [
      `select public.merge_items('${merge}', '${item('Möhren')}', '${item('Karotten')}')`,
      `select public.save_trip('${household}', '${trip}', null, current_date, '[{"name": "Brot"}]')`,
      `select public.save_trip_session('${household}', ${session(sessionId)}, false)`,
      `select public.create_invite('${household}', 'group')`,
    ]
  ) {
    await must(sql, owner, call);
  }
  const [invite] = await sql<{ id: string; code: string }[]>`
    select id, code from public.invites where household_id = ${household}`;
  assertExists(invite);
  return {
    household,
    owner,
    member,
    guest,
    code: invite.code,
    invite: invite.id,
    milk: item('Milch'),
    bread: item('Brot'),
    cheese: item('Käse'),
    merge,
    trip,
    session: sessionId,
  };
}

const leaves = (who: 'owner' | 'member') => (f: Fixture) =>
  `delete from public.household_members
   where household_id = '${f.household}' and user_id = '${f[who]}'`;
const householdRow = (f: Fixture) =>
  `select from public.households where id = '${f.household}' for update`;
const memberships = (who: 'member' | 'guest') => (f: Fixture) =>
  `select public.lock_memberships('${f[who]}')`;
const row = (table: string, id: 'merge' | 'invite' | 'trip' | 'session') => (f: Fixture) =>
  `select from public.${table} where id = '${f[id]}' for update`;
const roleOfMember = (f: Fixture) =>
  `select coalesce((select role from public.household_members
                    where household_id = '${f.household}' and user_id = '${f.member}'), 'gone') as v`;
const count = (from: string) => `select count(*)::text as v from public.${from}`;
const joins = (f: Fixture) => `select public.accept_invite('${f.code}', 'add') ->> 'status' as v`;
/** The one with the invite code is in the household, as an admin. */
const guestIsAdmin = (f: Fixture) =>
  `insert into public.household_members (household_id, user_id, role)
   values ('${f.household}', '${f.guest}', 'admin')`;
/** The household asks before someone joins, and the guest has asked through the invite. */
const guestAsked = (f: Fixture) =>
  `with asks as (
     update public.households set join_approval = true where id = '${f.household}'
   )
   insert into public.join_requests (household_id, user_id, invite_id)
   values ('${f.household}', '${f.guest}', '${f.invite}')`;
const guestIn = (f: Fixture) =>
  `select (select count(*) from public.household_members
           where household_id = '${f.household}' and user_id = '${f.guest}') || ' memberships, ' ||
          (select count(*) from public.join_requests
           where household_id = '${f.household}' and user_id = '${f.guest}' and decision is null)
          || ' open requests' as v`;

const CASES: Case[] = [
  {
    name: 'set_member_role, the caller is no member any more',
    caller: (f) => f.owner,
    call: (f) => `select public.set_member_role('${f.household}', '${f.member}', 'admin')`,
    hold: householdRow,
    change: leaves('owner'),
    ends: '42501 not_member',
    probe: roleOfMember,
    shows: 'member',
  },
  {
    name: 'set_member_role, the caller is a plain member now',
    caller: (f) => f.owner,
    call: (f) => `select public.set_member_role('${f.household}', '${f.member}', 'admin')`,
    hold: householdRow,
    change: (f) =>
      `update public.household_members
       set role = case when user_id = '${f.owner}' then 'member' else 'owner' end
       where household_id = '${f.household}'`,
    ends: '42501 not_owner',
    probe: roleOfMember,
    shows: 'owner',
  },
  {
    name: 'set_member_role, the other one is no member any more',
    caller: (f) => f.owner,
    call: (f) => `select public.set_member_role('${f.household}', '${f.member}', 'admin')`,
    hold: householdRow,
    change: leaves('member'),
    ends: '42501 not_member',
    probe: roleOfMember,
    shows: 'gone',
  },
  {
    name: 'remove_member, the caller is no member any more',
    caller: (f) => f.owner,
    call: (f) => `select public.remove_member('${f.household}', '${f.member}')`,
    hold: householdRow,
    change: leaves('owner'),
    ends: '42501 not_member',
    probe: roleOfMember,
    shows: 'member',
  },
  {
    name: 'remove_member, the other one is no member any more',
    caller: (f) => f.owner,
    call: (f) => `select public.remove_member('${f.household}', '${f.member}')`,
    hold: memberships('member'),
    change: leaves('member'),
    ends: '42501 not_member',
    probe: (f) => count(`household_removals where household_id = '${f.household}'`),
    shows: '0',
  },
  {
    name: 'remove_member by an admin, the other one is an admin now',
    caller: (f) => f.guest,
    call: (f) => `select public.remove_member('${f.household}', '${f.member}')`,
    given: guestIsAdmin,
    hold: memberships('member'),
    change: (f) =>
      `update public.household_members set role = 'admin'
       where household_id = '${f.household}' and user_id = '${f.member}'`,
    ends: '42501 cannot_remove_admin',
    probe: roleOfMember,
    shows: 'admin',
  },
  {
    name: 'remove_member by an admin, the other one is the owner now',
    caller: (f) => f.guest,
    call: (f) => `select public.remove_member('${f.household}', '${f.member}')`,
    given: guestIsAdmin,
    hold: memberships('member'),
    // In short what the owner's leave does after making the member an admin: it hands over.
    change: (f) =>
      `update public.household_members
       set role = case when user_id = '${f.owner}' then 'member' else 'owner' end
       where household_id = '${f.household}' and user_id in ('${f.owner}', '${f.member}')`,
    ends: '42501 cannot_remove_owner',
    probe: roleOfMember,
    shows: 'owner',
  },
  {
    name: 'remove_member by an admin, the caller is a plain member now',
    caller: (f) => f.guest,
    call: (f) => `select public.remove_member('${f.household}', '${f.member}')`,
    given: guestIsAdmin,
    hold: memberships('member'),
    change: (f) =>
      `update public.household_members set role = 'member'
       where household_id = '${f.household}' and user_id = '${f.guest}'`,
    ends: '42501 not_admin',
    probe: roleOfMember,
    shows: 'member',
  },
  {
    name: 'leave_household, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.leave_household('${f.household}') as v`,
    hold: memberships('member'),
    change: leaves('member'),
    ends: '42501 not_member',
    probe: (f) => count(`households where id = '${f.household}'`),
    shows: '1',
  },
  {
    name: 'leave_household of the last one, someone joined meanwhile',
    caller: (f) => f.owner,
    call: (f) =>
      `select 'deleted: ' || (public.leave_household('${f.household}') ->> 'deleted') as v`,
    given: leaves('member'),
    // What a join holds until it commits.
    hold: (f) => `select from public.households where id = '${f.household}' for share`,
    change: (f) =>
      `insert into public.household_members (household_id, user_id, role)
       values ('${f.household}', '${f.guest}', 'member')`,
    ends: 'deleted: false',
    probe: (f) =>
      `select (select count(*) from public.households where id = '${f.household}')
              || ' households, ' ||
              (select count(*) from public.household_members
               where household_id = '${f.household}') || ' members' as v`,
    shows: '1 households, 1 members',
  },
  {
    name: 'claim_item, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select (public.claim_item('${f.milk}', null)).item_id as v`,
    hold: memberships('member'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => count(`item_claims where item_id = '${f.milk}'`),
    shows: '0',
  },
  {
    name: 'merge_items, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.merge_items(gen_random_uuid(), '${f.bread}', '${f.cheese}')`,
    hold: (f) => `select from public.items where id in ('${f.bread}', '${f.cheese}') for update`,
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => count(`items where id in ('${f.bread}', '${f.cheese}')`),
    shows: '2',
  },
  {
    name: 'unmerge_items, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.unmerge_items('${f.merge}')`,
    hold: row('item_merges', 'merge'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) =>
      `select (undone_at is not null)::text as v from public.item_merges where id = '${f.merge}'`,
    shows: 'false',
  },
  {
    // Nothing is left to undo, so no write of the call's own asks again: only its check does.
    name: 'unmerge_items of a merge undone meanwhile, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.unmerge_items('${f.merge}')`,
    hold: row('item_merges', 'merge'),
    change: (f) =>
      `with gone as (${leaves('member')(f)} returning 1)
       update public.item_merges set undone_at = now() where id = '${f.merge}'`,
    ends: '42501 not_a_member',
    probe: (f) => count(`household_members where user_id = '${f.member}'`),
    shows: '0',
  },
  {
    name: 'revoke_invite, the caller is no member any more',
    caller: (f) => f.owner,
    call: (f) => `select public.revoke_invite('${f.invite}')`,
    hold: row('invites', 'invite'),
    change: leaves('owner'),
    ends: '42501 not_a_member',
    probe: (f) =>
      `select (revoked_at is not null)::text as v from public.invites where id = '${f.invite}'`,
    shows: 'false',
  },
  {
    name: 'revoke_invite of a group invite, the caller is a plain member now',
    caller: (f) => f.owner,
    call: (f) => `select public.revoke_invite('${f.invite}')`,
    hold: row('invites', 'invite'),
    change: (f) =>
      `update public.household_members
       set role = case when user_id = '${f.owner}' then 'member' else 'owner' end
       where household_id = '${f.household}'`,
    ends: '42501 not_admin',
    probe: (f) =>
      `select (revoked_at is not null)::text as v from public.invites where id = '${f.invite}'`,
    shows: 'false',
  },
  {
    name: 'delete_trip, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.delete_trip('${f.trip}')`,
    hold: row('trips', 'trip'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => count(`trips where id = '${f.trip}'`),
    shows: '1',
  },
  {
    name: 'delete_trip_session, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.delete_trip_session('${f.session}')`,
    hold: row('trip_sessions', 'session'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => count(`trip_sessions where id = '${f.session}'`),
    shows: '1',
  },
  {
    name: 'mark_trip_line_planned, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.mark_trip_line_planned('${f.session}', 'k', true)`,
    hold: row('trip_sessions', 'session'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) =>
      `select lines -> 0 ->> 'marked_planned' as v
       from public.trip_sessions where id = '${f.session}'`,
    shows: 'false',
  },
  {
    name: 'save_trip, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) =>
      `select (public.save_trip('${f.household}', '${f.trip}', null, current_date,
                                '[{"name": "Wein"}]')).id as v`,
    hold: memberships('member'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => `select items -> 0 ->> 'name' as v from public.trips where id = '${f.trip}'`,
    shows: 'Brot',
  },
  {
    name: 'save_trip_session, the caller is no member any more',
    caller: (f) => f.member,
    call: (f) => `select public.save_trip_session('${f.household}', ${session(f.session)}, true)`,
    hold: memberships('member'),
    change: leaves('member'),
    ends: '42501 not_a_member',
    probe: (f) => count(`trips where session_id = '${f.session}'`),
    shows: '0',
  },
  {
    name: 'accept_invite, the household asks before someone joins now',
    caller: (f) => f.guest,
    call: joins,
    hold: householdRow,
    change: (f) => `update public.households set join_approval = true where id = '${f.household}'`,
    ends: 'requested',
    probe: guestIn,
    shows: '0 memberships, 1 open requests',
  },
  {
    name: 'accept_invite, the guest was declined meanwhile',
    caller: (f) => f.guest,
    call: joins,
    hold: householdRow,
    change: (f) =>
      `with asks as (
         update public.households set join_approval = true where id = '${f.household}'
       )
       insert into public.join_requests (household_id, user_id, decision, decided_at)
       values ('${f.household}', '${f.guest}', 'declined', now())`,
    ends: 'declined_recently',
    probe: guestIn,
    shows: '0 memberships, 0 open requests',
  },
  {
    name: 'accept_invite, the household is archived now',
    caller: (f) => f.guest,
    call: joins,
    hold: householdRow,
    change: (f) =>
      `update public.households set archived_at = now(), archived_by = '${f.owner}'
       where id = '${f.household}'`,
    ends: 'invalid_invite',
    probe: guestIn,
    shows: '0 memberships, 0 open requests',
  },
  {
    name: 'accept_invite, the guest became a member meanwhile',
    caller: (f) => f.guest,
    call: joins,
    hold: memberships('guest'),
    change: (f) =>
      `insert into public.household_members (household_id, user_id, role)
       values ('${f.household}', '${f.guest}', 'member')`,
    ends: 'member',
    probe: (f) => count(`invite_uses where invite_id = '${f.invite}'`),
    shows: '0',
  },
  {
    // The answer to a request that is open already takes none of the household's locks. An admin
    // who decides the request holds the asker's memberships, and the answer waits for that.
    name: 'accept_invite asked a second time, an admin approved meanwhile',
    caller: (f) => f.guest,
    call: joins,
    given: guestAsked,
    hold: memberships('guest'),
    // The membership closes the request (join_requests_close_on_join).
    change: (f) =>
      `insert into public.household_members (household_id, user_id, role)
       values ('${f.household}', '${f.guest}', 'member')`,
    ends: 'member',
    probe: guestIn,
    shows: '1 memberships, 0 open requests',
  },
  {
    name: 'accept_invite asked a second time, an admin declined meanwhile',
    caller: (f) => f.guest,
    call: joins,
    given: guestAsked,
    hold: memberships('guest'),
    change: (f) =>
      `update public.join_requests set decision = 'declined', decided_at = now()
       where household_id = '${f.household}' and user_id = '${f.guest}'`,
    ends: 'declined_recently',
    probe: guestIn,
    shows: '0 memberships, 0 open requests',
  },
];

Deno.test({
  name: 'a check before a lock is made again under it',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async (t) => {
    const admin = connect();
    const users: string[] = [];
    const households: string[] = [];
    try {
      for (const c of CASES) {
        await t.step({
          name: c.name,
          sanitizeResources: false,
          sanitizeOps: false,
          fn: async () => {
            const f = await fixture(admin, users, households);
            if (c.given) await admin.unsafe(c.given(f));
            const side = connect();
            const caller = connect();
            try {
              const [backend] = await caller<{ pid: number }[]>`select pg_backend_pid() as pid`;
              assertExists(backend);
              let waited = false;
              let pending: Promise<string> | undefined;
              await side.begin(async (held) => {
                await held.unsafe(c.hold(f));
                pending = answerAs(caller, c.caller(f), c.call(f));
                const until = performance.now() + REACH_MS;
                while (!waited && performance.now() < until) {
                  const [activity] = await admin<{ waits: boolean }[]>`
                    select coalesce(bool_or(wait_event_type = 'Lock'), false) as waits
                    from pg_stat_activity where pid = ${backend.pid}`;
                  waited = activity?.waits ?? false;
                  if (!waited) await new Promise((done) => setTimeout(done, 20));
                }
                if (waited) await held.unsafe(c.change(f));
              });
              assertExists(pending);
              const ended = await pending;
              assertEquals(waited, true, `the call waits for the held lock (it ended: ${ended})`);
              assertEquals(ended, c.ends, 'how the call ends');
              const [probe] = await admin.unsafe<{ v: string | null }[]>(c.probe(f));
              assertEquals(probe?.v, c.shows, 'what it left');
            } finally {
              await side.end({ timeout: 2 });
              await caller.end({ timeout: 2 });
            }
          },
        });
      }
    } finally {
      await admin`delete from public.households where id = any(${households}::uuid[])`;
      await admin`delete from auth.users where id = any(${users}::uuid[])`;
      await admin.end();
    }
  },
});
