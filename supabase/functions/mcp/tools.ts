// The MCP server: one per request, bound to the authenticated caller.
import { type CallToolResult, McpServer } from '@modelcontextprotocol/server';
import { z } from 'zod';
import type { Auth } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import type { McpTool } from '../_shared/telemetry.ts';
import type { UserEvent } from '../_shared/user_events.ts';
import { asUser, ranOutOfTime, rowBusy, type Tx } from '../_shared/db.ts';
import {
  addItems,
  categories,
  listCatalog,
  listItems,
  moveItem,
  stores,
  tickItems,
  ToolError,
} from '../_shared/list.ts';
import { storedText } from '../_shared/stored_text.ts';
import { telemetry } from './telemetry.ts';

const INSTRUCTIONS = `Snacklist: die gemeinsame Einkaufsliste eines Haushalts (deutsch).
Einträge haben einen Namen (z. B. "Windeln"), optional eine Marke ("Pampers"), Eigenschaften
("Größe 3, Big Pack"), eine Menge ("2", "500 g"), eine Kategorie (Gang im Laden, z. B.
"Kühlregal") und optional einen Laden (z. B. "dm"). Neue Einträge werden automatisch zerlegt und
einsortiert; gib eine Kategorie nur an, wenn der Nutzer sie ausdrücklich nennt.
Einträge, Kategorien und Läden lassen sich per Name (ungefähr, ohne Umlaute) oder per id angeben.
Abgehakte Einträge verschwinden aus der Liste.
Wer in mehreren Haushalten ist, findet sie mit list_households; die Listen-Werkzeuge nehmen dann
"household" (id oder Name), ohne Angabe gilt der Standardhaushalt.
Ein Haushalt kann mehrere Listen haben (list_lists, z. B. "Wocheneinkauf" und "Baumarkt"); die
Werkzeuge nehmen dann "list" (id oder genauer Name), ohne Angabe gilt die Standardliste des Nutzers
(in der App gewählt, sonst die erste Liste).`;

/**
 * `ttlMs`/`cacheScope` on 2026-era list results (SEP-2549). The tool list and the server's
 * description change only with a deploy; an hour keeps clients from polling. Private: the answers
 * are to an authenticated caller, so no shared cache may keep them.
 */
const CACHE_HINTS = {
  'tools/list': { ttlMs: 3_600_000, cacheScope: 'private' },
  'server/discover': { ttlMs: 3_600_000, cacheScope: 'private' },
} as const;

/** The tool error for a call that ran out of its time (ranOutOfTime); it rolled back. */
export const tookTooLong: Record<Lang, string> = {
  de: 'Das hat zu lange gedauert und wurde abgebrochen. Es wurde nichts geändert. Versuch es mit ' +
    'weniger Einträgen auf einmal und einem Aufruf nach dem anderen.',
  en: 'That took too long and was stopped. Nothing was changed. Try fewer items at once, and ' +
    'one call at a time.',
};

/** The tool error for a call that met a household that is being changed right now (rowBusy). */
export const busyNow: Record<Lang, string> = {
  de: 'Das geht in diesem Moment nicht. Es wurde nichts geändert. Versuch es gleich noch einmal.',
  en: 'That is not possible at this moment. Nothing was changed. Try again in a moment.',
};

/**
 * The tool error for any other failure. The call ran in one transaction, which rolled back. The
 * error goes to error tracking; its own message (Postgres' text, say) never reaches the client.
 */
export const failedNow: Record<Lang, string> = {
  de: 'Das hat nicht geklappt. Es wurde nichts geändert. Versuch es später noch einmal.',
  en: 'That did not work. Nothing was changed. Try again later.',
};

/**
 * Job 50: what a tool call of a user without Snacklist Premium gets while the lock is on. A tool
 * result, not a 401/403: the client keeps its token and needs no new sign-in once the user
 * unlocks. Premium is per user (PB2): another member's plan does not unlock the caller (job 328
 * review 0). PLACEHOLDER copy (Spec #4); the final text comes from Snacklist PM.
 */
