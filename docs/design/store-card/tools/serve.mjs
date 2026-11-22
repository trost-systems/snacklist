// Serves docs/design on 127.0.0.1 for the round page and verify.mjs; /store-card/fonts/ comes from app/assets/fonts,
// as build.sh copies it. Usage: node serve.mjs [port] [root]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../../..');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.md': 'text/markdown; charset=utf-8', '.png': 'image/png', '.ttf': 'font/ttf', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };

export function serve(port = 0, root = join(repo, 'docs/design')) {
  const server = createServer(async (req, res) => {
    let path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (path.endsWith('/')) path += 'index.html';
    const file = path.startsWith('/store-card/fonts/') && root === join(repo, 'docs/design')
      ? join(repo, 'app/assets/fonts', path.slice('/store-card/fonts/'.length))
      : join(root, path);
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end('not found');
    }
  });
  return new Promise((ok) => server.listen(port, '127.0.0.1', () => ok({ server, url: `http://127.0.0.1:${server.address().port}` })));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { url } = await serve(Number(process.argv[2] ?? 8400), process.argv[3] ? resolve(process.argv[3]) : undefined);
  console.log(`${url}/store-card/sc/`);
}
