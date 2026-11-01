// The MCP server: one per request, bound to the authenticated caller.
import { type CallToolResult, McpServer } from '@modelcontextprotocol/server';
import { z } from 'zod';
import type { Auth } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import { asUser, type Tx } from '../_shared/db.ts';
import { addItems, categories, listItems, moveItem, stores, tickItems, ToolError } from './list.ts';

const INSTRUCTIONS = `Hummlist: die gemeinsame Einkaufsliste eines Haushalts (deutsch).
Einträge haben einen Namen (z. B. "Windeln"), optional eine Marke ("Pampers"), Eigenschaften
("Größe 3, Big Pack"), eine Menge ("2", "500 g"), eine Kategorie (Gang im Laden, z. B.
"Kühlregal") und optional einen Laden (z. B. "dm"). Neue Einträge werden automatisch zerlegt und
einsortiert; gib eine Kategorie nur an, wenn der Nutzer sie ausdrücklich nennt.
Einträge, Kategorien und Läden lassen sich per Name (ungefähr, ohne Umlaute) oder per id angeben.
Abgehakte Einträge verschwinden aus der Liste.`;

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
    const [tag, ...params] = part.trim().toLowerCase().split(';');
    const q = Number(params.find((p) => p.trim().startsWith('q='))?.trim().slice(2) ?? 1);
    return { lang: tag.split('-')[0], q: Number.isFinite(q) ? q : 0, i };
  }).filter((r) => (r.lang === 'de' || r.lang === 'en') && r.q > 0)
    .sort((a, b) => b.q - a.q || a.i - b.i);
  return ranked[0]?.lang === 'en' ? 'en' : 'de';
}

/** Whether the caller's household may use the tools; asked once per request, on the first call. */
export type Gate = () => Promise<Access>;

/**
 * A tool body: runs as the caller in one transaction once the household may use MCP; ToolErrors
 * become tool-level errors. A failing check throws, like any database error.
 */
function run(auth: Auth, gate: Gate, lang: Lang, body: (tx: Tx) => Promise<unknown>) {
  return async (): Promise<CallToolResult> => {
    if (await gate() === 'locked') {
      return { isError: true, content: [{ type: 'text', text: premiumRequired[lang] }] };
    }
    try {
      const result = await asUser(auth.userId, body);
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      return { isError: true, content: [{ type: 'text', text: e.message }] };
    }
  };
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

export function buildServer(auth: Auth, gate: Gate, lang: Lang = 'de'): McpServer {
  const server = new McpServer(
    { name: 'hummlist', title: 'Hummlist', version: '1.0.0' },
    { instructions: INSTRUCTIONS },
  );
  const h = auth.householdId;
  let access: Promise<Access> | undefined;
  const once: Gate = () => (access ??= gate());

  server.registerTool('list_items', {
    title: 'Einkaufsliste anzeigen',
    description: 'Zeigt die offenen Einträge der Einkaufsliste mit Marke und Eigenschaften, in ' +
      'Gang-Reihenfolge und innerhalb einer Kategorie in der Laufweg-Reihenfolge des Haushalts. Mit "store" ' +
      'nur, was in diesem Laden gekauft werden kann (seine Einträge plus alle ohne Laden), in der ' +
      'Reihenfolge dieses Ladens. Mit "category" nur eine Kategorie.',
    inputSchema: z.object({ store: storeName.optional(), category: categoryName.optional() }),
    annotations: { readOnlyHint: true },
  }, (args) => run(auth, once, lang, (tx) => listItems(tx, h, args))());

  server.registerTool('add_items', {
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
    }),
  }, ({ items }) => run(auth, once, lang, (tx) => addItems(tx, h, items))());

  server.registerTool('tick_items', {
    title: 'Einträge abhaken',
    description:
      'Hakt einen oder mehrere Einträge als gekauft ab; sie verschwinden von der Liste und ' +
      'landen unter "Zuletzt verwendet". Nicht gefundene oder schon abgehakte Einträge werden ' +
      'unter "notFound" gemeldet, ein zweiter Aufruf ändert also nichts.',
    inputSchema: z.object({ items: z.array(itemRef).min(1).max(50) }),
    annotations: { destructiveHint: false, idempotentHint: true },
  }, ({ items }) => run(auth, once, lang, (tx) => tickItems(tx, h, items))());

  server.registerTool('move_item', {
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
    }),
    annotations: { idempotentHint: true },
  }, (args) => run(auth, once, lang, (tx) => moveItem(tx, h, args))());

  server.registerTool('list_categories', {
    title: 'Kategorien anzeigen',
    description: 'Listet die Kategorien des Haushalts in Gang-Reihenfolge.',
    annotations: { readOnlyHint: true },
  }, () => run(auth, once, lang, (tx) => categories(tx, h))());

  server.registerTool('list_stores', {
    title: 'Läden anzeigen',
    description: 'Listet die Läden des Haushalts.',
    annotations: { readOnlyHint: true },
  }, () => run(auth, once, lang, (tx) => stores(tx, h))());

  return server;
}
