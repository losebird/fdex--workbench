#!/usr/bin/env bash
# Run ON macOS or Windows (or matching Linux) after staging, before electron-builder.
# Reinstalls platform-native bindings inside staging/workbench harness.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/staging/workbench/upstream/deepseek-harness"
export DSH_CLIENT_COMMIT_HASH=337cd32a63a7042ccfd2ade412619ee41441f4c1
cd "$H"
if command -v corepack >/dev/null; then
  corepack enable
  corepack pnpm install
else
  echo "Need Node 24 + corepack/pnpm on this machine" >&2
  exit 1
fi
echo "[rebuild-natives] done for $(uname -s)"