export const premiumRequired: Record<Lang, string> = {
  de: 'Du brauchst Snacklist Premium für den Zugang über KI-Assistenten. Schalte es in der ' +
    'Snacklist-App frei. Es wurde nichts gelesen oder geändert.',
  en: 'You need Snacklist Premium for AI assistant access. Unlock it in the Snacklist app. ' +
    'Nothing was read or changed.',
};

export type Lang = 'de' | 'en';

/** English when the client prefers it to German (Accept-Language), else German like the tools. */
export function langOf(acceptLanguage: string | null): Lang {
  const ranked = (acceptLanguage ?? '').split(',').map((part, i) => {
    const [tag = '', ...params] = part.trim().toLowerCase().split(';');
    const [lang] = tag.split('-');
    const q = Number(params.find((p) => p.trim().startsWith('q='))?.trim().slice(2) ?? 1);
    return { lang, q: Number.isFinite(q) ? q : 0, i };
  }).filter((r) => (r.lang === 'de' || r.lang === 'en') && r.q > 0)
    .sort((a, b) => b.q - a.q || a.i - b.i);
  return ranked[0]?.lang === 'en' ? 'en' : 'de';
}

/** Whether a household may use the tools; asked once per household and request. */
export type Gate = (householdId: string) => Promise<Access>;

/** How a tool call ended, as mcp_tool_call reports it (job 195). */
export type CallReason = 'done' | 'tool_error' | 'premium_required' | 'server';

/** Reports one finished tool call; never throws. */
export type ReportCall = (
  call: { tool: McpTool; household: string; reason: CallReason },
) => Promise<void>;

/**
 * Reports each tool call of [userId] as mcp_tool_call through [send].
 *
 * N-147 (Legal Review, 12 Nov 2026): capture is off until the analytics
 * consent text covers connected-app (MCP) usage events. The catalog and this
 * helper stay; set [mcpToolCallCapture] back to true to restore the send.
 */
export const mcpToolCallCapture = false;

export function reportToolCalls(send: UserEvent, userId: string): ReportCall {
  return ({ tool, household, reason }) => {
    if (!mcpToolCallCapture) return Promise.resolve();
    return send(userId, household, 'mcp_tool_call', {
      tool,
      result: reason === 'done' ? 'success' : 'fail',
      reason,
    });
  };
}

/**
 * A tool body: runs as the caller in one transaction once the household (the [household]
 * argument, else the one the credential acts in) may use MCP; ToolErrors become tool-level
 * errors. A failing check fails the call like any database error: reported, answered with
 * failedNow. A null [gate] is no check. Every call ends with one [done], in the household it
 * resolved to (the credential's while unresolved).
 */
function run(
  auth: Auth,
  gate: Gate | null,
  lang: Lang,
  household: string | undefined,
  body: (tx: Tx, household: string) => Promise<unknown>,
  done: (household: string, reason: CallReason) => Promise<void>,
) {
  return async (): Promise<CallToolResult> => {
    let h = auth.householdId;
    try {
      if (household !== undefined) {
        h = await asUser(auth.userId, (tx) => householdNamed(tx, auth, household));
      }
      if (gate && await gate(h) === 'locked') {
        await done(h, 'premium_required');
        return { isError: true, content: [{ type: 'text', text: premiumRequired[lang] }] };
      }
      const result = await asUser(auth.userId, (tx) => body(tx, h));
      await done(h, 'done');
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    } catch (e) {
      const slow = ranOutOfTime(e);
      const busy = rowBusy(e);
      const toolError = e instanceof ToolError;
      await done(h, toolError || slow || busy ? 'tool_error' : 'server');
      if (slow) return { isError: true, content: [{ type: 'text', text: tookTooLong[lang] }] };
      if (busy) return { isError: true, content: [{ type: 'text', text: busyNow[lang] }] };
      if (toolError) return { isError: true, content: [{ type: 'text', text: e.message }] };
      console.error('mcp: tool failed', (e as Error)?.name, (e as { code?: unknown })?.code);
      telemetry.exception(e);
      return { isError: true, content: [{ type: 'text', text: failedNow[lang] }] };
    }
  };
}

