// The MCP server: one per request, bound to the authenticated caller.
import { type CallToolResult, McpServer } from '@modelcontextprotocol/server';
import { z } from 'zod';
import type { Auth } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import { asUser, type Tx } from '../_shared/db.ts';
import {
  addItems,
  categories,
  listItems,
  moveItem,
  stores,
  tickItems,
  ToolError,
} from '../_shared/list.ts';

const INSTRUCTIONS = `Hummlist: die gemeinsame Einkaufsliste eines Haushalts (deutsch).
Einträge haben einen Namen (z. B. "Windeln"), optional eine Marke ("Pampers"), Eigenschaften
("Größe 3, Big Pack"), eine Menge ("2", "500 g"), eine Kategorie (Gang im Laden, z. B.
"Kühlregal") und optional einen Laden (z. B. "dm"). Neue Einträge werden automatisch zerlegt und
einsortiert; gib eine Kategorie nur an, wenn der Nutzer sie ausdrücklich nennt.
Einträge, Kategorien und Läden lassen sich per Name (ungefähr, ohne Umlaute) oder per id angeben.
Abgehakte Einträge verschwinden aus der Liste.
Wer in mehreren Haushalten ist, findet sie mit list_households; die Listen-Werkzeuge nehmen dann
"household" (id oder Name), ohne Angabe gilt der Standardhaushalt.`;

/**
 * Job 50: what a tool call of a household without Hummlist Premium gets while the lock is on. A
 * tool result, not a 401/403: the client keeps its token and needs no new sign-in once the
 * household unlocks. PLACEHOLDER copy (Spec #4); the final text comes from Hummlist Launch.
 */
