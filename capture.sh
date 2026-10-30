#!/usr/bin/env bash
set -euo pipefail

if [ -z "${CAPTURE_URL:-}" ] || [ -z "${CAPTURE_DIR:-}" ]; then
  echo "capture.sh: CAPTURE_URL and CAPTURE_DIR must be set" >&2
  exit 1
fi

mkdir -p "$CAPTURE_DIR"

RUNTIME="${HOME}/.local/share/omgithub-playwright"
RUNNER="/tmp/opencode/capture-run.mjs"
export DISPLAY=":${DISPLAY:-$(cat "${RUNTIME}/display" 2>/dev/null || echo 0)}"

cat > "$RUNNER" <<'NODE'
import { createRequire } from 'node:module'
import { join } from 'node:path'
const url = process.argv[2]
const output = process.argv[3]
const require = createRequire(join(process.env.HOME, '.local/share/omgithub-playwright', 'node_modules', 'package.json'))
const { chromium } = require('playwright')

const transient = (err) => { console.error('transient failure:', err && err.message ? err.message : err); process.exitCode = 75 }
let browser = null
let exitCode = 0

try {
  browser = await chromium.launch({
    headless: false,
    args: [
      '--no-sandbox', '--disable-dev-shm-usage',
      '--enable-gpu', '--ignore-gpu-blocklist', '--use-gl=swiftshader'
    ]
  }).catch(err => { transient(err); throw err })

  const contexts = [
    { name: 'desktop', width: 1440, height: 900 },
    { name: 'mobile', width: 390, height: 844 }
  ]

  for (const { name, width, height } of contexts) {
    const page = await browser.newPage({ viewport: { width, height } }).catch(err => { transient(err); throw err })
    page.setDefaultTimeout(30000)
    page.on('pageerror', err => console.error(`pageerror [${name}]:`, err.message))
    console.log(`[capture] ${name}: goto ${url}`)
    const response = await page.goto(url, { waitUntil: 'load', timeout: 60000 }).catch(err => { transient(err); throw err })
    if (!response || !response.ok()) {
      const status = response ? response.status() : 'unknown'
      const isInfra = !response || [408, 429, 500, 502, 503, 504].includes(status)
      console.error(`[capture] ${name}: HTTP ${status} loading preview`)
      exitCode = isInfra ? 75 : 1
      await page.close().catch(() => {})
      continue
    }
    await page.locator('body').waitFor({ state: 'visible', timeout: 30000 }).catch(() => {})
    try { await page.waitForFunction(() => document.fonts.status === 'loaded', { timeout: 10000 }).catch(() => {}) } catch {}
    await page.waitForTimeout(1000)
    const outPath = join(output, `final-${name}.png`)
    await page.screenshot({ path: outPath, timeout: 30000 }).catch(err => {
      if (err.name === 'TimeoutError' || !browser.isConnected()) { transient(err); throw err }
      throw err
    })
    console.log(`[capture] ${name}: wrote ${outPath}`)
    await page.close().catch(() => {})
  }
} catch (err) {
  console.error('capture error:', err && err.message ? err.message : err)
  if (!exitCode) exitCode = 1
} finally {
  if (browser) {
    try { await browser.close() } catch (err) { console.error(err); if (!exitCode) exitCode = 75 }
  }
}

process.exit(exitCode)
NODE

set +e
/usr/bin/time -p node "$RUNNER" "${CAPTURE_URL}" "${CAPTURE_DIR}"
status=$?
set -e
exit $status
