// Static server for the Flutter web build, routed like vercel.json: a missing file goes to the
// first rewrite whose source matches (the join page's `/join/:code`, else the app's index.html),
// a trailing slash redirects away (`trailingSlash: false`), any other missing file is a 404.
// Usage: node e2e/serve.mjs <dir> <port> [--csp <supabase-url> <posthog-host>]
// --csp sends vercel.json's Content-Security-Policy with the production Supabase and PostHog
// origins swapped for the given ones (job 33c: the e2e suite runs under the production CSP).
import { createReadStream, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import process from 'node:process';

const [root, port = '3000', flag, supabaseUrl, posthogHost] = process.argv.slice(2);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.css': 'text/css',
  '.ico': 'image/x-icon',
};

const vercel = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'));
// Vercel's sources are path-to-regexp patterns: a `:name` segment matches one path segment.
const rewrites = vercel.rewrites.map((r) => ({
  source: new RegExp(`^${r.source.replace(/\/:[A-Za-z_]\w*/g, '/[^/]+')}$`),
  destination: r.destination,
}));
const rewrite = (urlPath) => rewrites.find((r) => r.source.test(urlPath))?.destination;

function productionCsp() {
  for (const rule of vercel.headers) {
    const header = rule.headers.find((h) => h.key === 'Content-Security-Policy');
    if (header) return header.value;
  }
  throw new Error('vercel.json sets no Content-Security-Policy');
}

let csp;
if (flag === '--csp') {
  if (!supabaseUrl || !posthogHost) throw new Error('usage: --csp <supabase-url> <posthog-host>');
  const supabase = new URL(supabaseUrl);
  const ws = `${supabase.protocol === 'https:' ? 'wss' : 'ws'}://${supabase.host}`;
  csp = productionCsp()
    .replace(/https:\/\/[a-z0-9]+\.supabase\.co/g, supabase.origin)
    .replace(/wss:\/\/[a-z0-9]+\.supabase\.co/g, ws)
    .replace('https://eu.i.posthog.com', new URL(posthogHost).origin);
}

function resolve(urlPath) {
  const path = normalize(join(root, decodeURIComponent(urlPath)));
  if (!path.startsWith(normalize(root))) return null;
  try {
    if (statSync(path).isFile()) return path;
  } catch {
    return null;
  }
  return null;
}

createServer((req, res) => {
  const [urlPath, query] = req.url.split(/\?(.*)/s);
  const headers = { 'cache-control': 'no-store', ...(csp && { 'content-security-policy': csp }) };
  if (vercel.trailingSlash === false && urlPath.length > 1 && urlPath.endsWith('/')) {
    res.writeHead(308, { ...headers, location: urlPath.replace(/\/+$/, '') + (query ? `?${query}` : '') }).end();
    return;
  }
  const destination = rewrite(urlPath);
  const file = resolve(urlPath) ?? (destination ? resolve(destination) : null);
  if (!file) {
    res.writeHead(404, headers).end();
    return;
  }
  res.writeHead(200, { ...headers, 'content-type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
}).listen(Number(port), '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}`));
