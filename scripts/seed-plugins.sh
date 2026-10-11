#!/usr/bin/env bash
# Seed vendor plugins into DSH_HOME (idempotent). Called from start / setup.
# Equivalent of Electron fixupDshHome for dsh-our-free-model — no pnpm needed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

resolve_root() {
  if [[ -n "${FDE_REPO_ROOT:-}" && -d "$FDE_REPO_ROOT/upstream/deepseek-harness" ]]; then
    (cd "$FDE_REPO_ROOT" && pwd); return
  fi
  for cand in \
    "$REPO_ROOT/workbench" \
    "$REPO_ROOT/workbench-src" \
    "$REPO_ROOT"
  do
    if [[ -d "$cand/upstream/deepseek-harness" ]]; then
      (cd "$cand" && pwd); return
    fi
  done
  echo "seed-plugins: 找不到工作台根（需要 upstream/deepseek-harness）" >&2
  exit 1
}

export FDE_REPO_ROOT="$(resolve_root)"
export DSH_HOME="${DSH_HOME:-$FDE_REPO_ROOT/.runtime/dsh-home}"
mkdir -p "$DSH_HOME"

if ! command -v node >/dev/null 2>&1; then
  echo "seed-plugins: 需要 node" >&2
  exit 1
fi

node "$SCRIPT_DIR/seed-plugins.js"
