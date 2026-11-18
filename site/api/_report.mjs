// The browser's side of the DSA notice form (job 275): forwards a report to the edge function
// `report`, next to the waitlist's on the same project and with the same proxy secret. The edge
// function owns validation and storage. Nothing here logs or forwards a body or an IP; the
// limiter keeps the client's network in memory for an hour at most.
import { answer, clientNetwork, json, parseObject, readText } from './_waitlist.mjs';

const BODY_LIMIT = 64 * 1024;

// Requests per client network in a rolling window. The map stays bounded: a sweep drops
// networks with no request in the window, and past `maxKeys` the least recently seen go first.
export function createLimiter({ limit = 5, windowMs = 60 * 60 * 1000, maxKeys = 10_000 } = {}) {
  const hits = new Map();
  let swept = 0;
  const sweep = (nowMs) => {
    for (const [key, times] of hits) if (times.at(-1) <= nowMs - windowMs) hits.delete(key);
    swept = nowMs;
  };
  return {
    get size() {
      return hits.size;
    },
    take(key, nowMs) {
      if (nowMs - swept >= windowMs) sweep(nowMs);
      const times = (hits.get(key) ?? []).filter((t) => t > nowMs - windowMs);
      const allowed = times.length < limit;
      if (allowed) times.push(nowMs);
      hits.delete(key);
      hits.set(key, times);
      if (hits.size > maxKeys) sweep(nowMs);
      for (const oldest of hits.keys()) {
        if (hits.size <= maxKeys) break;
        hits.delete(oldest);
      }
      return allowed;
    },
  };
}

// WAITLIST_UPSTREAM_URL names the waitlist function (…/functions/v1/waitlist); report is its sibling.
export function reportUrl(upstream) {
  const base = upstream.replace(/\/+$/, '');
  return /\/waitlist$/.test(base) ? `${base.slice(0, -'waitlist'.length)}report` : null;
}

function clientIp(request) {
  return request.headers.get('x-real-ip') ?? request.headers.get('x-forwarded-for')?.split(',')[0].trim() ?? '';
}

// Only the site's own page sends reports: a page elsewhere can't post through its visitors'
// browsers (a JSON content-type makes a cross-site fetch preflight, which nothing here answers).
function fromOwnPage(request) {
  if (!/^application\/json\b/i.test(request.headers.get('content-type') ?? '')) return false;
  const site = request.headers.get('sec-fetch-site');
  if (site !== null) return site === 'same-origin';
  const origin = request.headers.get('origin');
  if (origin === null) return true;
  try {
    return new URL(origin).host === (request.headers.get('host') ?? new URL(request.url).host);
  } catch {
    return false;
  }
}

async function forward(request, { env, fetch, now, limiter, timeoutMs }) {
  if (!fromOwnPage(request)) return json(403, { error: 'forbidden' });
  if (!limiter.take(clientNetwork(clientIp(request)), now.getTime())) return json(429, { error: 'rate_limited' });
  const text = await readText(request, BODY_LIMIT);
  const body = text === null ? null : parseObject(text);
  if (!body) return json(400, { error: 'invalid_request' });
  try {
    const res = await fetch(reportUrl(env.WAITLIST_UPSTREAM_URL), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-waitlist-proxy-secret': env.WAITLIST_PROXY_SECRET,
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
}

export async function handle(request, { env, fetch, now, limiter, timeoutMs = 10_000 }) {
  let res;
  if (!env.WAITLIST_UPSTREAM_URL || !env.WAITLIST_PROXY_SECRET || !reportUrl(env.WAITLIST_UPSTREAM_URL)) res = json(404, { error: 'not_found' });
  else if (request.method !== 'POST') res = json(405, { error: 'method_not_allowed' }, { allow: 'POST' });
  else res = await forward(request, { env, fetch, now, limiter, timeoutMs });
  console.log(`report ${res.status}`);
  return res;
}
