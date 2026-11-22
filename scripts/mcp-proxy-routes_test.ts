// mcp-proxy/vercel.json decides per request whether mcp.snacklist.app shows the page for people
// (mcp-proxy/public) or forwards to the mcp function, and forwards all of api.snacklist.app to the
// api function. This replays real browser and MCP client
// requests through its rewrites the way Vercel's router reads them: the filesystem first, then
// the first rewrite whose source, `has` and `missing` match. Vercel does not document whether a
// `value` regex must match the whole header, so every case runs both ways and must agree.
// Usage: deno test --config scripts/deno.json --allow-read scripts/mcp-proxy-routes_test.ts
import { assert, assertEquals } from '@std/assert';

interface Condition {
  type: 'header' | 'host';
  key?: string;
  value?: string;
}

interface Rewrite {
  source: string;
  destination: string;
  has?: Condition[];
  missing?: Condition[];
}

type Anchoring = 'whole value' | 'substring';

const proxyDir = new URL('../mcp-proxy/', import.meta.url);
interface HeaderRule {
  source: string;
  has?: Condition[];
  headers: { key: string; value: string }[];
}

const config: {
  outputDirectory: string;
  cleanUrls: boolean;
  rewrites: Rewrite[];
  headers: HeaderRule[];
} = JSON.parse(
  Deno.readTextFileSync(new URL('vercel.json', proxyDir)),
);
const publicDir = new URL(`${config.outputDirectory}/`, proxyDir);
const fn = 'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp';
const apiFn = 'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api';

function sourceMatches(source: string, path: string): boolean {
  if (source === '/:path*' || source === '/(.*)') return true;
  assert(!source.includes(':'), `this test reads literal sources and /:path* only, not ${source}`);
  return source === path;
}

function holds(
  condition: Condition,
  headers: Headers,
  anchoring: Anchoring,
  host: string,
): boolean {
  if (condition.type === 'host') {
    assert(condition.value !== undefined, 'host conditions need a value');
    const pattern = anchoring === 'whole value' ? `^(?:${condition.value})$` : condition.value;
    return new RegExp(pattern).test(host);
  }
  assertEquals(condition.type, 'header', 'this test reads header and host conditions only');
  assert(condition.key !== undefined, 'header conditions need a key');
  const value = headers.get(condition.key);
  if (value === null) return false;
  if (condition.value === undefined) return true;
  const pattern = anchoring === 'whole value' ? `^(?:${condition.value})$` : condition.value;
  return new RegExp(pattern).test(value);
}

function staticFile(path: string): string | undefined {
  const name = path.slice(1) + (config.cleanUrls && !path.includes('.') ? '.html' : '');
  try {
    return Deno.statSync(new URL(name, publicDir)).isFile ? name : undefined;
  } catch {
    return undefined;
  }
}

const DEFAULT_HOST = 'mcp.snacklist.app';
// Kept until R1: clients set up before the rename still connect through the old host.
const OLD_HOST = 'mcp.hummlist.com';
const API_HOST = 'api.snacklist.app';

function forwardedDestination(destination: string, path: string): string {
  return destination.replace(':path*', path.slice(1));
}

/** What Vercel serves for a request: `public/<file>` or the function URL it forwards to. */
function route(
  path: string,
  init: Record<string, string>,
  anchoring: Anchoring,
  host = DEFAULT_HOST,
): string {
  const headers = new Headers(init);
  const own = staticFile(path);
  if (own !== undefined) return `public/${own}`;
  for (const rule of config.rewrites) {
    if (!sourceMatches(rule.source, path)) continue;
    if (!(rule.has ?? []).every((c) => holds(c, headers, anchoring, host))) continue;
    if ((rule.missing ?? []).some((c) => holds(c, headers, anchoring, host))) continue;
    if (rule.destination.startsWith('https://')) {
      return forwardedDestination(rule.destination, path).replace(
        /\?via=(?:mcp-hummlist|mcp-snacklist|api-snacklist)$/,
        '',
      );
    }
    const file = staticFile(rule.destination);
    assert(file !== undefined, `${rule.destination} has no file in ${config.outputDirectory}/`);
    return `public/${file}`;
  }
  return 'no route';
}

