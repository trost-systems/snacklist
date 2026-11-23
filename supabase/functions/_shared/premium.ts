// Job 50: MCP / AI assistants are part of Snacklist Premium (Spec #4), and the API (job 73);
// Siri (job 184) and Alexa (job 72, Legal Review N-27) stay free and never ask. Every other
// integration endpoint asks requirePremium once it knows the caller's household; the rule itself
// lives in Postgres (public.integration_gate: the integration_lock switch, then
// user_has_premium of the caller only, since job 419; a household's plan does not unlock), never here. A locked
// household's first refusal of the hour per integration counts as integration_blocked for an
// install that said yes to analytics. A failing check throws: the endpoint answers with its
// transient error, never as locked and never by going ahead (DECISIONS "Job 50").
import { serviceDb, type Sql } from './db.ts';
import type { Telemetry } from './telemetry.ts';
import { userEvents } from './user_events.ts';

export type Integration = 'mcp' | 'api';

export type Access = 'open' | 'locked';

export interface Caller {
  userId: string;
  householdId: string;
}

/** Decides whether [caller] may use [integration] in their household now. */
export type RequirePremium = (caller: Caller, integration: Integration) => Promise<Access>;

export interface GateDeps {
  gate(caller: Caller, integration: Integration): Promise<{ locked: boolean; report: boolean }>;
  /** Sends integration_blocked for [caller]; only called for a refusal that is reported. */
  blocked(caller: Caller, integration: Integration): Promise<void>;
}

export function premiumGate(deps: GateDeps): RequirePremium {
  return async (caller, integration) => {
    const { locked, report } = await deps.gate(caller, integration);
    if (!locked) return 'open';
    if (report) {
      await deps.blocked(caller, integration).catch((e) =>
        console.error(`premium: integration_blocked not recorded: ${(e as Error)?.name}`)
      );
    }
    return 'locked';
  };
}

export async function integrationGate(
  sql: Sql,
  caller: Caller,
  integration: Integration,
): Promise<{ locked: boolean; report: boolean }> {
  const [row] = await sql<{ locked: boolean; report: boolean }[]>`
    select locked, report
    from public.integration_gate(${caller.householdId}::uuid, ${integration}, ${caller.userId}::uuid)`;
  return row;
}

/** The production gate for a function, reporting through its [telemetry]. */
export function requirePremiumWith(
  telemetry: Telemetry,
  sql: () => Sql = serviceDb,
): RequirePremium {
  const send = userEvents(telemetry, sql);
  return premiumGate({
    gate: (caller, integration) => integrationGate(sql(), caller, integration),
    blocked: (caller, integration) =>
      send(caller.userId, caller.householdId, 'integration_blocked', { integration }),
  });
}
