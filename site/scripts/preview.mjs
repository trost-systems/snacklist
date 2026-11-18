// Serves dist/ with the parts of vercel.json this site uses, so redirects and headers can be
// checked locally: headers, redirects with `has` header conditions, rewrites to functions, cleanUrls,
// trailingSlash false.
// The site/api functions (waitlist, report, get) answer under /api/* with the env of this process.
import process from 'node:process';
import { Buffer } from 'node:buffer';
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as signup from '../api/waitlist/index.mjs';
import * as confirm from '../api/waitlist/confirm.mjs';
import * as unsubscribe from '../api/waitlist/unsubscribe.mjs';
import * as getApp from '../api/get.mjs';
import * as report from '../api/report.mjs';

const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.js': 'text/javascript; charset=utf-8',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.webm': 'video/webm',
  '.mp4': 'video/mp4',
  '.vtt': 'text/vtt; charset=utf-8',
};

// Sources here are plain paths or regex groups like "/(.*)", which path-to-regexp treats like a regex.
export const matchesSource = (source, path) => new RegExp(`^${source}$`).test(path);

// Like Vercel, a `has` value is a regex that must match the whole header value; no value means present.
function matchesHas(req, has = []) {
  return has.every((cond) => {
    // type "host" matches the Host header without its port (S3: the hummlist.com redirect).
    const value = cond.type === 'host' ? req.headers.host?.replace(/:\d+$/, '') : req.headers[cond.key.toLowerCase()];
    if (value === undefined) return false;
    return cond.value === undefined || new RegExp(`^${cond.value}$`).test(value);
  });
}

const FUNCTIONS = { '/api/waitlist': signup, '/api/waitlist/confirm': confirm, '/api/waitlist/unsubscribe': unsubscribe, '/api/get': getApp, '/api/report': report };

// Hands the request to a site/api function the way Vercel does, x-real-ip from the socket.
async function callFunction(module, req, res) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) headers.set(key, [value].flat().join(', '));
  headers.set('x-real-ip', req.socket.remoteAddress);
  const hasBody = !['GET', 'HEAD'].includes(req.method);
  const request = new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers, body: hasBody ? Buffer.concat(chunks) : undefined });
  // An unexported method still reaches the shared handler, which answers 405 with allow.
  const response = await (module[req.method] ?? module.POST)(request);
  res.statusCode = response.status;
  for (const [key, value] of response.headers) res.setHeader(key, value);
  res.end(Buffer.from(await response.arrayBuffer()));
}

function fileFor(dir, path) {
  const candidates = path === '/' ? ['index.html'] : [path, `${path}.html`];
  for (const candidate of candidates) {
    const file = normalize(join(dir, candidate));
    if (file.startsWith(dir) && existsSync(file) && statSync(file).isFile()) return file;
  }
  return null;
}

export function startPreview({ dir = join(SITE_DIR, 'dist'), port = 55990, host = '127.0.0.1' } = {}) {
  const config = JSON.parse(readFileSync(join(SITE_DIR, 'vercel.json'), 'utf8'));
  const root = normalize(dir);
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://preview');
    const path = decodeURIComponent(url.pathname);
    for (const rule of config.headers ?? []) {
      if (matchesSource(rule.source, path) && matchesHas(req, rule.has)) {
        for (const { key, value } of rule.headers) res.setHeader(key, value);
      }
    }
    const redirect = (status, location) => {
      res.writeHead(status, { Location: location + url.search }).end();
    };
    if (config.trailingSlash === false && path !== '/' && path.endsWith('/')) return redirect(308, path.replace(/\/+$/, '') || '/');
    if (config.cleanUrls && path.endsWith('.html')) return redirect(308, path.replace(/(\/index)?\.html$/, '') || '/');
    for (const rule of config.redirects ?? []) {
      if (matchesSource(rule.source, path) && matchesHas(req, rule.has)) {
        const groups = new RegExp(`^${rule.source}$`).exec(path);
        const location = rule.destination.replace(/\$(\d)/g, (_, n) => groups[Number(n)] ?? '');
        return redirect(rule.statusCode ?? (rule.permanent === false ? 307 : 308), location);
      }
    }
    if (FUNCTIONS[path]) {
      return callFunction(FUNCTIONS[path], req, res).catch(() => res.writeHead(500).end());
    }
    const file = fileFor(root, path);
    // Like Vercel: files first, then rewrites (only to functions here).
    const rewrite = file ? null : (config.rewrites ?? []).find((rule) => matchesSource(rule.source, path) && FUNCTIONS[rule.destination]);
    if (rewrite) return callFunction(FUNCTIONS[rewrite.destination], req, res).catch(() => res.writeHead(500).end());
    const status = file ? 200 : 404;
    const body = file ?? join(root, '404.html');
    res.writeHead(status, { 'Content-Type': TYPES[extname(body)] ?? 'application/octet-stream' });
    res.end(req.method === 'HEAD' ? undefined : readFileSync(body));
  });
  return new Promise((resolve) => server.listen(port, host, () => resolve(server)));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT ?? 55990);
  await startPreview({ port });
  console.log(`preview on http://127.0.0.1:${port}`);
}
