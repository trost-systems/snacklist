// POST /functions/v1/voice {"text": "Milch, zwei Gurken und Klopapier"}
// Splits the sentence, adds the items to the caller's list and answers with a German
// sentence for Siri to speak. `?format=text` answers with that sentence as plain text.
// {"text": ..., "mode": "parse"} only splits; the app adds the items itself. With "split": true
// (job 111, the app since then) each item also comes back with the brand, details and store
// public.parse_item reads, as add_item stores them; without it, the answer stays as it was.
// Job 51: "lang": "en" answers in English (native Siri), "mode": "read" reads the open items, and
// a request that names a lang gets `outcome` in every JSON answer, which the native client
// branches on. Requests without lang (the Shortcut recipe) get the answers they always got.
// Job 169b: the app's session may name the household it shows ("household": id); it must be a
// member. Without it the default household, as older apps get; Siri and token callers always act
// in their credential's household.
// Job 207: an add goes to the list `list` names (an id or a spoken name) or the text ends with
// ("Luftballons zur Geburtstag Liste"), else to the caller's default list there; an unknown or
// ambiguous name adds to the default list and says so. Every add answer names the list in `list`.
import { AuthError, type Scope, type Via } from '../_shared/auth.ts';
import { corsHeaders, json, preflight } from '../_shared/http.ts';
import type { ListCatalog } from '../_shared/list.ts';
import {
  namesList,
  takeListPhrase,
  type Target,
  targetOf,
  wishOf,
} from '../_shared/spoken_list.ts';
import { scrubMessage } from '../_shared/telemetry.ts';
import { copy, type FailureCode, type Lang, readLimit } from './copy.ts';
import { maxItems, type ParsedItem, parseSentence } from './parse.ts';
import { parseEnglish } from './parse_en.ts';

export interface Caller {
  userId: string;
  householdId: string;
  /** How the caller signed in; events go only to Siri (siri) and Shortcut (pat) calls. */
  via?: Via;
  /** A personal key's scopes (job 397): adding needs `write`. Absent for other credentials. */
  scopes?: readonly Scope[];
}

/** A heard item split like a typed one (public.parse_item): "Windeln", "Pampers", "Größe 3". */
export interface SplitItem extends ParsedItem {
  /** Marke the server's parser found, e.g. "Pampers". */
  brand: string | null;
  /** Eigenschaften, comma-separated, e.g. "Größe 3, Big Pack". */
  properties: string | null;
  /** The store add_item would pick (remembered, the brand's, drugstore items to dm), by id. */
  storeId: string | null;
  /** The category the insert trigger will pick (classify_item), by id, so the app shows the row there at once (job 150). */
  categoryId: string | null;
}

export interface Added extends Omit<SplitItem, 'storeId' | 'categoryId'> {
  /** The category the classifier picked, by name. */
  category: string;
  /** True when the item was active already and nothing was added. */
  alreadyOnList: boolean;
  /**
   * Open items that are another spelling or a synonym of this new one ("Möhren" for
   * "Karotten"), or the same name with other details ("Butter gesalzen" for "Butter"), by name
   * with brand and details; it was added anyway (job 32b). Empty when there are none.
   */
  similarOnList: string[];
  /**
   * The request as heard when this open item has the same name with its own brand or details
   * ("Butter" with "Butter Weihenstephan" open): nothing was added, and a yes adds it
   * (`addVariants`). Null otherwise.
   */
  held?: ParsedItem | null;
}

export interface Deps<C extends Caller = Caller> {
  /** Resolves the bearer token; throws an AuthError when it can't. */
  authenticate(req: Request): Promise<C>;
  /** Whether the caller is a member of the household a session request names (job 169b). */
  isMember(caller: C, householdId: string): Promise<boolean>;
  /** The household's lists and the caller's default one, for mode add (job 207). */
  lists(caller: C): Promise<ListCatalog>;
  /**
   * Adds to the list [options.list] (an id from `lists`); `addVariants`: the yes to a question,
   * held items are added as said (items.ts).
   */
  addItems(
    caller: C,
    items: ParsedItem[],
    options: { addVariants?: boolean; list: string },
  ): Promise<Added[]>;
  /** Splits brand, details and store off each item as add_item does, for mode parse. */
  splitItems(caller: C, items: ParsedItem[]): Promise<SplitItem[]>;
  /** The household's open items in the app's order, for mode read. */
  readItems?(caller: C): Promise<ParsedItem[]>;
  /** Sends a siri_add or siri_read event when the caller's analytics consent allows it. */
  track?(caller: C, event: VoiceEvent): Promise<void>;
  /** Error tracking for a failure answered with 500 (telemetry.ts); scrubbed there. */
  report?(error: unknown): void;
  /** Writes the one request line (requestLine) to the function log; console.log by default. */
  log?(line: string): void;
}