const chrome = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,' +
  'image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';
const firefox = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
const safari = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
const mcpAccept = 'application/json, text/event-stream';

const cases: [string, string, Record<string, string>, string][] = [
  ['Chrome, German first', '/', { accept: chrome, 'accept-language': 'de-DE,de;q=0.9,en;q=0.8' }, 'public/de.html'],
  ['Safari, de only', '/', { accept: safari, 'accept-language': 'de' }, 'public/de.html'],
  ['Firefox, English', '/', { accept: firefox, 'accept-language': 'en-US,en;q=0.5' }, 'public/en.html'],
  ['English first, German second', '/', { accept: chrome, 'accept-language': 'en-GB,de;q=0.8' }, 'public/en.html'],
  ['French: the English page', '/', { accept: chrome, 'accept-language': 'fr-FR,fr;q=0.9' }, 'public/en.html'],
  ['no Accept-Language', '/', { accept: chrome }, 'public/en.html'],
  ['a language merely starting with "de"', '/', { accept: chrome, 'accept-language': 'dexx' }, 'public/en.html'],
  ['the language switch, /en', '/en', { accept: chrome, 'accept-language': 'de' }, 'public/en.html'],
  ['the language switch, /de', '/de', { accept: chrome }, 'public/de.html'],
  [
    'MCP initialize POST',
    '/',
    { accept: mcpAccept, 'content-type': 'application/json', 'mcp-protocol-version': '2025-11-25' },
    fn,
  ],
  ['initialize POST without a protocol header', '/', { accept: mcpAccept, 'content-type': 'application/json' }, fn],
  ['POST that also accepts HTML', '/', { accept: `text/html, ${mcpAccept}`, 'content-type': 'application/json' }, fn],
  [
    'JSON POST from a client that accepts HTML but not SSE',
    '/',
    { accept: 'application/json, text/html', 'content-type': 'application/json' },
    fn,
  ],
  ['GET for the SSE stream', '/', { accept: 'text/event-stream', authorization: 'Bearer t' }, fn],
  ['GET accepting HTML and SSE', '/', { accept: 'text/html, text/event-stream' }, fn],
  ['GET with a token', '/', { accept: chrome, authorization: 'Bearer t' }, fn],
  ['GET with an MCP session', '/', { accept: chrome, 'mcp-session-id': 's' }, fn],
  ['GET with an MCP protocol version', '/', { accept: chrome, 'mcp-protocol-version': '2025-11-25' }, fn],
  ['curl default', '/', { accept: '*/*' }, fn],
  ['no Accept', '/', {}, fn],
  [
    'protected resource metadata in a browser',
    '/.well-known/oauth-protected-resource',
    { accept: chrome },
    `${fn}/.well-known/oauth-protected-resource`,
  ],
  [
    'authorization server metadata in a browser',
    '/.well-known/openid-configuration',
    { accept: chrome },
    `${fn}/.well-known/openid-configuration`,
  ],
  ['/mcp in a browser', '/mcp', { accept: chrome }, `${fn}/mcp`],
];

for (const anchoring of ['whole value', 'substring'] as const) {
  for (const [name, path, headers, want] of cases) {
    Deno.test(`${name} (${anchoring} regex): ${path} → ${want}`, () => {
      assertEquals(route(path, headers, anchoring), want);
    });
  }
}

function rewriteDestination(
  path: string,
  init: Record<string, string>,
  host: string,
): string {
  const headers = new Headers(init);
  for (const rule of config.rewrites) {
    if (!sourceMatches(rule.source, path)) continue;
    if (!(rule.has ?? []).every((c) => holds(c, headers, 'whole value', host))) continue;
    if ((rule.missing ?? []).some((c) => holds(c, headers, 'whole value', host))) continue;
    if (rule.destination.startsWith('https://')) {
      return forwardedDestination(rule.destination, path);
    }
  }
  return 'no route';
}

