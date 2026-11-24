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

const INSTRUCTIONS = `Snacklist: a household's shared shopping list (item content is mostly German).
Items have a name (e.g. "Windeln"), optionally a brand ("Pampers"), properties
("Größe 3, Big Pack"), a quantity ("2", "500 g"), a category (aisle in the store, e.g.
"Kühlregal") and optionally a store (e.g. "dm"). New items are split and sorted into a
category automatically; give a category only if the user names it explicitly.
Items, categories and stores can be given by name (approximately, umlauts optional) or by id.
Ticked-off items disappear from the list.
Anyone in several households finds them with list_households; the list tools then take
"household" (id or name), and without it the default household applies.
A household can have several lists (list_lists, e.g. "Wocheneinkauf" and "Baumarkt"); the
tools then take "list" (id or exact name), and without it the user's default list applies
(chosen in the app, otherwise the first list).
suggest_items shows what the household often buys; list_recent shows what was ticked off last.`;

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
 * plan changes. Only the caller's own Premium (user_has_premium) unlocks;
 * neither another member's plan nor the household's does (job 419). Neutral by rule (job 415): no plan or product name, no price, no call to action;
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
 * Job 415: the four hints, and job 421's English `title`, every tool declares, explicit because Claude's and ChatGPT's directory
 * reviews reject a tool that leaves one to the spec's defaults. openWorldHint is false throughout:
 * a tool reaches only the caller's household. destructiveHint is true where a call deletes data or
 * overwrites text the user typed (remove_items, merge_items, update_item, the renames), replaces
 * a store's whole order (set_store_order, set_store_layout) or overwrites an item's store,
 * category or hand-placed position (move_item, place_item, job 432: moving resets the position),
 * false for additive writes and for ticking; clients ask the user
 * before a destructive call. idempotentHint is false where a repeat adds again.
 */
