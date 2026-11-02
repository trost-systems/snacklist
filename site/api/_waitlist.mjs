// The browser's side of the waitlist (docs/WAITLIST.md, "Browser to Vercel"): forwards to the
// edge function, which owns all logic. Nothing here logs an address, a token, a body or an IP.
import { createHmac } from 'node:crypto';

const BODY_LIMIT = 2048;

const answer = (status, text, headers = {}) =>
  new Response(text, { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });
const json = (status, body, headers) => answer(status, JSON.stringify(body), headers);
const invalid = () => json(400, { error: 'invalid_request' });

async function readText(request) {
  if (Number(request.headers.get('content-length') ?? 0) > BODY_LIMIT) return null;
  const chunks = [];
  let size = 0;
  for await (const chunk of request.body ?? []) {
    size += chunk.byteLength;
    if (size > BODY_LIMIT) return null;
    chunks.push(chunk);
  }
  return new TextDecoder().decode(Buffer.concat(chunks));
}

function parseObject(text) {
  try {
    const value = JSON.parse(text);
    return typeof value === 'object' && value !== null && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

// Sniffs the body instead of trusting content-type: RFC 8058 senders post a form, our page JSON.
function unsubscribeBody(text, url) {
  if (new URLSearchParams(text).get('List-Unsubscribe') === 'One-Click') {
    const id = url.searchParams.get('id');
    const sig = url.searchParams.get('s');
    return id && sig ? { id, sig } : null;
  }
  const body = parseObject(text);
  return body && { id: body.id, sig: body.sig };
}

// One IPv6 client usually holds a whole /64, so it counts as one key.
export function clientNetwork(ip) {
  if (!ip.includes(':')) return ip;
  const [head, tail = ''] = ip.split('::');
  const left = head ? head.split(':') : [];
  const right = tail ? tail.split(':') : [];
  const groups = ip.includes('::') ? [...left, ...Array(8 - left.length - right.length).fill('0'), ...right] : left;
  return `${groups.slice(0, 4).map((g) => parseInt(g || '0', 16).toString(16)).join(':')}::/64`;
}

function clientKey(request, secret, now) {
  const ip = request.headers.get('x-real-ip') ?? request.headers.get('x-forwarded-for')?.split(',')[0].trim() ?? '';
  return createHmac('sha256', secret).update(`${now.toISOString().slice(0, 10)}|${clientNetwork(ip)}`).digest('hex');
}

function origin(request) {
  const host = request.headers.get('host') ?? new URL(request.url).host;
  return `${/^(127\.0\.0\.1|localhost):\d+$/.test(host) ? 'http' : 'https'}://${host}`;
}

const forward = (path, read) => async (request, { env, fetch, now, timeoutMs }) => {
  const text = await readText(request);
  const body = text === null ? null : read(text, new URL(request.url));
  if (!body) return invalid();
  const secret = env.WAITLIST_PROXY_SECRET;
  try {
    const res = await fetch(`${env.WAITLIST_UPSTREAM_URL.replace(/\/+$/, '')}/${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-waitlist-proxy-secret': secret,
        'x-waitlist-client': clientKey(request, secret, now),
        'x-waitlist-origin': origin(request),
        'x-region': 'eu-central-1',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const answerText = await res.text();
    JSON.parse(answerText);
    return answer(res.status, answerText);
  } catch {
    return json(503, { error: 'unavailable' });
  }
};

// Mail links land here; the page sends the values only when its button is pressed.
function unsubscribePage(request) {
  const params = new URL(request.url).searchParams;
  const id = params.get('id');
  const sig = params.get('s');
  if (!id || !sig) return invalid();
  const page = params.get('l') === 'en' ? '/en/waitlist/unsubscribe' : '/de/warteliste/abmelden';
  return answer(303, null, { location: `${page}#id=${encodeURIComponent(id)}&s=${encodeURIComponent(sig)}` });
}

const ROUTES = {
  signup: { POST: forward('signup', parseObject) },
  confirm: { POST: forward('confirm', parseObject) },
  unsubscribe: { POST: forward('unsubscribe', unsubscribeBody), GET: unsubscribePage },
};

export async function handle(route, request, { env, fetch, now, timeoutMs = 10_000 }) {
  const methods = ROUTES[route];
  let res;
  if (!env.WAITLIST_UPSTREAM_URL || !env.WAITLIST_PROXY_SECRET) res = json(404, { error: 'not_found' });
  else if (!methods[request.method]) res = json(405, { error: 'method_not_allowed' }, { allow: Object.keys(methods).join(', ') });
  else res = await methods[request.method](request, { env, fetch, now, timeoutMs });
  console.log(`waitlist ${route} ${res.status}`);
  return res;
}
