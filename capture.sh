#!/usr/bin/env bash
# capture.sh — screenshot the exact $CAPTURE_URL at desktop + mobile viewports.
#
# - Reads CAPTURE_URL and CAPTURE_DIR from the environment (both required).
# - Writes final-desktop.png and final-mobile.png into CAPTURE_DIR (outside the
#   source tree) and leaves the app server running.
# - Exit 75: temporary navigation/browser infrastructure failure (retryable).
# - Exit 1: script defect or rendering defect (missing env, bad HTTP status,
#   blank/empty evidence).
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${CAPTURE_URL:-}" || -z "${CAPTURE_DIR:-}" ]]; then
  echo 'Set CAPTURE_URL and CAPTURE_DIR.' >&2
  exit 1
fi
/usr/bin/time -p mkdir -p "$CAPTURE_DIR"

/usr/bin/time -p test -n "${HOME:?HOME must be set.}"
PLAYWRIGHT_RUNTIME_DIR="${PLAYWRIGHT_RUNTIME_DIR:-$HOME/.local/share/omgithub-playwright}"
HELPER_DIR="${RUNNER_TEMP:-/tmp}"
HELPER_FILE="$HELPER_DIR/capture-helper-$$.mjs"
cleanup() { rm -f "$HELPER_FILE"; }
trap cleanup EXIT

/usr/bin/time -p cat > "$HELPER_FILE" <<'HELPER_EOF'
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const runtime = process.env.PLAYWRIGHT_RUNTIME_DIR;
const require = createRequire(join(runtime, 'package.json'));
const { chromium } = require('playwright');
try {
  require(join(runtime, 'wip-screenshots.cjs')).instrument({ chromium });
} catch (error) {
  console.error(`WIP instrumentation skipped: ${error.message}`);
}
const config = JSON.parse(readFileSync(join(runtime, process.platform === 'darwin' ? 'metal.json' : 'linux.json'), 'utf8'));
if (process.platform === 'linux') {
  process.env.DISPLAY ||= ':' + readFileSync(join(runtime, 'display'), 'utf8').trim();
}

const url = process.env.CAPTURE_URL;
const output = process.env.CAPTURE_DIR;
if (!url || !output) {
  console.error('Set CAPTURE_URL and CAPTURE_DIR.');
  process.exit(1);
}
mkdirSync(output, { recursive: true });

const TRANSIENT_STATUS = new Set([408, 429, 500, 502, 503, 504]);
const transient = (error) => { throw Object.assign(error, { exitCode: 75 }); };

// Best-effort gameplay start: click the single visible start/play control, if any.
async function autoStart(page) {
  if (process.env.CAPTURE_AUTO_START === 'false') return 'disabled';
  const selector = process.env.CAPTURE_START_SELECTOR || '';
  const deadline = Date.now() + 3000;
  for (;;) {
    const candidate = selector ? page.locator(selector) : page.locator('button, input[type="button"], input[type="submit"], [role="button"]');
    const matches = [];
    for (const control of await candidate.all()) {
      if (!await control.isVisible() || !await control.isEnabled()) continue;
      const eligible = await control.evaluate((element, explicit) => {
        if (element.closest('a[href], form') || element.getAttribute('aria-disabled') === 'true') return false;
        if (explicit) return true;
        const label = element.getAttribute('aria-label') || element.value || element.textContent || '';
        return /^(?:start|play)(?:\s+(?:game|now))?$/i.test(label.trim());
      }, Boolean(selector));
      if (eligible) matches.push(control);
    }
    if (matches.length > 1) return 'ambiguous';
    if (matches.length === 1) {
      try { await matches[0].click({ trial: true, timeout: 2000 }); }
      catch (error) {
        if (error.name === 'TimeoutError') return 'not-actionable';
        throw error;
      }
      await matches[0].click({ timeout: 2000, noWaitAfter: true });
      return 'clicked';
    }
    if (Date.now() >= deadline) return 'not-found';
    await page.waitForTimeout(Math.min(200, Math.max(0, deadline - Date.now())));
  }
}

let browser;
try {
  browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }).catch(transient);
  for (const [name, width, height] of [['desktop', 1440, 900], ['mobile', 390, 844]]) {
    const page = await browser.newPage({ viewport: { width, height } }).catch(transient);
    page.setDefaultTimeout(30000);
    page.on('pageerror', (error) => console.error(error.message));
    const response = await page.goto(url, { waitUntil: 'load', timeout: 45000 }).catch(transient);
    if (!response?.ok()) {
      const status = response?.status();
      throw Object.assign(new Error(`HTTP ${status} loading preview`), {
        exitCode: !response || TRANSIENT_STATUS.has(status) ? 75 : 1,
      });
    }
    await page.locator(process.env.CAPTURE_READY_SELECTOR || 'body').waitFor({ state: 'visible' });
    await page.waitForFunction(() => document.fonts.status === 'loaded');
    console.log(`Capture ${name}: auto-start ${await autoStart(page)}`);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(output, `final-${name}.png`), timeout: 30000 }).catch((error) => {
      if (error.name === 'TimeoutError' || !browser.isConnected()) transient(error);
      throw error;
    });
    await page.close();
  }
} catch (error) {
  console.error(error);
  process.exitCode = error.exitCode || 1;
} finally {
  await browser?.close().catch((error) => { console.error(error); process.exitCode ||= 75; });
}
HELPER_EOF

PLAYWRIGHT_RUNTIME_DIR="$PLAYWRIGHT_RUNTIME_DIR" CAPTURE_URL="$CAPTURE_URL" CAPTURE_DIR="$CAPTURE_DIR" \
  /usr/bin/time -p node "$HELPER_FILE"

/usr/bin/time -p test -s "$CAPTURE_DIR/final-desktop.png"
/usr/bin/time -p test -s "$CAPTURE_DIR/final-mobile.png"
/usr/bin/time -p ls -l "$CAPTURE_DIR/final-desktop.png" "$CAPTURE_DIR/final-mobile.png"
