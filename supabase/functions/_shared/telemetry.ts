// Error tracking and server-side analytics events for the edge functions, sent to PostHog EU
// (docs/ANALYTICS.md). Off without POSTHOG_PROJECT_API_KEY; only https://eu.i.posthog.com is
// accepted as POSTHOG_HOST. An exception carries the function name, its message reduced to the
// runtime's own template words and code locations: never the request body, headers, tokens or
// item text. Events pass an allow-list.
//
// Use: `Deno.serve(withTelemetry('voice', handler))`. Errors a handler catches itself go through
// `telemetry.exception(e)`; the wrapper sends everything queued before the response returns, and
// what an event stream queues when it ends.
import { discardUnreadBody } from './http.ts';

export const posthogEuHost = 'https://eu.i.posthog.com';

export interface Env {
  get(key: string): string | undefined;
}

type Fetch = typeof fetch;

interface Config {
  key: string;
  host: string;
  /** Events from this deployment count as internal (local proofs, the test project). */
  internal: boolean;
}

/** Event name to its allowed properties, each a check on the value. Server events only. */
export type Rule = (value: unknown) => boolean;

const oneOf = (...values: string[]): Rule => (v) => typeof v === 'string' && values.includes(v);
const matches = (re: RegExp): Rule => (v) => typeof v === 'string' && re.test(v);
const amount: Rule = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v < 10_000;
const uuid = matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
const intIn = (min: number, max: number): Rule => (v) =>
  typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max;

const revenue = {
  product_id: matches(/^[a-z0-9_.]{1,64}$/),
  price: amount,
  currency: matches(/^[A-Z]{3}$/),
  app_store: oneOf('apple', 'google'),
  country: matches(/^[A-Z]{2}$/),
  net_amount: amount,
  transaction_ref: matches(/^[0-9a-f]{32}$/),
  // Job 49: which Snacklist Premium product the event is about. Promotional grants send no events.
  premium_source: oneOf('yearly', 'lifetime'),
} satisfies Record<string, Rule>;

/** The MCP server's tools (mcp/tools.ts), the only names mcp_tool_call may carry. */
export const mcpTools = [
  'list_households',
  'list_lists',
  'list_items',
  'add_items',
  'tick_items',
  'move_item',
  'update_item',
  'remove_items',
  'untick_items',
  'get_item',
  'merge_items',
  'place_item',
  'set_store_order',
  'list_categories',
  'list_stores',
  'list_recent',
  'suggest_items',
  'create_list',
  'rename_list',
  'add_store',
  'rename_store',
  'set_store_layout',
] as const;

export type McpTool = typeof mcpTools[number];

/**
 * The events a function may send (docs/ANALYTICS.md, "Purchases"). Adding one: list it here,
 * with a rule per property, and add a case to telemetry_test.ts.
 */
export const serverEventCatalog: Record<string, Record<string, Rule>> = {
  'purchase_completed': revenue,
  'purchase_refunded': revenue,
  'purchase_restored': { product_id: revenue.product_id, app_store: revenue.app_store },
  // Job 31: an item added over Alexa, the app's item_added with source alexa; once per added
  // item, never for one already on the list. Never the name.
  'item_added': {
    source: oneOf('alexa'),
    actor_role: oneOf('owner', 'member'),
    household_size: intIn(1, 100),
  },
  // Job 51: one per Siri add or read through the voice function, native (the app's Siri
  // credential) or the Shortcut (a PAT). count is how many items, never which.
  'siri_add': {
    result: oneOf('success', 'fail'),
    reason: oneOf(
      'added',
      'nothing_added',
      'no_text',
      'too_long',
      'nothing_understood',
      'server',
      'no_household',
    ),
    language: oneOf('en', 'de'),
    source: oneOf('native', 'shortcut'),
    count: intIn(0, 30),
  },
  'siri_read': {
    result: oneOf('success', 'fail'),
    reason: oneOf('read', 'server', 'no_household'),
    language: oneOf('en', 'de'),
    source: oneOf('native', 'shortcut'),
    count: intIn(0, 10_000),
  },
  // Job 50: a household without Snacklist Premium used an integration while the lock is on (at
  // most once an hour per household and integration, _shared/premium.ts). Never what was said.
  // Siri (job 184) and Alexa (job 72) stay free, so they are never blocked; the API (job 73) is.
  'integration_blocked': { integration: oneOf('mcp', 'api') },
  // Job 195 (F5): one per MCP tools/call, for a caller whose newest consent answer is yes. The tool
  // is one of mcpTools; never its arguments, an item, a store or a household name.
  'mcp_tool_call': {
    tool: oneOf(...mcpTools),
    result: oneOf('success', 'fail'),
    reason: oneOf('done', 'tool_error', 'premium_required', 'server'),
  },
  // Job 195 (F5): one per API request the key, its scope and the household's access let through,
  // before it runs. Only the route's scope; never the token, its hint, the route or the body.
  'api_key_used': { scope: oneOf('read', 'write') },
};

