#!/usr/bin/env bash
# start.sh — install, build (when needed), publish deployment metadata, serve.
#
# - Source and built output stay inside PROJECT_DIR (the build lands in ./dist).
# - OPENCODE_WEB_DIR carries worker metadata only
#   (deployment-output.json, dependency stamp).
# - Serves the built ./dist directory in the FOREGROUND on $PORT (default 3000).
set -euo pipefail
cd "$(dirname "$0")"

/usr/bin/time -p test -n "${OPENCODE_WEB_DIR:?OPENCODE_WEB_DIR must be set.}"
PROJECT_ROOT="$(/usr/bin/time -p pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
PORT="${PORT:-3000}"
export PORT

# --- dependencies -----------------------------------------------------------
# Same stamp contract as the default pipeline: reinstall only when the
# package.json/package-lock.json fingerprint moved or vite is absent.
FINGERPRINT="$(/usr/bin/time -p node -e 'const fs=require("node:fs");const ex=p=>fs.existsSync(p)?fs.readFileSync(p):"";process.stdout.write(ex("package.json")+ex("package-lock.json"))' | /usr/bin/time -p sha256sum | /usr/bin/time -p cut -d" " -f1)"
STAMP_FILE="$OPENCODE_WEB_DIR/default-dependencies"
OLD_FINGERPRINT="$(/usr/bin/time -p cat "$STAMP_FILE" 2>/dev/null || true)"
if [[ "$FINGERPRINT" != "$OLD_FINGERPRINT" ]] || [[ ! -x "$PROJECT_ROOT/node_modules/vite/bin/vite.js" ]]; then
  if [[ -f "$PROJECT_ROOT/package-lock.json" ]]; then
    /usr/bin/time -p npm ci --no-audit --no-fund
  else
    /usr/bin/time -p npm install --no-audit --no-fund
  fi
  /usr/bin/time -p bash -c 'printf "%s" "$0" > "$1"' "$FINGERPRINT" "$STAMP_FILE"
fi

# --- build ------------------------------------------------------------------
# Rebuild when forced, when the output is missing, or when inputs are newer.
NEEDS_BUILD=0
if [[ "${FORCE_BUILD:-0}" == 1 ]]; then NEEDS_BUILD=1; fi
if [[ ! -f "$DIST_DIR/index.html" ]]; then NEEDS_BUILD=1; fi
if [[ "$NEEDS_BUILD" == 0 ]] && /usr/bin/time -p find index.html vite.config.ts src public package.json -newer "$DIST_DIR/index.html" -print -quit 2>/dev/null | /usr/bin/time -p grep -q .; then
  NEEDS_BUILD=1
fi
if [[ "$NEEDS_BUILD" == 1 ]]; then
  # Direct vite build (not `npm run build`): the npm prebuild hook requires
  # i18n service credentials, while vite build alone is fully local.
  /usr/bin/time -p node node_modules/vite/bin/vite.js build
fi
/usr/bin/time -p test -f "$DIST_DIR/index.html"

# --- deployment metadata ----------------------------------------------------
# Absolute built static directory inside PROJECT_DIR for the controller.
OPENCODE_WEB_DIR="$OPENCODE_WEB_DIR" PROJECT_ROOT="$PROJECT_ROOT" DIST_DIR="$DIST_DIR" \
  /usr/bin/time -p node -e 'const fs=require("node:fs"),p=require("node:path");fs.writeFileSync(p.join(process.env.OPENCODE_WEB_DIR,"deployment-output.json"),JSON.stringify({project:process.env.PROJECT_ROOT,directory:process.env.DIST_DIR}))'
/usr/bin/time -p cat "$OPENCODE_WEB_DIR/deployment-output.json"
echo

# --- serve in the foreground --------------------------------------------------
# The controller reuses this healthy server; it owns the tmux session.
# NOTE: `exec` is a shell builtin — /usr/bin/time can only run real binaries.
/usr/bin/time -p node scripts/serve-dist.mjs "$DIST_DIR"
