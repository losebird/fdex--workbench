#!/usr/bin/env bash
# pnpm install + build inside extracted workbench-src (CI / local).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${FDEX_SRC_REPO:-$ROOT/workbench-src}"
H="$SRC/upstream/deepseek-harness"
VENDOR_SRC="${FDEX_VENDOR:-$ROOT/vendor}"

if [[ ! -d "$H" ]]; then
  echo "ERROR: missing $H — run ci-fetch-workbench.sh first" >&2
  exit 1
fi

mkdir -p "$SRC/vendor" "$H/vendor"
if [[ -d "$VENDOR_SRC/dsh-openapi" ]]; then
  rm -rf "$SRC/vendor/dsh-openapi" "$H/vendor/dsh-openapi"
  cp -a "$VENDOR_SRC/dsh-openapi" "$SRC/vendor/dsh-openapi"
  cp -a "$VENDOR_SRC/dsh-openapi" "$H/vendor/dsh-openapi"
fi
if [[ -d "$VENDOR_SRC/dsh-our-free-model" ]]; then
  rm -rf "$SRC/vendor/dsh-our-free-model"
  cp -a "$VENDOR_SRC/dsh-our-free-model" "$SRC/vendor/dsh-our-free-model"
fi

WS="$H/pnpm-workspace.yaml"
if [[ -f "$WS" ]]; then
  python3 - <<PY
from pathlib import Path
p = Path("$WS")
lines = []
for line in p.read_text().splitlines(True):
    if "dsh-openapi" in line and "link:" in line:
        lines.append("  'dsh-openapi': 'link:vendor/dsh-openapi'\n")
    else:
        lines.append(line)
p.write_text(''.join(lines))
print("patched pnpm-workspace.yaml dsh-openapi -> link:vendor/dsh-openapi")
PY
fi

export DSH_CLIENT_COMMIT_HASH=337cd32a63a7042ccfd2ade412619ee41441f4c1
cd "$H"
corepack enable
node -v
corepack pnpm --version
corepack pnpm install
corepack pnpm run build
echo "[ci-build-workbench] done"