Deno.test('each host forwards to the function with its own via marker', () => {
  for (
    const [host, marker] of [[DEFAULT_HOST, 'mcp-snacklist'], [OLD_HOST, 'mcp-hummlist']] as const
  ) {
    for (
      const [path, headers] of [
        ['/.well-known/oauth-protected-resource', { accept: chrome }],
        ['/', { accept: '*/*' }],
        ['/mcp', { accept: chrome }],
      ] as const
    ) {
      const dest = rewriteDestination(path, headers, host);
      assert(dest.endsWith(`?via=${marker}`), `${host} ${path} → ${dest}`);
    }
  }
});

const apiCases: [string, string, Record<string, string>, string][] = [
  ['list items', '/v1/items', { accept: 'application/json', authorization: 'Bearer fgp_x' }, `${apiFn}/v1/items`],
  ['tick an item', '/v1/items/abc/tick', { 'content-type': 'application/json' }, `${apiFn}/v1/items/abc/tick`],
  ['the root in a German browser', '/', { accept: chrome, 'accept-language': 'de-DE,de;q=0.9' }, `${apiFn}/`],
  ['the root from curl', '/', { accept: '*/*' }, `${apiFn}/`],
  ['/de: the page file, filesystem first on every host', '/de', { accept: chrome }, 'public/de.html'],
  [
    'the MCP metadata path',
    '/.well-known/oauth-protected-resource',
    { accept: chrome },
    `${apiFn}/.well-known/oauth-protected-resource`,
  ],
];

for (const anchoring of ['whole value', 'substring'] as const) {
  for (const [name, path, headers, want] of apiCases) {
    Deno.test(`${API_HOST}: ${name} (${anchoring} regex): ${path} → ${want}`, () => {
      assertEquals(route(path, headers, anchoring, API_HOST), want);
    });
  }
}

Deno.test(`${API_HOST} forwards to the api function with its via marker`, () => {
  for (const [, path, headers] of apiCases) {
    const dest = rewriteDestination(path, headers, API_HOST);
    assert(dest.startsWith(`${apiFn}/`), `${path} → ${dest}`);
    assert(dest.endsWith('?via=api-snacklist'), `${path} → ${dest}`);
  }
});

Deno.test('no request on the MCP hosts reaches the api function', () => {
  for (const host of [DEFAULT_HOST, OLD_HOST]) {
    for (const [, path, headers] of [...cases, ...apiCases]) {
      const dest = rewriteDestination(path, headers, host);
      assert(!dest.startsWith(apiFn), `${host} ${path} → ${dest}`);
    }
  }
});

Deno.test('Vercel caches no rewritten response, on any host', () => {
  for (const host of [DEFAULT_HOST, OLD_HOST, API_HOST]) {
    for (const path of ['/', '/v1/items', '/.well-known/oauth-protected-resource']) {
      const set = config.headers
        .filter((rule) => sourceMatches(rule.source, path))
        .filter((rule) =>
          (rule.has ?? []).every((c) => holds(c, new Headers(), 'whole value', host))
        )
        .flatMap((rule) => rule.headers);
      assert(
        set.some((h) => h.key === 'x-vercel-enable-rewrite-caching' && h.value === '0'),
        `${host} ${path}`,
      );
    }
  }
});

Deno.test('a browser still gets the page on either host', () => {
  for (const host of [DEFAULT_HOST, OLD_HOST]) {
    assertEquals(
      route('/', { accept: chrome, 'accept-language': 'de' }, 'whole value', host),
      'public/de.html',
    );
    assertEquals(
      route('/', { accept: chrome, 'accept-language': 'en' }, 'whole value', host),
      'public/en.html',
    );
  }
});

Deno.test('each page is noindex in its own language', () => {
  for (const lang of ['de', 'en']) {
    const html = Deno.readTextFileSync(new URL(`${lang}.html`, publicDir));
    assert(html.includes(`<html lang="${lang}"`), `${lang}.html: lang="${lang}"`);
    assert(/<meta name="robots" content="noindex/.test(html), `${lang}.html: robots noindex`);
  }
});