export const premiumRequired: Record<Lang, string> = {
  de:
    'Dieser Haushalt braucht Hummlist Premium für den Zugang über KI-Assistenten. Schalte es in ' +
    'der Hummlist-App frei. Es wurde nichts gelesen oder geändert.',
  en: 'This household needs Hummlist Premium for AI assistant access. Unlock it in the Hummlist ' +
    'app. Nothing was read or changed.',
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

/**
 * A tool body: runs as the caller in one transaction once the household (the [household]
 * argument, else the one the credential acts in) may use MCP; ToolErrors become tool-level
 * errors. A failing check throws, like any database error. A null [gate] is no check.
 */
function run(
  auth: Auth,
  gate: Gate | null,
  lang: Lang,
  household: string | undefined,
  body: (tx: Tx, household: string) => Promise<unknown>,
) {
  return async (): Promise<CallToolResult> => {
    try {
      const h = household === undefined
        ? auth.householdId
        : await asUser(auth.userId, (tx) => householdNamed(tx, auth, household));
      if (gate && await gate(h) === 'locked') {
        return { isError: true, content: [{ type: 'text', text: premiumRequired[lang] }] };
      }
      const result = await asUser(auth.userId, (tx) => body(tx, h));
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      return { isError: true, content: [{ type: 'text', text: e.message }] };
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

const itemRef = z.string().min(1).max(120).describe(
  'Name des Eintrags auf der Liste (z. B. "Milch") oder seine id',
);
const storeName = z.string().min(1).max(60).describe(
  'Ein Laden des Haushalts (list_stores), z. B. "dm", "Lidl" oder ein eigener wie "Rewe"',
);
const categoryName = z.string().min(1).max(60).describe(
  'Kategorie, z. B. "Obst & Gemüse" oder "Kühlregal"',
);
const householdRef = z.string().min(1).max(80).optional().describe(
  'Haushalt (list_households): seine id oder sein Name. Ohne Angabe der Standardhaushalt.',
);

export function buildServer(auth: Auth, gate: Gate, lang: Lang = 'de'): McpServer {
  const server = new McpServer(
    { name: 'hummlist', title: 'Hummlist', version: '1.0.0' },
    { instructions: INSTRUCTIONS },
  );
  const asked = new Map<string, Promise<Access>>();
  const once: Gate = (household) => {
    const known = asked.get(household);
    if (known) return known;
    const access = gate(household);
    asked.set(household, access);
    return access;
  };

  server.registerTool('list_households', {
    title: 'Haushalte anzeigen',
    description: 'Listet die Haushalte, in denen der Nutzer ist, mit Mitgliederzahl. "default" ' +
      'markiert den Standardhaushalt, in dem die anderen Werkzeuge ohne "household" arbeiten. ' +
      'Mit einem Zugriffstoken nur dessen Haushalt.',
    annotations: { readOnlyHint: true },
    // Ungated: it lists only the user's own households, so a locked default can still find an
    // unlocked one.
  }, () => run(auth, null, lang, undefined, (tx) => households(tx, auth))());

  server.registerTool(
    'list_items',
    {
      title: 'Einkaufsliste anzeigen',
      description: 'Zeigt die offenen Einträge der Einkaufsliste mit Marke und Eigenschaften, in ' +
        'Gang-Reihenfolge und innerhalb einer Kategorie in der Laufweg-Reihenfolge des Haushalts. Mit "store" ' +
        'nur, was in diesem Laden gekauft werden kann (seine Einträge plus alle ohne Laden), in der ' +
        'Reihenfolge dieses Ladens. Mit "category" nur eine Kategorie. "counts" gilt immer für die ' +
        'ganze Liste, auch mit Filter: "open" offene Einträge, "checkedLast24h" in den letzten 24 ' +
        'Stunden abgehakte.',
      inputSchema: z.object({
        store: storeName.optional(),
        category: categoryName.optional(),
        household: householdRef,
      }),
      annotations: { readOnlyHint: true },
    },
    ({ household, ...args }) =>
      run(auth, once, lang, household, (tx, h) => listItems(tx, h, args))(),
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
        '"similarOnList" gemeldet (added: der neue Name, onList: die offenen Einträge); sag dem Nutzer ' +
        'dann, dass etwas Ähnliches schon auf der Liste steht. Zusammengeführt wird nichts.',
      inputSchema: z.object({
        items: z.array(z.object({
          name: z.string().min(1).max(120).describe('Was gekauft werden soll, z. B. "Milch"'),
          quantity: z.string().max(40).optional().describe('Menge, z. B. "2" oder "500 g"'),
          brand: z.string().max(60).optional().describe('Marke, z. B. "Pampers" oder "Ja!"'),
          properties: z.string().max(120).optional().describe(
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
      }),
    },
    ({ items, household }) => run(auth, once, lang, household, (tx, h) => addItems(tx, h, items))(),
  );

  server.registerTool(
    'tick_items',
    {
      title: 'Einträge abhaken',
      description:
        'Hakt einen oder mehrere Einträge als gekauft ab; sie verschwinden von der Liste und ' +
        'landen unter "Zuletzt verwendet". Nicht gefundene oder schon abgehakte Einträge werden ' +
        'unter "notFound" gemeldet, ein zweiter Aufruf ändert also nichts.',
      inputSchema: z.object({ items: z.array(itemRef).min(1).max(50), household: householdRef }),
      annotations: { destructiveHint: false, idempotentHint: true },
    },
    ({ items, household }) =>
      run(auth, once, lang, household, (tx, h) => tickItems(tx, h, items))(),
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
      }),
      annotations: { idempotentHint: true },
    },
    ({ household, ...args }) =>
      run(auth, once, lang, household, (tx, h) => moveItem(tx, h, args))(),
  );

  server.registerTool('list_categories', {
    title: 'Kategorien anzeigen',
    description: 'Listet die Kategorien des Haushalts in Gang-Reihenfolge.',
    inputSchema: z.object({ household: householdRef }),
    annotations: { readOnlyHint: true },
  }, ({ household }) => run(auth, once, lang, household, (tx, h) => categories(tx, h))());

  server.registerTool('list_stores', {
    title: 'Läden anzeigen',
    description: 'Listet die Läden des Haushalts.',
    inputSchema: z.object({ household: householdRef }),
    annotations: { readOnlyHint: true },
  }, ({ household }) => run(auth, once, lang, household, (tx, h) => stores(tx, h))());

  return server;
}