/** Properties every server event carries besides its own. */
const contextRules: Record<string, Rule> = {
  'distinct_id': uuid,
  'install_id': uuid,
  'household_id': (v) => v === null || uuid(v),
  'event_id': uuid,
  platform: oneOf('server'),
  'app_version': oneOf('server'),
  'is_internal': (v) => typeof v === 'boolean',
  '$geoip_disable': (v) => v === true,
  '$process_person_profile': (v) => v === false,
  $lib: oneOf('snacklist-edge'),
};

export class RefusedEvent extends Error {}

/** Throws [RefusedEvent] (naming the property, never the value) unless all is allowed. */
export function checkServerEvent(event: string, properties: Record<string, unknown>): void {
  const rules = serverEventCatalog[event];
  if (!rules) throw new RefusedEvent(`unknown event ${event}`);
  for (const [key, value] of Object.entries(properties)) {
    const rule = rules[key] ?? contextRules[key];
    if (!rule) throw new RefusedEvent(`${event} does not carry ${key}`);
    if (!rule(value)) throw new RefusedEvent(`${event}.${key} has a value its rule refuses`);
  }
}

/** Where an event goes: an install that said yes in the app, and its household. */
export interface Subject {
  installId: string;
  householdId: string | null;
  /** The install is internal (app/lib/analytics/internal.dart); the deployment's flag also counts. */
  internal?: boolean;
}

export class Telemetry {
  #queue: Record<string, unknown>[] = [];

  constructor(
    readonly fn: string,
    readonly config: Config | null,
    readonly fetchImpl: Fetch = fetch,
  ) {}

  get enabled(): boolean {
    return this.config !== null;
  }

  /** Queued, unsent events; for tests. */
  get queued(): readonly Record<string, unknown>[] {
    return this.#queue;
  }

  /** Queues [error] for PostHog error tracking, tagged with the function name. */
  exception(error: unknown, { handled = true }: { handled?: boolean } = {}): void {
    if (!this.config) return;
    try {
      const id = crypto.randomUUID();
      this.#queue.push({
        event: '$exception',
        uuid: id,
        timestamp: new Date().toISOString(),
        properties: {
          distinct_id: `edge-function-${this.fn}`,
          event_id: id,
          function_name: this.fn,
          platform: 'server',
          is_internal: this.config.internal,
          $exception_level: 'error',
          $exception_list: exceptionList(error, handled),
          $geoip_disable: true,
          $process_person_profile: false,
          $lib: 'snacklist-edge',
        },
      });
    } catch (e) {
      // Reporting an error must never raise one.
      console.error(`${this.fn}: exception not captured`, (e as Error)?.name);
    }
  }

  /** Queues a server event for [subject]; refuses anything the catalog does not allow. */
  event(event: string, subject: Subject, properties: Record<string, unknown>): boolean {
    if (!this.config) return false;
    const id = crypto.randomUUID();
    const all = {
      ...properties,
      'distinct_id': subject.installId,
      'install_id': subject.installId,
      'household_id': subject.householdId,
      'event_id': id,
      platform: 'server',
      'app_version': 'server',
      'is_internal': this.config.internal || subject.internal === true,
      '$geoip_disable': true,
      '$process_person_profile': false,
      $lib: 'snacklist-edge',
    };
    try {
      checkServerEvent(event, all);
    } catch (e) {
      console.error(`${this.fn}: ${(e as Error).message}`);
      return false;
    }
    this.#queue.push({ event, uuid: id, timestamp: new Date().toISOString(), properties: all });
    return true;
  }

  /** Sends what is queued; never throws. Bounded, so a slow PostHog never holds a response. */
  async flush(timeoutMs = 3_000): Promise<void> {
    if (!this.config || this.#queue.length === 0) return;
    const batch = this.#queue.splice(0);
    try {
      const response = await this.fetchImpl(`${this.config.host}/batch/`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ api_key: this.config.key, batch }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      await response.body?.cancel();
      if (!response.ok) console.error(`${this.fn}: telemetry answered ${response.status}`);
    } catch (e) {
      console.error(`${this.fn}: telemetry not sent`, (e as Error)?.name);
    }
  }
}

