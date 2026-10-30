#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
PORT="${PORT:-3000}"

WEB_DIR="/home/runner/work/_temp/omgithub-web"
mkdir -p "$WEB_DIR"

cat > "$WEB_DIR/deployment-output.json" <<EOF
{"project":"$PROJECT_DIR","directory":"$PROJECT_DIR"}
EOF

echo "[start] project=$PROJECT_DIR port=$PORT"

# Install optional ws dependency for multiplayer (non-fatal if offline).
if [ -f package.json ]; then
  /usr/bin/time -p npm install --no-audit --no-fund 2>&1 | tail -n 5 || true
fi

# Serve the static build (index.html at project root) in the foreground on PORT.
/usr/bin/time -p node - <<'NODE' &
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = process.cwd();
const port = parseInt(process.env.PORT || '3000', 10);
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  let filePath = path.join(root, req.url === '/' ? '/index.html' : req.url);
  if (!filePath.startsWith(root + path.sep) && filePath !== root) filePath = path.join(root, 'index.html');
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      filePath = path.join(root, 'index.html');
    }
    const ext = path.extname(filePath).toLowerCase();
    res.setHeader('Content-Type', mime[ext] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-cache');
    fs.createReadStream(filePath).pipe(res).on('error', () => {
      res.writeHead(404); res.end('not found');
    });
  });
});
server.listen(port, '0.0.0.0', () => {
  console.log(`[start] serving static on http://0.0.0.0:${port}`);
});
server.on('error', (err) => { console.error('[start] server error', err); process.exit(1); });
NODE

# Wait briefly to confirm the server bound the port.
for i in $(seq 1 30); do
  if command -v curl >/dev/null 2>&1 && curl -sf -o /dev/null "http://127.0.0.1:${PORT}/index.html" 2>/dev/null; then
    echo "[start] healthy on port ${PORT}"
    wait
    exit 0
  fi
  sleep 0.2
done
echo "[start] timed out waiting for port ${PORT}" >&2
exit 1