export const toolAnnotations = {
  list_households: {
    title: 'List Households',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_lists: {
    title: 'List Shopping Lists',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_items: {
    title: 'List Items',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  get_item: {
    title: 'Get Item',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_categories: {
    title: 'List Categories',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_stores: {
    title: 'List Stores',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  list_recent: {
    title: 'List Recent Items',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  suggest_items: {
    title: 'Suggest Items',
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  add_items: {
    title: 'Add Items',
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
  },
  tick_items: {
    title: 'Check Off Items',
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  untick_items: {
    title: 'Uncheck Items',
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  move_item: {
    title: 'Move Item',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  update_item: {
    title: 'Update Item',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  remove_items: {
    title: 'Remove Items',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  merge_items: {
    title: 'Merge Items',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: false,
    openWorldHint: false,
  },
  place_item: {
    title: 'Reorder Item',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  set_store_order: {
    title: 'Set Item Order in Store',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  create_list: {
    title: 'Create List',
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
  },
  rename_list: {
    title: 'Rename List',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  add_store: {
    title: 'Add Store',
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
  rename_store: {
    title: 'Rename Store',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  set_store_layout: {
    title: 'Set Store Aisle Order',
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
} as const satisfies Record<McpTool, ToolAnnotations & { title: string }>;

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
            error: 'plan_required',
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
  'Name of the item on the list (e.g. "Milch") or its id; an id finds it without "list" ' +
    'on any list of the household',
);
const storeName = storedText.min(1).max(60).describe(
  'A store of the household (list_stores), e.g. "dm", "Lidl" or a custom one like "Rewe"',
);
const categoryName = storedText.min(1).max(60).describe(
  'Category, e.g. "Obst & Gemüse" or "Kühlregal"',
);
const householdRef = storedText.min(1).max(80).optional().describe(
  'Household (list_households): its id or name. Without it, the default household.',
);
const listRef = storedText.min(1).max(60).optional().describe(
  'List of the household (list_lists): its id or exact name. Without it, the default list.',
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
    { name: 'snacklist', title: 'Snacklist', version: '1.7.0' },
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
    title: toolAnnotations.list_households.title,
    description: 'Lists the households the user belongs to, with member counts. "default" ' +
      'marks the default household, which the other tools use when "household" is omitted. ' +
      "With an access key, only that key's household.",
    annotations: toolAnnotations.list_households,
    // Ungated: it lists only the user's own households, so a locked default can still find an
    // unlocked one.
  }, () => call('list_households', null, undefined, (tx) => households(tx, auth))());

  server.registerTool('list_lists', {
    title: toolAnnotations.list_lists.title,
    description:
      'Lists the household\'s shopping lists in their order. "default" marks the user\'s default ' +
      'list, which the other tools use when "list" is omitted (Siri and Alexa too); without a ' +
      'choice in the app, that is the first list.',
    inputSchema: z.object({ household: householdRef }),
    annotations: toolAnnotations.list_lists,
  }, ({ household }) => call('list_lists', once, household, (tx, h) => listLists(tx, h))());

  server.registerTool(
    'list_items',
    {
      title: toolAnnotations.list_items.title,
      description: 'Shows the open items on the shopping list with brand and properties. ' +
        '"order" in the answer says how it is sorted: "walk" (learned order) means store by ' +
        'store in the order of the stores, then the items without a store, each in walking-route ' +
        'order; "aisle" means in the aisle order of the categories and, within a category, in ' +
        'walking-route order. "position" is an item\'s place in its store (or under "no store"), ' +
        'starting at 1. With "store", only what can be bought in that store (its items plus all ' +
        'items without a store), in the order of that store. With "category", only one category. ' +
        '"counts" always covers the whole list, even with a filter: "open" open items, ' +
        '"checkedLast24h" items ticked off in the last 24 hours. "list" in the answer names the ' +
        'list shown.',
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
      title: toolAnnotations.add_items.title,
      description:
        'Puts one or more items on the list. The name is split: "Windeln Pampers Größe 3" → ' +
        'name "Windeln", brand "Pampers", properties "Größe 3"; "2 Gurken" → name "Gurken", ' +
        'quantity "2". What is given in "quantity", "brand" or "properties" replaces the split ' +
        "value. Each item is assigned a category automatically; the household's corrections " +
        '(move_item or in the app) apply first, then a dictionary. Without "store", it gets the ' +
        'store where it was last bought, otherwise the store of a store brand (Balea → dm), or ' +
        'dm for drugstore items. What is already on the list ("Gurke" = "2 Gurken"; another size ' +
        'or brand is a different item) is not added twice and is reported under "alreadyOnList". ' +
        'If another spelling or a synonym is already on the list ("Karotten" and "Möhren"), the ' +
        'item is still added and reported under "similarOnList" (added: the new name, onList: at ' +
        'most three of the open items, total: how many there are); this means something similar ' +
        'is already on the list. Nothing is merged automatically; if the user wants it, ' +
        'merge_items (keep: the item from onList, merge: the new one) merges both like "Merge" ' +
        'in the app.',
      annotations: toolAnnotations.add_items,
      inputSchema: z.object({
        items: z.array(z.object({
          name: storedText.min(1).max(120).describe('What should be bought, e.g. "Milch"'),
          quantity: storedText.max(40).optional().describe('Quantity, e.g. "2" or "500 g"'),
          brand: storedText.max(60).optional().describe('Brand, e.g. "Pampers" or "Ja!"'),
          properties: storedText.max(120).optional().describe(
            'Properties, comma-separated, e.g. "Größe 3, Big Pack" or "1,5 %"',
          ),
          category: categoryName.optional().describe(
            'Give only if the user explicitly names a category; it is remembered like a correction',
          ),
          store: storeName.optional().describe(
            'Give only if it should be in a specific store',
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
      title: toolAnnotations.tick_items.title,
      description:
        'Ticks off one or more items as bought; they disappear from the list and appear under ' +
        '"Recently used". Items that are not found or already ticked off are reported under ' +
        '"notFound", so a second call changes nothing.',
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
      title: toolAnnotations.untick_items.title,
      description: 'Puts ticked-off items back on the list. A name finds the most recently ' +
        'ticked-off item of that name on the list, unless it is already open there; an id finds ' +
        'it on any list of the household without "list". Items that are not found or still open ' +
        'are reported under "notFound", so a second call changes nothing.',
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
      title: toolAnnotations.move_item.title,
      description:
        'Changes the category and/or the store of an item. With learned order (list_items ' +
        '"order": "walk"), it takes its place in the new store; otherwise it goes to the end of ' +
        'its new group in the walking route. The household remembers both: the same item lands ' +
        'in this category and this store the next time it is added. store: null removes the ' +
        'store (the item can then be bought in any store) and deletes every ' +
        'store the household remembered for this item and how often. The item itself is not ' +
        'deleted and keeps its name, brand, properties and quantity, but the call overwrites ' +
        'its previous store and category. Moving it back to a store that already has a ' +
        'remembered place restores that place; it does not restore the other stores it ' +
        'remembered or how often.',
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
      title: toolAnnotations.place_item.title,
      description:
        'Puts an open item directly before ("before") or after ("after") another one, e.g. ' +
        '"the eggs after the flour"; give exactly one of the two. With learned order ' +
        '(list_items "order": "walk"), the other item must be in the same store, including when ' +
        'both have no store (move_item changes the store). Nothing is deleted in learned order; ' +
        'only a manual walk position is written. In categories / aisle mode the item takes the ' +
        'store and category of the other one, as when dragging in the app. Only when that other ' +
        "item has no store does this remove the item's store, and then it deletes every store " +
        'the household remembered for this item and how often (as move_item with store: null). ' +
        'Category memory and walk-order positions are not deleted. A second identical call ' +
        'changes nothing. The item itself is not deleted. To undo it, place the item next to ' +
        'its old neighbour (learned order) or move it back with move_item and place it again.',
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
      title: toolAnnotations.set_store_order.title,
      description:
        'Sets the order in which a store\'s open items appear on the list, e.g. "this is how I ' +
        'walk through IKEA: …". The items named move to the front in that order; the store\'s ' +
        'other items keep their order behind them. Every item named must be open and in this ' +
        'store. Only with learned order (list_items "order": "walk"); otherwise use place_item ' +
        "for single items. Returns the store's open items in the new order; a second identical " +
        'call changes nothing.',
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
      title: toolAnnotations.update_item.title,
      description:
        'Changes an open item like "Edit" in the app: only the fields given. quantity, brand ' +
        'or properties null (or empty) deletes them. category and store work as in move_item, ' +
        'including that store: null removes the store (the item can then be bought in any ' +
        'store) and deletes every store the household remembered for this item and how often. ' +
        'Moving it back to a store that already has a remembered place restores that place; it ' +
        'does not restore the other stores it remembered or how often. With learned order, the ' +
        'item takes its place in the new store. "toList" moves it to another list ' +
        '(list_lists); "list" says where it is now. If an identical open item (name, brand, ' +
        'properties) is already on the list after the change, nothing changes and the call ' +
        'reports it.',
      inputSchema: z.object({
        item: itemRef,
        name: storedText.trim().min(1).max(120).optional().describe(
          'New name, e.g. "Hafermilch"',
        ),
        quantity: storedText.max(40).nullable().optional().describe(
          'Quantity, e.g. "2" or "500 g"',
        ),
        brand: storedText.max(60).nullable().optional().describe('Brand, e.g. "Pampers"'),
        properties: storedText.max(120).nullable().optional().describe(
          'Properties, comma-separated, e.g. "Größe 3, Big Pack"',
        ),
        category: categoryName.optional(),
        store: storeName.nullable().optional(),
        toList: storedText.min(1).max(60).optional().describe(
          'List the item moves to (list_lists): its id or exact name',
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
      title: toolAnnotations.remove_items.title,
      description: 'Deletes open items from the list without ticking them off (they do not ' +
        'appear under "Recently used"). What the household has learned about them (category, ' +
        'store) is kept, except what adding them taught when they are removed within 10 minutes ' +
        'of being added. Items that are not found are reported under "notFound", so a second ' +
        "call changes nothing. Only at the user's explicit request.",
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
      title: toolAnnotations.get_item.title,
      description: 'Shows an item with its status ("open" or "ticked") and the time it was ' +
        'added. An id also finds it when ticked off; a name only among the open items.',
      inputSchema: z.object({ item: itemRef, household: householdRef, list: listRef }),
      annotations: toolAnnotations.get_item,
    },
    ({ item, household, list }) =>
      call('get_item', once, household, (tx, h) => getItem(tx, h, item, list))(),
  );

  server.registerTool(
    'merge_items',
    {
      title: toolAnnotations.merge_items.title,
      description: 'Merges two open items like "Merge" in the app, for example after ' +
        '"similarOnList" from add_items when the user wants it: "keep" stays with its name, the ' +
        'quantities are added ("2" and "3" → "5"), a missing brand or properties come from ' +
        '"merge", which is deleted. Both must be on the same list. Answer: "kept" as it is now, ' +
        '"merged" as the deleted one was.',
      inputSchema: z.object({
        keep: itemRef.describe(
          'The item that stays, usually the one from "onList" of similarOnList (name or id)',
        ),
        merge: itemRef.describe(
          'The item that is absorbed into "keep", usually the newly added one (name or id)',
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
      title: toolAnnotations.list_categories.title,
      description: 'Lists the household\'s categories in aisle order. With "store", in the ' +
        'walking-route order of that store (like list_items with "store"); "hidden" marks ' +
        'categories that the store does not carry.',
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
    title: toolAnnotations.list_recent.title,
    description: 'Shows what was ticked off last, like "Recently used" in the app: newest ' +
      'first, each thing once (its last purchase), nothing that is open on the list again. ' +
      '"tickedAt" is the time it was ticked off. With untick_items (id), an item comes back ' +
      'onto the list.',
    inputSchema: z.object({
      limit: z.number().int().min(1).max(50).optional().describe(
        `At most how many, ${RECENT_SHOWN} if omitted`,
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
      title: toolAnnotations.suggest_items.title,
      description: 'What the household often buys, like the suggestions in the app: often and ' +
        'recently bought first, nothing that is currently open on a list. With "prefix", only ' +
        'names that begin with it, then names with a word that begins with it. "uses": on how ' +
        'many days in the last year; "due": its usual interval since the last purchase has ' +
        'passed, so it will probably be needed soon.',
      inputSchema: z.object({
        prefix: storedText.max(60).optional().describe('Beginning of the name, e.g. "Mil"'),
        limit: z.number().int().min(1).max(50).optional().describe(
          'At most how many, 10 if omitted',
        ),
        due: z.boolean().optional().describe(
          'Only what is due (like "Due again" in the app), even if it is not among the first ' +
            '"limit". Anyone who wants to know what is due sets this to true.',
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
    const listName = storedText.trim().min(1).max(60).describe('Name of the list, e.g. "Baumarkt"');
    const storeNew = storedText.trim().min(1).max(40).describe(
      'Name of the store, only the name, e.g. "Rewe" or "Wochenmarkt"',
    );

    server.registerTool('create_list', {
      title: toolAnnotations.create_list.title,
      description: 'Creates a new shopping list at the end of the lists, as in the app. At ' +
        "most 50 lists per household. Only at the user's explicit request.",
      inputSchema: z.object({ name: listName, household: householdRef }),
      annotations: toolAnnotations.create_list,
    }, ({ name, household }) =>
      call('create_list', once, household, async (tx, h) => {
        const { id, name: created } = await createList(tx, h, name);
        return { id, name: created };
      })());

    server.registerTool('rename_list', {
      title: toolAnnotations.rename_list.title,
      description: 'Renames a shopping list. A second call changes nothing.',
      inputSchema: z.object({
        list: storedText.min(1).max(60).describe(
          'The list (list_lists): its id or exact name',
        ),
        name: listName.describe('New name of the list'),
        household: householdRef,
      }),
      annotations: toolAnnotations.rename_list,
    }, ({ list, name, household }) =>
      call('rename_list', once, household, async (tx, h) => {
        const { id, name: renamed } = await changeList(tx, h, list, { name });
        return { id, name: renamed };
      })());

    server.registerTool('add_store', {
      title: toolAnnotations.add_store.title,
      description: 'Creates a store, as in the app. Only the name, not a retail chain. If the ' +
        'name already exists (upper and lower case and umlauts do not matter), it answers with ' +
        'that store and "created": false. At most 50 stores per household.',
      inputSchema: z.object({ name: storeNew, household: householdRef }),
      annotations: toolAnnotations.add_store,
    }, ({ name, household }) =>
      call('add_store', once, household, async (tx, h) => {
        const { store, created } = await addStore(tx, h, name);
        return { id: store.id, name: store.name, created };
      })());

    server.registerTool('rename_store', {
      title: toolAnnotations.rename_store.title,
      description: 'Renames a store. If another store already has that name, nothing changes ' +
        'and the call reports it.',
      inputSchema: z.object({
        store: storeName,
        name: storeNew.describe('New name of the store, only the name'),
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
        title: toolAnnotations.set_store_layout.title,
        description:
          'Sets the order in which the categories come in a store (the walking route, as in ' +
          'the app under the store). "categories": those named first, in this order, the others ' +
          'after them in their previous order. "hidden": all categories that the store does not ' +
          'carry; if omitted, they stay as they are. With learned order (list_items "order": ' +
          '"walk"), the walking route is only the starting order for new items; place_item and ' +
          'set_store_order set the order of the items in the store. Answer: the whole walking ' +
          'route (like list_categories with "store").',
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
    title: toolAnnotations.list_stores.title,
    description: "Lists the household's stores.",
    inputSchema: z.object({ household: householdRef }),
    annotations: toolAnnotations.list_stores,
  }, ({ household }) => call('list_stores', once, household, (tx, h) => stores(tx, h))());

  return server;
}