/** PostHog's project key shape; a personal key (phx_) is never accepted. */
export const projectKeyLike = (key: string): boolean => /^phc_[A-Za-z0-9_-]{8,64}$/.test(key);

/** Telemetry for function [fn] from the environment; disabled without a valid key and host. */
export function telemetryFor(fn: string, env: Env = Deno.env, fetchImpl: Fetch = fetch): Telemetry {
  const key = env.get('POSTHOG_PROJECT_API_KEY') ?? '';
  const host = env.get('POSTHOG_HOST') ?? '';
  if (!projectKeyLike(key) || host !== posthogEuHost) {
    if (key) console.error(`${fn}: telemetry off, the key or host is not accepted`);
    return new Telemetry(fn, null, fetchImpl);
  }
  return new Telemetry(
    fn,
    { key, host, internal: env.get('ANALYTICS_INTERNAL') === 'true' },
    fetchImpl,
  );
}

/**
 * Wraps a function's handler: an exception it does not catch is reported and answered with 500,
 * a request body it left unread is read to its end first (discardUnreadBody), and whatever the
 * request queued is sent before the response returns.
 */
export function withTelemetry(
  fn: string,
  handler: (req: Request) => Response | Promise<Response>,
  telemetry: Telemetry = telemetryFor(fn),
): (req: Request) => Promise<Response> {
  return async (req) => {
    let response: Response;
    try {
      response = await handler(req);
    } catch (e) {
      console.error(`${fn}: unhandled`, e);
      telemetry.exception(e, { handled: false });
      response = new Response(JSON.stringify({ error: 'server' }), {
        status: 500,
        headers: { 'content-type': 'application/json; charset=utf-8' },
      });
    }
    await discardUnreadBody(req);
    await telemetry.flush();
    return flushAtEnd(response, telemetry);
  };
}

/**
 * An event stream (the mcp function's SSE) is still being written when the handler returns, and
 * what it queues meanwhile is sent when it ends. Any other answer is returned untouched, so it
 * keeps its Content-Length.
 */
function flushAtEnd(response: Response, telemetry: Telemetry): Response {
  const streamed = response.headers.get('content-type')?.startsWith('text/event-stream');
  // The type first: reading `body` makes a finished answer a stream, and it goes out chunked.
  if (!streamed || !response.body) return response;
  const body = response.body.pipeThrough(new TransformStream({ flush: () => telemetry.flush() }));
  return new Response(body, response);
}

// ---------------------------------------------------------------------------------------------
// The exception, as PostHog's $exception_list wants it.

const runtimeErrors = [TypeError, RangeError, ReferenceError, SyntaxError, EvalError, URIError];