/** A household the tools may act in; `default` is where a call without "household" goes. */
export type Household = { id: string; name: string; members: number; default: boolean };

/**
 * The caller's households. An OAuth connection reaches all of them; a personal access token
 * only the household it was made in.
 */
export async function households(tx: Tx, auth: Auth): Promise<Household[]> {
  const rows = await tx<{ id: string; name: string; member_count: number }[]>`
    select id, name, member_count from public.my_households()`;
  return rows
    .filter((r) => auth.via === 'oauth' || r.id === auth.householdId)
    .map((r) => ({
      id: r.id,
      name: r.name,
      members: r.member_count,
      default: r.id === auth.householdId,
    }));
}

/** The id of the caller's household [ref] names (its id or its name, in any case). */
export async function householdNamed(tx: Tx, auth: Auth, ref: string): Promise<string> {
  const mine = await households(tx, auth);
  const wanted = ref.trim();
  const folded = wanted.toLocaleLowerCase('de');
  const byId = mine.find((h) => h.id === folded);
  if (byId) return byId.id;
  const byName = mine.filter((h) => h.name.trim().toLocaleLowerCase('de') === folded);
  const names = mine.map((h) => h.name);
  const [only, ...more] = byName;
  if (only && more.length === 0) return only.id;
  if (only) {
    throw new ToolError(
      `Mehrere Haushalte heißen "${wanted}". Gib die id an: ` +
        byName.map((h) => `${h.name} (${h.id})`).join(', '),
      'ambiguous',
      null,
      byName.map((h) => h.id),
      ref,
    );
  }
  throw new ToolError(
    auth.via === 'oauth'
      ? `Kein Haushalt "${wanted}". Deine Haushalte: ${names.join(', ')}`
      : `Dieser Zugriffstoken gilt nur für den Haushalt ${names.join(', ')}.`,
    'not_found',
    null,
    names,
    ref,
  );
}

const itemRef = storedText.min(1).max(120).describe(
  'Name des Eintrags auf der Liste (z. B. "Milch") oder seine id; eine id findet ihn ohne "list" ' +
    'auf jeder Liste des Haushalts',
);
const storeName = storedText.min(1).max(60).describe(
  'Ein Laden des Haushalts (list_stores), z. B. "dm", "Lidl" oder ein eigener wie "Rewe"',
);
const categoryName = storedText.min(1).max(60).describe(
  'Kategorie, z. B. "Obst & Gemüse" oder "Kühlregal"',
);
const householdRef = storedText.min(1).max(80).optional().describe(
  'Haushalt (list_households): seine id oder sein Name. Ohne Angabe der Standardhaushalt.',
);
const listRef = storedText.min(1).max(60).optional().describe(
  'Liste des Haushalts (list_lists): ihre id oder ihr genauer Name. Ohne Angabe die Standardliste.',
);

/** A list of the household; `default` is where a call without "list" goes. */
export type ListEntry = { id: string; name: string; default: boolean };

export async function listLists(tx: Tx, household: string): Promise<ListEntry[]> {
  const { lists: options, defaultList } = await listCatalog(tx, household);
  return options.map((l) => ({ id: l.id, name: l.name, default: l.id === defaultList.id }));
}

