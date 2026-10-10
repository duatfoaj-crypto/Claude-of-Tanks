/**
 * serve-dist.mjs — minimal static file server for the built project output.
 *
 * Serves the given directory (default: ./dist) in the foreground on
 * process.env.PORT (default 3000). Exact-file contract: directories resolve
 * to index.html, anything else is a 404. No build, no watch, no dependencies
 * beyond node itself.
 */
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';

const root = resolve(process.argv[2] || join(process.cwd(), 'dist'));
if (!existsSync(join(root, 'index.html'))) {
  console.error(`Static deployment output must contain index.html (missing under ${root}).`);
  process.exit(1);
}

const mime = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.glb': 'model/gltf-binary',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
};

const server = createServer((req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const path = resolve(root, '.' + decodeURIComponent(url.pathname));
    if (path !== root && !path.startsWith(root + '/')) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const file = statSync(path).isDirectory() ? join(path, 'index.html') : path;
    res.setHeader('Content-Type', mime[extname(file)] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.end(readFileSync(file));
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
});

const port = Number(process.env.PORT || 3000);
server.listen(port, '0.0.0.0', () => {
  console.log(`Serving ${root} on port ${port}.`);
});