/** A runtime error's first line reduced to its shape; a code for anything else. */
export function scrubMessage(error: unknown): string {
  if (runtimeErrors.some((t) => error instanceof t)) {
    const [first = ''] = String((error as Error).message ?? '').split('\n');
    return shape(scrub(first)).slice(0, 120);
  }
  const code = (error as { code?: unknown } | null)?.code ??
    (error as { status?: unknown } | null)?.status;
  const text = typeof code === 'number' ? String(code) : code;
  return typeof text === 'string' && /^[A-Za-z0-9_.:-]{1,64}$/.test(text) ? text : '<redacted>';
}

const scrub = (text: string) =>
  text
    .replace(/[a-z][a-z0-9+.-]*:\/\/\S+/gi, '<url>')
    .replace(/[^\s@]+@[^\s@]+/g, '<email>')
    .replace(/"[^"]*"|'[^']*'|„[^“”]*[“”]|“[^”]*”|‘[^’]*’|«[^»]*»|`[^`]*`/g, '<redacted>')
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '<uuid>')
    .replace(/[0-9]{6,}/g, '<n>');

/**
 * Words of V8's and Deno's own error templates. Any other word came from a value (an item, a
 * name, a key) and becomes <w>, so `cannot parse Hafermilch` reads `cannot <w>`.
 */
const templateWords = new Set(
  `a abort aborted access already an and argument arguments array assignment async at await been
  before between bigint body bounds buffer call called cannot character class code column
  constant constructor convert create date decode declared deep defined detached digits element
  empty encode end error exceeded expected explicit expression extensible failed fetch field
  flags fraction frozen function generator getter has in index initial initialization input
  instance invalid is iterable iterator json keyword left length line literal locked malformed
  maximum member method missing mix mode must network new non not null number object of offset
  on only or out position precision primitive private promise properties property radix range
  read reading recursion redefine reduce regular request reserved response right sealed set
  setter setting side size stack strict stream string super symbol the this time timed to token
  too type types undefined unexpected unterminated uri use used valid value variable with without
  writable`.split(/\s+/),
);

const marker = /^<(?:url|email|redacted|uuid|n)>$/;

const shape = (text: string) =>
  text
    .replace(/<[a-z]+>|[\p{L}\p{N}_$]+(?:\.[\p{L}\p{N}_$]+)*/gu, (word) => {
      if (marker.test(word)) return word;
      if (/^\p{N}+$/u.test(word)) return '<n>';
      return templateWords.has(word.toLowerCase()) ? word : '<w>';
    })
    .replace(/<w>(?:\s*<w>)+/g, '<w>');

function exceptionList(error: unknown, handled: boolean): Record<string, unknown>[] {
  const type = error instanceof Error ? error.name || error.constructor.name : typeof error;
  const frames = error instanceof Error ? framesOf(error.stack ?? '') : [];
  return [{
    type: /^[A-Za-z0-9_$.]{1,64}$/.test(type) ? type : 'Error',
    value: scrubMessage(error),
    mechanism: { handled, synthetic: frames.length === 0, type: 'generic' },
    ...(frames.length ? { stacktrace: { type: 'raw', frames } } : {}),
  }];
}

const v8Frame = /^\s*at (?:(.+?) \()?(.+?):(\d+):(\d+)\)?$/;

/** V8 frames, crash site last; files relative to the functions directory, no device paths. */
export function framesOf(stack: string): Record<string, unknown>[] {
  const frames: Record<string, unknown>[] = [];
  for (const line of stack.split('\n').slice(1, 81)) {
    const m = v8Frame.exec(line);
    if (!m) continue;
    const [, fn, file = '', lineno, colno] = m;
    const path = file.replace(/^file:\/\//, '').replace(/[?#].*$/, '');
    const inFunctions = path.match(/\/functions\/(.+)$/)?.[1];
    const filename = inFunctions ?? path.split('/').pop() ?? '';
    frames.push({
      platform: 'node:javascript',
      filename,
      abs_path: filename,
      function: fn ? fn.slice(0, 200) : '<anonymous>',
      lineno: Number(lineno),
      colno: Number(colno),
      in_app: inFunctions !== undefined && !inFunctions.includes('node_modules'),
    });
  }
  return frames.reverse();
}
