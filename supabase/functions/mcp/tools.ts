// The MCP server: one per request, bound to the authenticated caller.
import { type CallToolResult, McpServer, type ToolAnnotations } from '@modelcontextprotocol/server';
import { z } from 'zod';
import { allows, type Auth, type Scope } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import type { McpTool } from '../_shared/telemetry.ts';
import type { UserEvent } from '../_shared/user_events.ts';
import { asUser, ranOutOfTime, rowBusy, type Tx } from '../_shared/db.ts';
import {
  addItems,
  addStore,
  anchorOf,
  categories,
  changeList,
  createList,
  getItem,
  listCatalog,
  listItems,
  listRecent,
  mergeItems,
  placeItem,
  RECENT_SHOWN,
  removeItems,
  renameStore,
  setStoreLayout,
  setStoreOrder,
  STORE_ORDER_MAX,
  storeLayout,
  stores,
  tickItems,
  ToolError,
  untickItems,
  updateItem,
  usuals,
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
(in der App gewählt, sonst die erste Liste).
Was der Haushalt oft kauft, zeigt suggest_items; was zuletzt abgehakt wurde, list_recent.`;

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
 * Info pages (site/content/guides) a locked call points to. Plain information, no price, no
 * checkout: OpenAI's rules (section 5.1) let a connector say a feature needs another plan and
 * link to such a page, never show plans, start a purchase or promote an upgrade.
 */
export const planInfoUrl: Record<Lang, string> = {
  de: 'https://snacklist.app/de/anleitungen/ki-assistenten-tarif',
  en: 'https://snacklist.app/en/guides/ai-assistants-plan',
};

/**
 * Job 50, reworded in job 415: what a tool call of a user without access gets while the lock is
 * on. A tool result, not a 401/403: the client keeps its token and needs no new sign-in once the
 * plan changes. Premium is per user (PB2): another member's plan does not unlock the caller (job
 * 328 review 0). Neutral by rule (job 415): no plan or product name, no price, no call to action;
 * a test pins it.
 */
export const premiumRequired: Record<Lang, string> = {
  de: `Dafür brauchst du einen anderen Snacklist-Tarif. Infos: ${planInfoUrl.de} ` +
    'Es wurde nichts gelesen oder geändert.',
  en: `This needs a different Snacklist plan. Info: ${planInfoUrl.en} ` +
    'Nothing was read or changed.',
};

/**
 * Job 397: what a call with a read-only personal key gets from a tool that writes. A tool result
 * like premiumRequired, naming the scope the key lacks.
 */
export const writeScopeRequired: Record<Lang, string> = {
  de: 'Dieser Zugriffsschlüssel darf nur lesen. Erstelle in der ' +
    'Snacklist-App unter Mehr › Zugänge einen Schlüssel zum Lesen und Schreiben. Es wurde nichts ' +
    'geändert.',
  en: 'This access key can only read. Create a key that can read and ' +
    'write in the Snacklist app under More › Access. Nothing was changed.',
};

/** The scope each tool needs; a personal key without it gets writeScopeRequired. */
export const toolScopes = {
  list_households: 'read',
  list_lists: 'read',
  list_items: 'read',
  get_item: 'read',
  list_categories: 'read',
  list_stores: 'read',
  list_recent: 'read',
  suggest_items: 'read',
  add_items: 'write',
  tick_items: 'write',
  untick_items: 'write',
  move_item: 'write',
  update_item: 'write',
  remove_items: 'write',
  merge_items: 'write',
  place_item: 'write',
  set_store_order: 'write',
  create_list: 'write',
  rename_list: 'write',
  add_store: 'write',
  rename_store: 'write',
  set_store_layout: 'write',
} as const satisfies Record<McpTool, Scope>;

/**
 * Job 415: the four hints every tool declares, explicit because Claude's and ChatGPT's directory
 * reviews reject a tool that leaves one to the spec's defaults. openWorldHint is false throughout:
 * a tool reaches only the caller's household. destructiveHint is true where a call deletes data or
 * overwrites text the user typed (remove_items, merge_items, update_item, the renames), false for
 * additive writes and for changes that keep every value (ticking, categories, orders); clients
 * ask the user before a destructive call. idempotentHint is false where a repeat adds again.
 */
export const toolAnnotations = {
  list_households: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_lists: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_items: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  get_item: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_categories: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_stores: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_recent: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  suggest_items: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  add_items: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
  },
  tick_items: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  untick_items: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  move_item: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  update_item: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  remove_items: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  merge_items: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: false,
    openWorldHint: false,
  },
  place_item: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  set_store_order: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  create_list: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
  },
  rename_list: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  add_store: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  rename_store: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  set_store_layout: {
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
} as const satisfies Record<McpTool, ToolAnnotations>;

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
 * A tool body: runs as the caller in one transaction once the credential has [scope] and the
 * household (the [household] argument, else the one the credential acts in) may use MCP; ToolErrors become tool-level
 * errors. A failing check fails the call like any database error: reported, answered with
 * failedNow. A null [gate] is no check. Every call ends with one [done], in the household it
 * resolved to (the credential's while unresolved).
 */
function run(
  auth: Auth,
  scope: Scope,
  gate: Gate | null,
  lang: Lang,
  household: string | undefined,
  body: (tx: Tx, household: string) => Promise<unknown>,
  done: (household: string, reason: CallReason) => Promise<void>,
) {
  return async (): Promise<CallToolResult> => {
    let h = auth.householdId;
    if (!allows(auth, scope)) {
      await done(h, 'tool_error');
      return {
        isError: true,
        content: [{ type: 'text', text: writeScopeRequired[lang] }],
        structuredContent: { error: 'insufficient_scope', details: { required: scope } },
      };
    }
    try {
      if (household !== undefined) {
        h = await asUser(auth.userId, (tx) => householdNamed(tx, auth, household));
      }
      if (gate && await gate(h) === 'locked') {
        await done(h, 'premium_required');
        return {
          isError: true,
          content: [{ type: 'text', text: premiumRequired[lang] }],
          structuredContent: {
            error: 'premium_required',
            details: { integration: 'mcp', info: planInfoUrl[lang] },
          },
        };
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

/**
 * Server switches (public.app_switches) a request reads before the tools are built. Off, a tool
 * behind a switch is not registered: absent from tools/list, and a call is an unknown tool.
 */
export type Switches = {
  /**
   * mcp_lists_stores (job 345): create_list, rename_list, add_store, rename_store and
   * set_store_layout. Off until privacy section 7 names lists and stores for assistants.
   */
  listsStores: boolean;
};

export const SWITCHED_OFF: Switches = { listsStores: false };

/** The switches a request reads, by their app_switches keys. */
export const switchKeys = { listsStores: 'mcp_lists_stores' } as const satisfies Record<
  keyof Switches,
  string
>;

export function buildServer(
  auth: Auth,
  gate: Gate,
  report: ReportCall,
  lang: Lang = 'de',
  switches: Switches = SWITCHED_OFF,
): McpServer {
  const server = new McpServer(
    { name: 'snacklist', title: 'Snacklist', version: '1.4.0' },
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
    run(
      auth,
      toolScopes[tool],
      gate,
      lang,
      household,
      body,
      (h, reason) => report({ tool, household: h, reason }),
    );

  server.registerTool('list_households', {
    title: 'Haushalte anzeigen',
    description: 'Listet die Haushalte, in denen der Nutzer ist, mit Mitgliederzahl. "default" ' +
      'markiert den Standardhaushalt, in dem die anderen Werkzeuge ohne "household" arbeiten. ' +
      'Mit einem Zugriffstoken nur dessen Haushalt.',
    annotations: toolAnnotations.list_households,
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
    annotations: toolAnnotations.list_lists,
  }, ({ household }) => call('list_lists', once, household, (tx, h) => listLists(tx, h))());

  server.registerTool(
    'list_items',
    {
      title: 'Einkaufsliste anzeigen',
      description: 'Zeigt die offenen Einträge der Einkaufsliste mit Marke und Eigenschaften. ' +
        '"order" in der Antwort sagt, wie sortiert ist: "walk" (gelernte Reihenfolge) heißt Laden ' +
        'für Laden in der Reihenfolge der Läden, dann die Einträge ohne Laden, jeweils in ' +
        'Laufweg-Reihenfolge; "aisle" heißt in Gang-Reihenfolge der Kategorien und innerhalb einer ' +
        'Kategorie im Laufweg. "position" ist der Platz eines Eintrags in seinem Laden (oder unter ' +
        '"ohne Laden"), ab 1. Mit "store" nur, was in diesem Laden gekauft werden kann (seine ' +
        'Einträge plus alle ohne Laden), in der Reihenfolge dieses Ladens. Mit "category" nur eine ' +
        'Kategorie. "counts" gilt immer für die ganze Liste, auch mit Filter: "open" offene ' +
        'Einträge, "checkedLast24h" in den letzten 24 Stunden abgehakte. "list" in der Antwort ' +
        'nennt die gezeigte Liste.',
      inputSchema: z.object({
        store: storeName.optional(),
        category: categoryName.optional(),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.list_items,
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
        'Einträge, total: wie viele es sind); das bedeutet, etwas Ähnliches steht schon auf ' +
        'der Liste. Von selbst wird nichts zusammengeführt; will der Nutzer es, führt ' +
        'merge_items (keep: der Eintrag aus onList, merge: der neue) beide zusammen wie ' +
        '"Zusammenführen" in der App.',
      annotations: toolAnnotations.add_items,
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
      annotations: toolAnnotations.tick_items,
    },
    ({ items, household, list }) =>
      call('tick_items', once, household, (tx, h) => tickItems(tx, h, items, list))(),
  );

  server.registerTool(
    'untick_items',
    {
      title: 'Abhaken zurücknehmen',
      description: 'Setzt abgehakte Einträge wieder auf die Liste. Ein Name findet den zuletzt ' +
        'abgehakten Eintrag dieses Namens auf der Liste, außer er steht dort schon offen; eine id ' +
        'findet ihn ohne "list" auf jeder ' +
        'Liste des Haushalts. Nicht gefundene oder noch offene Einträge werden unter "notFound" ' +
        'gemeldet, ein zweiter Aufruf ändert also nichts.',
      inputSchema: z.object({
        items: z.array(itemRef).min(1).max(50),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.untick_items,
    },
    ({ items, household, list }) =>
      call('untick_items', once, household, (tx, h) => untickItems(tx, h, items, list))(),
  );

  server.registerTool(
    'move_item',
    {
      title: 'Eintrag verschieben',
      description:
        'Ändert die Kategorie und/oder den Laden eines Eintrags. Bei gelernter Reihenfolge ' +
        '(list_items "order": "walk") nimmt er im neuen Laden seinen Platz ein, sonst kommt er ans ' +
        'Ende seiner neuen Gruppe im Laufweg. Beides merkt sich der Haushalt: ' +
        'derselbe Eintrag landet beim nächsten Hinzufügen in dieser Kategorie und diesem Laden. ' +
        'store: null entfernt den Laden (dann in jedem Laden kaufbar) und vergisst ihn.',
      inputSchema: z.object({
        item: itemRef,
        category: categoryName.optional(),
        store: storeName.nullable().optional(),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.move_item,
    },
    ({ household, item, list, category, store }) =>
      call(
        'move_item',
        once,
        household,
        (tx, h) => updateItem(tx, h, { item, list }, { category, store }),
      )(),
  );

  server.registerTool(
    'place_item',
    {
      title: 'Eintrag einsortieren',
      description:
        'Setzt einen offenen Eintrag direkt vor ("before") oder hinter ("after") einen anderen, ' +
        'z. B. "die Eier hinter das Mehl"; genau eines von beiden angeben. Bei gelernter ' +
        'Reihenfolge (list_items "order": "walk") merkt sich der Haushalt den Platz im Laden; ' +
        'der andere Eintrag muss dann im selben Laden stehen (den Laden ändert move_item). Sonst ' +
        'übernimmt der Eintrag Laden und Kategorie des anderen, wie beim Ziehen in der App. Ein ' +
        'zweiter gleicher Aufruf ändert nichts.',
      inputSchema: z.object({
        item: itemRef,
        before: itemRef.optional(),
        after: itemRef.optional(),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.place_item,
    },
    ({ household, item, before, after, list }) =>
      call('place_item', once, household, (tx, h) => {
        const placing = anchorOf({ before, after });
        if (!placing) {
          throw new ToolError('Gib genau eines von "before" und "after" an.', 'invalid', 'anchor');
        }
        return placeItem(tx, h, { item, ...placing, list });
      })(),
  );

  server.registerTool(
    'set_store_order',
    {
      title: 'Reihenfolge eines Ladens setzen',
      description:
        'Legt fest, in welcher Reihenfolge die offenen Einträge eines Ladens auf der Liste ' +
        'stehen, z. B. "so laufe ich bei IKEA: …". Die genannten Einträge kommen in dieser ' +
        'Reihenfolge nach vorn, die übrigen des Ladens behalten ihre Reihenfolge dahinter. Jeder ' +
        'genannte Eintrag muss offen und in diesem Laden sein. Nur bei gelernter Reihenfolge ' +
        '(list_items "order": "walk"); sonst einzelne Einträge mit place_item. Gibt die offenen ' +
        'Einträge des Ladens in der neuen Reihenfolge zurück; ein zweiter gleicher Aufruf ändert ' +
        'nichts.',
      inputSchema: z.object({
        store: storeName,
        items: z.array(itemRef).min(1).max(STORE_ORDER_MAX),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.set_store_order,
    },
    ({ household, ...args }) =>
      call('set_store_order', once, household, (tx, h) => setStoreOrder(tx, h, args))(),
  );

  server.registerTool(
    'update_item',
    {
      title: 'Eintrag ändern',
      description:
        'Ändert einen offenen Eintrag wie "Bearbeiten" in der App: nur die angegebenen ' +
        'Felder. quantity, brand oder properties null (oder leer) löscht sie. category und store ' +
        'wie bei move_item (der Haushalt merkt sie sich; bei gelernter Reihenfolge nimmt er im ' +
        'neuen Laden seinen Platz ein). "toList" setzt ihn auf eine andere Liste ' +
        '(list_lists); "list" sagt, wo er jetzt steht. Steht nach der Änderung schon ein gleicher ' +
        'offener Eintrag (Name, Marke, Eigenschaften) auf der Liste, ändert sich nichts und der ' +
        'Aufruf meldet es.',
      inputSchema: z.object({
        item: itemRef,
        name: storedText.trim().min(1).max(120).optional().describe(
          'Neuer Name, z. B. "Hafermilch"',
        ),
        quantity: storedText.max(40).nullable().optional().describe(
          'Menge, z. B. "2" oder "500 g"',
        ),
        brand: storedText.max(60).nullable().optional().describe('Marke, z. B. "Pampers"'),
        properties: storedText.max(120).nullable().optional().describe(
          'Eigenschaften, mit Komma getrennt, z. B. "Größe 3, Big Pack"',
        ),
        category: categoryName.optional(),
        store: storeName.nullable().optional(),
        toList: storedText.min(1).max(60).optional().describe(
          'Liste, auf die der Eintrag umzieht (list_lists): ihre id oder ihr genauer Name',
        ),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.update_item,
    },
    ({ household, item, list, toList, ...edit }) =>
      call(
        'update_item',
        once,
        household,
        (tx, h) => updateItem(tx, h, { item, list }, { ...edit, list: toList }),
      )(),
  );

  server.registerTool(
    'remove_items',
    {
      title: 'Einträge löschen',
      description: 'Löscht offene Einträge von der Liste, ohne sie abzuhaken (sie landen nicht ' +
        'unter "Zuletzt verwendet"). Was der Haushalt über sie gelernt hat (Kategorie, Laden), ' +
        'bleibt. Nicht gefundene Einträge werden unter "notFound" gemeldet, ein zweiter Aufruf ' +
        'ändert also nichts. Nur auf ausdrücklichen Wunsch des Nutzers.',
      inputSchema: z.object({
        items: z.array(itemRef).min(1).max(50),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.remove_items,
    },
    ({ items, household, list }) =>
      call('remove_items', once, household, (tx, h) => removeItems(tx, h, items, list))(),
  );

  server.registerTool(
    'get_item',
    {
      title: 'Eintrag anzeigen',
      description: 'Zeigt einen Eintrag mit Status ("open" oder "ticked") und Zeitpunkt des ' +
        'Hinzufügens. Eine id findet ihn auch abgehakt; ein Name nur unter den offenen Einträgen.',
      inputSchema: z.object({ item: itemRef, household: householdRef, list: listRef }),
      annotations: toolAnnotations.get_item,
    },
    ({ item, household, list }) =>
      call('get_item', once, household, (tx, h) => getItem(tx, h, item, list))(),
  );

  server.registerTool(
    'merge_items',
    {
      title: 'Einträge zusammenführen',
      description: 'Führt zwei offene Einträge zusammen wie "Zusammenführen" in der App, etwa ' +
        'nach "similarOnList" von add_items, wenn der Nutzer es will: "keep" bleibt mit seinem ' +
        'Namen, die Mengen werden addiert ("2" und "3" → "5"), fehlende Marke oder Eigenschaften ' +
        'kommen von "merge", das gelöscht wird. Beide müssen auf derselben Liste stehen. ' +
        'Antwort: "kept" wie er jetzt ist, "merged" wie der gelöschte war.',
      inputSchema: z.object({
        keep: itemRef.describe(
          'Der Eintrag, der bleibt, meist der aus "onList" von similarOnList (Name oder id)',
        ),
        merge: itemRef.describe(
          'Der Eintrag, der in "keep" aufgeht, meist der neu hinzugefügte (Name oder id)',
        ),
        household: householdRef,
        list: listRef,
      }),
      annotations: toolAnnotations.merge_items,
    },
    ({ keep, merge, household, list }) =>
      call('merge_items', once, household, (tx, h) => mergeItems(tx, h, { keep, merge, list }))(),
  );

  server.registerTool(
    'list_categories',
    {
      title: 'Kategorien anzeigen',
      description: 'Listet die Kategorien des Haushalts in Gang-Reihenfolge. Mit "store" in der ' +
        'Laufweg-Reihenfolge dieses Ladens (wie list_items mit "store"); "hidden" markiert ' +
        'Kategorien, die der Laden nicht führt.',
      inputSchema: z.object({ store: storeName.optional(), household: householdRef }),
      annotations: toolAnnotations.list_categories,
    },
    ({ store, household }) =>
      call(
        'list_categories',
        once,
        household,
        async (tx, h) =>
          store === undefined
            ? await categories(tx, h)
            : (await storeLayout(tx, h, store)).categories.map((c) => ({
              id: c.id,
              name: c.name,
              sort_order: c.sortOrder,
              hidden: c.hidden,
            })),
      )(),
  );

  server.registerTool('list_recent', {
    title: 'Zuletzt verwendet',
    description: 'Zeigt, was zuletzt abgehakt wurde, wie "Zuletzt verwendet" in der App: das ' +
      'Neueste zuerst, jedes Ding einmal (sein letzter Kauf), nichts, was wieder offen auf der ' +
      'Liste steht. "tickedAt" ist der Zeitpunkt des Abhakens. Mit untick_items (id) kommt ein ' +
      'Eintrag zurück auf die Liste.',
    inputSchema: z.object({
      limit: z.number().int().min(1).max(50).optional().describe(
        `Wie viele höchstens, ohne Angabe ${RECENT_SHOWN}`,
      ),
      household: householdRef,
      list: listRef,
    }),
    annotations: toolAnnotations.list_recent,
  }, ({ limit, household, list }) =>
    call(
      'list_recent',
      once,
      household,
      (tx, h) => listRecent(tx, h, list, limit ?? RECENT_SHOWN),
    )());

  server.registerTool(
    'suggest_items',
    {
      title: 'Vorschläge',
      description: 'Was der Haushalt oft kauft, wie die Vorschläge in der App: oft und zuletzt ' +
        'Gekauftes zuerst, nichts, was gerade offen auf einer Liste steht. Mit "prefix" nur Namen, ' +
        'die damit beginnen, dann Namen mit einem Wort, das damit beginnt. "uses": an wie vielen ' +
        'Tagen im letzten Jahr; "due": sein üblicher Abstand seit dem letzten Kauf ist um, er wird ' +
        'wohl bald gebraucht.',
      inputSchema: z.object({
        prefix: storedText.max(60).optional().describe('Anfang des Namens, z. B. "Mil"'),
        limit: z.number().int().min(1).max(50).optional().describe(
          'Wie viele höchstens, ohne Angabe 10',
        ),
        due: z.boolean().optional().describe(
          'Nur was fällig ist (wie "Wieder fällig" in der App), auch wenn es nicht unter den ersten ' +
            '"limit" steht. Wer wissen will, was fällig ist, setzt dies auf true.',
        ),
        household: householdRef,
      }),
      annotations: toolAnnotations.suggest_items,
    },
    ({ prefix, limit, due, household }) =>
      call(
        'suggest_items',
        once,
        household,
        (tx, h) => usuals(tx, h, prefix ?? '', limit ?? 10, due ?? false),
      )(),
  );

  if (switches.listsStores) {
    const listName = storedText.trim().min(1).max(60).describe('Name der Liste, z. B. "Baumarkt"');
    const storeNew = storedText.trim().min(1).max(40).describe(
      'Name des Ladens, nur der Name, z. B. "Rewe" oder "Wochenmarkt"',
    );

    server.registerTool('create_list', {
      title: 'Liste anlegen',
      description: 'Legt eine neue Einkaufsliste am Ende der Listen an, wie in der App. ' +
        'Höchstens 50 Listen je Haushalt. Nur auf ausdrücklichen Wunsch des Nutzers.',
      inputSchema: z.object({ name: listName, household: householdRef }),
      annotations: toolAnnotations.create_list,
    }, ({ name, household }) =>
      call('create_list', once, household, async (tx, h) => {
        const { id, name: created } = await createList(tx, h, name);
        return { id, name: created };
      })());

    server.registerTool('rename_list', {
      title: 'Liste umbenennen',
      description: 'Benennt eine Einkaufsliste um. Ein zweiter Aufruf ändert nichts.',
      inputSchema: z.object({
        list: storedText.min(1).max(60).describe(
          'Die Liste (list_lists): ihre id oder ihr genauer Name',
        ),
        name: listName.describe('Neuer Name der Liste'),
        household: householdRef,
      }),
      annotations: toolAnnotations.rename_list,
    }, ({ list, name, household }) =>
      call('rename_list', once, household, async (tx, h) => {
        const { id, name: renamed } = await changeList(tx, h, list, { name });
        return { id, name: renamed };
      })());

    server.registerTool('add_store', {
      title: 'Laden anlegen',
      description: 'Legt einen Laden an, wie in der App. Nur der Name, keine Handelskette. ' +
        'Gibt es den Namen schon (Groß- und Kleinschreibung, Umlaute egal), antwortet es mit ' +
        'diesem Laden und "created": false. Höchstens 50 Läden je Haushalt.',
      inputSchema: z.object({ name: storeNew, household: householdRef }),
      annotations: toolAnnotations.add_store,
    }, ({ name, household }) =>
      call('add_store', once, household, async (tx, h) => {
        const { store, created } = await addStore(tx, h, name);
        return { id: store.id, name: store.name, created };
      })());

    server.registerTool('rename_store', {
      title: 'Laden umbenennen',
      description: 'Benennt einen Laden um. Heißt schon ein anderer Laden so, ändert sich nichts ' +
        'und der Aufruf meldet es.',
      inputSchema: z.object({
        store: storeName,
        name: storeNew.describe('Neuer Name des Ladens, nur der Name'),
        household: householdRef,
      }),
      annotations: toolAnnotations.rename_store,
    }, ({ store, name, household }) =>
      call('rename_store', once, household, async (tx, h) => {
        const { id, name: renamed } = await renameStore(tx, h, store, name);
        return { id, name: renamed };
      })());

    server.registerTool(
      'set_store_layout',
      {
        title: 'Laufweg eines Ladens',
        description:
          'Legt fest, in welcher Reihenfolge die Kategorien in einem Laden kommen (der ' +
          'Laufweg, wie in der App unter dem Laden). "categories": die genannten zuerst, in dieser ' +
          'Reihenfolge, die übrigen danach in ihrer bisherigen. "hidden": alle Kategorien, die der ' +
          'Laden nicht führt; ohne Angabe bleiben sie. Bei gelernter Reihenfolge (list_items ' +
          '"order": "walk") ist der Laufweg nur die Ausgangsreihenfolge für neue Einträge; die ' +
          'Reihenfolge der Einträge im Laden setzen place_item und set_store_order. Antwort: der ' +
          'ganze Laufweg (wie list_categories mit "store").',
        inputSchema: z.object({
          store: storeName,
          categories: z.array(categoryName).max(200).optional(),
          hidden: z.array(categoryName).max(200).optional(),
          household: householdRef,
        }),
        annotations: toolAnnotations.set_store_layout,
      },
      ({ store, categories: order, hidden, household }) =>
        call('set_store_layout', once, household, async (tx, h) => {
          const layout = await setStoreLayout(tx, h, store, { order, hidden });
          return {
            store: layout.store.name,
            categories: layout.categories.map((c) => ({
              id: c.id,
              name: c.name,
              hidden: c.hidden,
            })),
          };
        })(),
    );
  }

  server.registerTool('list_stores', {
    title: 'Läden anzeigen',
    description: 'Listet die Läden des Haushalts.',
    inputSchema: z.object({ household: householdRef }),
    annotations: toolAnnotations.list_stores,
  }, ({ household }) => call('list_stores', once, household, (tx, h) => stores(tx, h))());

  return server;
}