export function buildServer(
  auth: Auth,
  gate: Gate,
  report: ReportCall,
  lang: Lang = 'de',
): McpServer {
  const server = new McpServer(
    { name: 'snacklist', title: 'Snacklist', version: '1.0.0' },
    { instructions: INSTRUCTIONS, cacheHints: CACHE_HINTS },
  );
  const asked = new Map<string, Promise<Access>>();
  const once: Gate = (household) => {
    const known = asked.get(household);
    if (known) return known;
    const access = gate(household);
    asked.set(household, access);
    return access;
  };
  const call = (
    tool: McpTool,
    gate: Gate | null,
    household: string | undefined,
    body: (tx: Tx, household: string) => Promise<unknown>,
  ) =>
    run(auth, gate, lang, household, body, (h, reason) => report({ tool, household: h, reason }));

  server.registerTool('list_households', {
    title: 'Haushalte anzeigen',
    description: 'Listet die Haushalte, in denen der Nutzer ist, mit Mitgliederzahl. "default" ' +
      'markiert den Standardhaushalt, in dem die anderen Werkzeuge ohne "household" arbeiten. ' +
      'Mit einem Zugriffstoken nur dessen Haushalt.',
    annotations: { readOnlyHint: true },
    // Ungated: it lists only the user's own households, so a locked default can still find an
    // unlocked one.
  }, () => call('list_households', null, undefined, (tx) => households(tx, auth))());

  server.registerTool('list_lists', {
    title: 'Listen anzeigen',
    description:
      'Listet die Einkaufslisten des Haushalts in ihrer Reihenfolge. "default" markiert ' +
      'die Standardliste des Nutzers, in der die anderen Werkzeuge ohne "list" arbeiten (auch Siri ' +
      'und Alexa); ohne eigene Wahl in der App ist das die erste Liste.',
    inputSchema: z.object({ household: householdRef }),
    annotations: { readOnlyHint: true },
  }, ({ household }) => call('list_lists', once, household, (tx, h) => listLists(tx, h))());

  server.registerTool(
    'list_items',
    {
      title: 'Einkaufsliste anzeigen',
      description: 'Zeigt die offenen Einträge der Einkaufsliste mit Marke und Eigenschaften, in ' +
        'Gang-Reihenfolge und innerhalb einer Kategorie in der Laufweg-Reihenfolge des Haushalts. Mit "store" ' +
        'nur, was in diesem Laden gekauft werden kann (seine Einträge plus alle ohne Laden), in der ' +
        'Reihenfolge dieses Ladens. Mit "category" nur eine Kategorie. "counts" gilt immer für die ' +
        'ganze Liste, auch mit Filter: "open" offene Einträge, "checkedLast24h" in den letzten 24 ' +
        'Stunden abgehakte. "list" in der Antwort nennt die gezeigte Liste.',
      inputSchema: z.object({
        store: storeName.optional(),
        category: categoryName.optional(),
        household: householdRef,
        list: listRef,
      }),
      annotations: { readOnlyHint: true },
    },
    ({ household, ...args }) =>
      call('list_items', once, household, (tx, h) => listItems(tx, h, args))(),
  );

  server.registerTool(
    'add_items',
    {
      title: 'Einträge hinzufügen',
      description:
        'Setzt einen oder mehrere Einträge auf die Liste. Der Name wird zerlegt: "Windeln Pampers ' +
        'Größe 3" → name "Windeln", Marke "Pampers", Eigenschaften "Größe 3"; "2 Gurken" → name ' +
        '"Gurken", Menge "2". Was in "quantity", "brand" oder "properties" steht, ersetzt den ' +
        'zerlegten Wert. Jeder Eintrag wird automatisch einer Kategorie zugeordnet; dabei gelten ' +
        'zuerst die Korrekturen des Haushalts (move_item oder in der App), dann ein Wörterbuch. Ohne ' +
        '"store" bekommt er den Laden, in dem er zuletzt gekauft wurde, sonst den Laden einer ' +
        'Eigenmarke (Balea → dm) oder dm für Drogerieartikel. Was schon auf der Liste steht ("Gurke" ' +
        '= "2 Gurken"; eine andere Größe oder Marke ist ein anderer Eintrag), wird nicht doppelt ' +
        'angelegt und unter "alreadyOnList" gemeldet. Steht schon eine andere Schreibweise oder ein ' +
        'Synonym auf der Liste ("Karotten" und "Möhren"), wird der Eintrag trotzdem angelegt und unter ' +
        '"similarOnList" gemeldet (added: der neue Name, onList: höchstens drei der offenen ' +
        'Einträge, total: wie viele es sind); sag dem Nutzer dann, dass etwas Ähnliches schon auf ' +
        'der Liste steht. Zusammengeführt wird nichts.',
      inputSchema: z.object({
        items: z.array(z.object({
          name: storedText.min(1).max(120).describe('Was gekauft werden soll, z. B. "Milch"'),
          quantity: storedText.max(40).optional().describe('Menge, z. B. "2" oder "500 g"'),
          brand: storedText.max(60).optional().describe('Marke, z. B. "Pampers" oder "Ja!"'),
          properties: storedText.max(120).optional().describe(
            'Eigenschaften, mit Komma getrennt, z. B. "Größe 3, Big Pack" oder "1,5 %"',
          ),
          category: categoryName.optional().describe(
            'Nur angeben, wenn der Nutzer eine Kategorie ausdrücklich nennt; wird wie eine Korrektur gemerkt',
          ),
          store: storeName.optional().describe(
            'Nur angeben, wenn es in einem bestimmten Laden sein soll',
          ),
        })).min(1).max(50),
        household: householdRef,
        list: listRef,
      }),
    },
    ({ items, household, list }) =>
      call('add_items', once, household, (tx, h) => addItems(tx, h, items, list))(),
  );

  server.registerTool(
    'tick_items',
    {
      title: 'Einträge abhaken',
      description:
        'Hakt einen oder mehrere Einträge als gekauft ab; sie verschwinden von der Liste und ' +
        'landen unter "Zuletzt verwendet". Nicht gefundene oder schon abgehakte Einträge werden ' +
        'unter "notFound" gemeldet, ein zweiter Aufruf ändert also nichts.',
      inputSchema: z.object({
        items: z.array(itemRef).min(1).max(50),
        household: householdRef,
        list: listRef,
      }),
      annotations: { destructiveHint: false, idempotentHint: true },
    },
    ({ items, household, list }) =>
      call('tick_items', once, household, (tx, h) => tickItems(tx, h, items, list))(),
  );

  server.registerTool(
    'move_item',
    {
      title: 'Eintrag verschieben',
      description:
        'Ändert die Kategorie und/oder den Laden eines Eintrags; er kommt ans Ende seiner neuen ' +
        'Gruppe im Laufweg. Beides merkt sich der Haushalt: ' +
        'derselbe Eintrag landet beim nächsten Hinzufügen in dieser Kategorie und diesem Laden. ' +
        'store: null entfernt den Laden (dann in jedem Laden kaufbar) und vergisst ihn.',
      inputSchema: z.object({
        item: itemRef,
        category: categoryName.optional(),
        store: storeName.nullable().optional(),
        household: householdRef,
        list: listRef,
      }),
      annotations: { idempotentHint: true },
    },
    ({ household, ...args }) =>
      call('move_item', once, household, (tx, h) => moveItem(tx, h, args))(),
  );

  server.registerTool('list_categories', {
    title: 'Kategorien anzeigen',
    description: 'Listet die Kategorien des Haushalts in Gang-Reihenfolge.',
    inputSchema: z.object({ household: householdRef }),
    annotations: { readOnlyHint: true },
  }, ({ household }) => call('list_categories', once, household, (tx, h) => categories(tx, h))());

  server.registerTool('list_stores', {
    title: 'Läden anzeigen',
    description: 'Listet die Läden des Haushalts.',
    inputSchema: z.object({ household: householdRef }),
    annotations: { readOnlyHint: true },
  }, ({ household }) => call('list_stores', once, household, (tx, h) => stores(tx, h))());

  return server;
}