export const maxTextLength = 1000;

const statuses: Record<FailureCode, number> = {
  method: 405,
  unauthorized: 401,
  read_only: 403,
  no_household: 403,
  no_text: 400,
  too_long: 413,
  nothing_understood: 422,
  server: 500,
};

/** What the native Siri client branches on; the failure codes are also `error`. */
export type Outcome = 'added' | 'nothing_added' | 'parsed' | 'read' | FailureCode;

/** A reply's outcome; `confirm` only for a client that said it can ask (`ask`). */
type ReplyOutcome = Outcome | 'confirm';

/** A server event for a Siri add or read (docs/ANALYTICS.md); never a name or text. */
export type VoiceEvent = {
  event: 'siri_add' | 'siri_read';
  result: 'success' | 'fail';
  reason: Outcome;
  language: Lang;
  source: 'native' | 'shortcut';
  /** Items understood (add) or open (read). */
  count: number;
};

const parsers: Record<Lang, (text: string, limit: number) => ParsedItem[]> = {
  de: parseSentence,
  en: parseEnglish,
};

/** How an added item is read back: "2 l Milch", "Windeln Pampers Größe 3 Big Pack". */
export const said = (item: Added, lang: Lang = 'de') =>
  [copy[lang].spoken(item), item.brand, item.properties?.replaceAll(', ', ' ')].filter(Boolean)
    .join(' ');

/**
 * The confirmation Siri speaks, one sentence per outcome: "Hinzugefügt: Karotten. Schon auf der
 * Liste: Möhren, Milch." The open ones are the exact items, then the other spellings or synonyms
 * of new ones (job 32b, added anyway), each name once. A [target] other than the default list is
 * named, after why when a named list was not found (job 207).
 */
export function confirmation(results: Added[], lang: Lang = 'de', target?: Target): string {
  const say = copy[lang];
  const where = namesList(target) ? say.listName(target.list) : null;
  const added = results.filter((r) => !r.alreadyOnList);
  const open = [
    ...new Set([
      ...results.filter((r) => r.alreadyOnList).map((item) => said(item, lang)),
      ...added.flatMap((r) => r.similarOnList ?? []),
    ]),
  ];
  return [
    target?.kind === 'unknown' || target?.kind === 'ambiguous'
      ? say.notFound(target.kind, target.said)
      : '',
    added.length ? say.added(added.map((item) => said(item, lang)), where) : '',
    open.length ? say.existing(open, where) : '',
  ].filter(Boolean).join(' ');
}

/**
 * Q79: the yes/no question when held items ("Butter" with "Butter Weihenstephan" open) are in the
 * results, null otherwise: what was done, then "Butter Weihenstephan steht schon drauf. Soll ich
 * Butter trotzdem dazuschreiben?". The held items' spoken text, to resend on a yes, is `again`.
 */
export function question(
  results: Added[],
  lang: Lang = 'de',
  target?: Target,
): { question: string; again: string } | null {
  const held = results.filter((r) => r.held);
  if (!held.length) return null;
  const say = copy[lang];
  const wanted = held.map((r) => say.spoken(r.held!));
  return {
    question: [
      confirmation(results.filter((r) => !r.held), lang, target),
      say.ask(held.map((item) => said(item, lang)), wanted),
    ].filter(Boolean).join(' '),
    again: wanted.join(', '),
  };
}

interface Body {
  text: string | null;
  mode: 'add' | 'parse' | 'read';
  lang: Lang;
  /** Mode parse also splits brand, details and store (job 111); older apps don't ask. */
  split: boolean;
  /**
   * The request named a lang (the native client always does): its answers carry `outcome`.
   * Without one (the Shortcut recipe) they stay exactly as before job 51.
   */
  tagged: boolean;
  /** Q79: the client can ask a yes/no question (`"ask": true`, native Siri only). */
  ask: boolean;
  /** Q79: this is the yes to that question (`"confirmed": true`). */
  confirmed: boolean;
  /** Job 169b: the household the app shows, for session callers; null: the default. */
  household: string | null;
  /** Job 207: the list to add to, an id or a spoken name; null: as the text says, else the default. */
  list: string | null;
}

const modes = ['add', 'parse', 'read'] as const;

/**
 * Accepts JSON {"text", "mode", "lang", "list"} (list: a list id or name, job 207), a JSON
 * string, or a plain-text body.
 */
