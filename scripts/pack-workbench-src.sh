#!/usr/bin/env bash
# Pack FDEDeliveryWorkbench source WITHOUT node_modules / .runtime for Release upload.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_REPO="${FDEX_SRC_REPO:-/workspace/zip-recover/out/extracted/FF-FDE交付工作台-学员源码-20260916/FDEDeliveryWorkbench}"
OUT="${WORKBENCH_SRC_OUT:-/tmp/workbench-src.tar.zst}"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

echo "[pack] src=$SRC_REPO"
echo "[pack] out=$OUT"

if [[ ! -d "$SRC_REPO/upstream/deepseek-harness" ]]; then
  echo "ERROR: missing harness at $SRC_REPO" >&2
  exit 1
fi

rsync -a \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude '.runtime' \
  --exclude 'coverage' \
  --exclude '*.map' \
  "$SRC_REPO/" "$STAGING/"

WS="$STAGING/upstream/deepseek-harness/pnpm-workspace.yaml"
if [[ -f "$WS" ]]; then
  python3 - <<PY
from pathlib import Path
p = Path("$WS")
lines=[]
for line in p.read_text().splitlines(True):
    if "dsh-openapi" in line and "link:" in line:
        lines.append("  'dsh-openapi': 'link:vendor/dsh-openapi'\n")
    else:
        lines.append(line)
p.write_text(''.join(lines))
PY
fi

cat > "$STAGING/PACKAGING.md" <<'NOTE'
This archive is source-only (no node_modules, no .runtime).
Root layout: upstream/deepseek-harness, frontend/, …
CI runs pnpm install + build. Lab imported assets are NOT included.
Prefer a private GitHub repository — see NOTICE.md.
NOTE

mkdir -p "$(dirname "$OUT")"
tar -C "$STAGING" -cf - . | zstd -f -T0 -19 -o "$OUT"
ls -lh "$OUT"
# sanity
zstd -dc "$OUT" | tar -tf - | head -5
test -n "$(zstd -dc "$OUT" | tar -tf - | grep '^\\./upstream/deepseek-harness/package.json$' || zstd -dc "$OUT" | tar -tf - | grep 'upstream/deepseek-harness/package.json' | head -1)"
echo "[pack] done: $OUT"
