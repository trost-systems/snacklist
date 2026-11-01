// Serves dist/ with the parts of vercel.json this site uses, so redirects and headers can be
// checked locally: headers, redirects with `has` header conditions, cleanUrls, trailingSlash false.
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
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
const matchesSource = (source, path) => new RegExp(`^${source}$`).test(path);

// Like Vercel, a `has` value is a regex that must match the whole header value; no value means present.
function matchesHas(has = [], req) {
  return has.every((cond) => {
    const value = req.headers[cond.key.toLowerCase()];
    if (value === undefined) return false;
    return cond.value === undefined || new RegExp(`^${cond.value}$`).test(value);
  });
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
      if (matchesSource(rule.source, path) && matchesHas(rule.has, req)) {
        for (const { key, value } of rule.headers) res.setHeader(key, value);
      }
    }
    const redirect = (status, location) => {
      res.writeHead(status, { Location: location + url.search }).end();
    };
    if (config.trailingSlash === false && path !== '/' && path.endsWith('/')) return redirect(308, path.replace(/\/+$/, '') || '/');
    if (config.cleanUrls && path.endsWith('.html')) return redirect(308, path.replace(/(\/index)?\.html$/, '') || '/');
    for (const rule of config.redirects ?? []) {
      if (matchesSource(rule.source, path) && matchesHas(rule.has, req)) {
        return redirect(rule.statusCode ?? (rule.permanent === false ? 307 : 308), rule.destination);
      }
    }
    const file = fileFor(root, path);
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