async function readBody(req: Request): Promise<Body> {
  const raw = await req.text();
  const plain = {
    mode: 'add',
    lang: 'de',
    tagged: false,
    split: false,
    ask: false,
    confirmed: false,
    household: null,
    list: null,
  } as const;
  if (!(req.headers.get('content-type') ?? '').includes('json')) return { ...plain, text: raw };
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed === 'string') return { ...plain, text: parsed };
    const { text, mode, lang, split, ask, confirmed, household, list } = (parsed ?? {}) as {
      text?: unknown;
      household?: unknown;
      list?: unknown;
      mode?: unknown;
      lang?: unknown;
      split?: unknown;
      ask?: unknown;
      confirmed?: unknown;
    };
    const tagged = lang !== undefined;
    return {
      text: typeof text === 'string' ? text : null,
      mode: modes.find((m) => m === mode) ?? 'add',
      lang: lang === 'en' ? 'en' : 'de',
      tagged,
      split: split === true,
      ask: tagged && ask === true,
      confirmed: tagged && confirmed === true,
      household: typeof household === 'string' ? household : null,
      list: typeof list === 'string' ? list : null,
    };
  } catch {
    return { ...plain, text: null };
  }
}

const sources: Partial<Record<Via, VoiceEvent['source']>> = { siri: 'native', pat: 'shortcut' };

/** What one request did, for its log line; never the text or a name. */
export interface RequestFacts {
  /** How the caller signed in, `none` when that failed, `-` before it was tried. */
  via: Via | 'none' | '-';
  mode: Body['mode'] | '-';
  lang: Lang | '-';
  /**
   * The `x-snacklist-client` header (`x-hummlist-client` from installed Hummlist builds, kept until
   * R1): which app build and intent sent it ("ios-1210.AddItems").
   */
  client: string | null;
  outcome: ReplyOutcome | '-';
  status: number;
  /** Items understood (add, parse) or open (read). */
  count: number;
  /** Which list an add went to, by kind (Target): never its name or id. */
  target: Target['kind'] | '-';
  ms: number;
}

/** The client header as one token: our apps send "ios-1210.AddItems"; anything else is `other`. */
const clientToken = (value: string | null) =>
  value === null ? '-' : /^[A-Za-z0-9._-]{1,40}$/.test(value) ? value : 'other';

/**
 * `voice: <via> <mode> <lang> client=<client> -> <outcome> status=<n> count=<n> target=<kind>
 * ms=<n>`, the only line a request logs (docs/SIRI_SHORTCUT.md, "Request log"). Text, names,
 * tokens and ids never go in.
 */
export const requestLine = (f: RequestFacts) =>
  `voice: ${f.via} ${f.mode} ${f.lang} client=${
    clientToken(f.client)
  } -> ${f.outcome} status=${f.status} count=${f.count} target=${f.target} ms=${f.ms}`;

export function createHandler<C extends Caller>(deps: Deps<C>) {
  const log = deps.log ?? ((line: string) => console.log(line));
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    const facts: RequestFacts = {
      via: '-',
      mode: '-',
      lang: '-',
      client: req.headers.get('x-snacklist-client') ?? req.headers.get('x-hummlist-client'),
      outcome: '-',
      status: 0,
      count: 0,
      target: '-',
      ms: 0,
    };
    const started = performance.now();
    try {
      const response = await handle(req, facts);
      facts.status = response.status;
      return response;
    } catch (e) {
      // withTelemetry answers a throw with 500.
      facts.status = 500;
      throw e;
    } finally {
      facts.ms = Math.round(performance.now() - started);
      log(requestLine(facts));
    }
  };

  async function handle(req: Request, facts: RequestFacts): Promise<Response> {
    const asText = new URL(req.url).searchParams.get('format') === 'text';

    const reply = (status: number, body: { speech: string } & Record<string, unknown>) => {
      if (!asText) return json(body, { status, headers: authHeader(status) });
      return new Response(body.speech, {
        status,
        headers: {
          ...corsHeaders,
          ...authHeader(status),
          'content-type': 'text/plain; charset=utf-8',
        },
      });
    };
    if (req.method !== 'POST') {
      return reply(405, { error: 'method', speech: copy.de.failures.method });
    }
    const body = await readBody(req);
    facts.mode = body.mode;
    facts.lang = body.lang;
    const say = copy[body.lang];
    const send = (
      status: number,
      { outcome, ...rest }: { outcome: ReplyOutcome; speech: string } & Record<string, unknown>,
    ) => {
      facts.outcome = outcome;
      return reply(status, body.tagged ? { outcome, ...rest } : rest);
    };
    const fail = (error: FailureCode) =>
      send(statuses[error], { outcome: error, error, speech: say.failures[error] });

    let caller: C;
    try {
      caller = await deps.authenticate(req);
    } catch (e) {
      facts.via = 'none';
      if (e instanceof AuthError) return fail(e.status === 403 ? 'no_household' : 'unauthorized');
      console.error('voice: authenticate failed', errorShape(e));
      deps.report?.(e);
      return fail('server');
    }

    facts.via = caller.via ?? '-';
    // Job 213: OAuth tokens belong to MCP and AI-assistant clients, which the integration lock
    // puts behind Premium; voice stays free, so it must not be their side door.
    if (caller.via === 'oauth') return fail('unauthorized');
    if (caller.via === 'session' && body.household !== null) {
      try {
        if (!await deps.isMember(caller, body.household)) return fail('no_household');
      } catch (e) {
        console.error('voice: the membership check failed', errorShape(e));
        deps.report?.(e);
        return fail('server');
      }
      caller = { ...caller, householdId: body.household.toLowerCase() };
    }
    const source = caller.via && sources[caller.via];
    const track = async (event: VoiceEvent['event'], reason: Outcome, count: number) => {
      facts.count = count;
      if (!source || !deps.track) return;
      const result = ['added', 'nothing_added', 'read'].includes(reason) ? 'success' : 'fail';
      try {
        await deps.track(caller, { event, result, reason, language: body.lang, source, count });
      } catch (e) {
        console.error('voice: event not recorded', errorShape(e));
      }
    };

    if (body.mode === 'read') {
      try {
        if (!deps.readItems) throw new Error('voice: no list reader');
        const open = await deps.readItems(caller);
        await track('siri_read', 'read', open.length);
        const items = open.map(({ name, quantity }) => ({ name, quantity }));
        const speech = say.listing(items.slice(0, readLimit).map(say.spoken), items.length);
        return send(200, { outcome: 'read', speech, items, total: items.length });
      } catch (e) {
        console.error('voice: reading the list failed', errorShape(e));
        deps.report?.(e);
        await track('siri_read', 'server', 0);
        return fail('server');
      }
    }

    // A failing split must not fail dictation: the items go back as heard, as older apps get them.
    const splitOrHeard = async (items: ParsedItem[]) => {
      try {
        return await deps.splitItems(caller, items);
      } catch (e) {
        console.error('voice: splitting items failed', errorShape(e));
        deps.report?.(e);
        return items;
      }
    };

    const adding = body.mode === 'add';
    if (adding && caller.scopes && !caller.scopes.includes('write')) return fail('read_only');
    const refuse = async (error: FailureCode, count = 0) => {
      if (adding) await track('siri_add', error, count);
      return fail(error);
    };
    const text = body.text?.trim();
    if (!text) return refuse('no_text');
    if (text.length > maxTextLength) return refuse('too_long');
    let catalog: ListCatalog | null = null;
    if (adding) {
      try {
        catalog = await deps.lists(caller);
      } catch (e) {
        console.error('voice: reading the lists failed', errorShape(e));
        deps.report?.(e);
        return refuse('server');
      }
    }
    // The list phrase leaves the text whenever it is there; the `list` field wins over it.
    const phrase = catalog ? takeListPhrase(text, body.lang, catalog.lists) : { text, said: null };
    const heard = parsers[body.lang](phrase.text, maxItems + 1);
    if (!heard.length) return refuse('nothing_understood');
    const items = heard.slice(0, maxItems);
    const truncated = heard.length > maxItems;
    const cut = truncated ? ` ${say.tooMany}` : '';

    // Without the lists this is mode parse: the app adds the items itself.
    if (!catalog) {
      facts.count = items.length;
      return send(200, {
        outcome: 'parsed',
        speech: say.parsed(items.map(say.spoken)) + cut,
        items: body.split ? await splitOrHeard(items) : items,
        truncated,
      });
    }

    const target = targetOf(catalog, wishOf(body.list?.trim() ? body.list : phrase.said));
    facts.target = target.kind;
    try {
      const list = target.list.id;
      const added = await deps.addItems(caller, items, { addVariants: body.confirmed, list });
      const outcome = added.some((a) => !a.alreadyOnList) ? 'added' : 'nothing_added';
      await track('siri_add', outcome, items.length);
      // The speech is the answer for a no, a timeout and every client that cannot ask.
      const ask = body.ask ? question(added, body.lang, target) : null;
      return send(200, {
        outcome: ask ? 'confirm' : outcome,
        speech: confirmation(added, body.lang, target) + cut,
        ...(ask && { question: ask.question + cut, again: ask.again }),
        // `held` is the server's: the items keep the shape the Shortcut and older apps read.
        items: added.map(({ held: _, ...item }) => item),
        truncated,
        // The list used: a yes to the question resends its id as `list` (Q79 lands there too).
        list: { id: list, name: target.list.name },
      });
    } catch (e) {
      console.error('voice: adding items failed', errorShape(e));
      deps.report?.(e);
      return refuse('server', items.length);
    }
  }
}

/** An error for the function log: its type and scrubbed message, never an item name. */
const errorShape = (e: unknown) => `${(e as Error)?.name ?? typeof e}: ${scrubMessage(e)}`;

const authHeader = (status: number): Record<string, string> =>
  status === 401 ? { 'www-authenticate': 'Bearer' } : {};
