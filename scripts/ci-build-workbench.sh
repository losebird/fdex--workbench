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

# Place dsh-openapi OUTSIDE harness vendor/* so tsdown's workspace glob does
# not treat it as a DSH package (it has no lib/types/* entries).
mkdir -p "$SRC/vendor"
if [[ -d "$VENDOR_SRC/dsh-openapi" ]]; then
  rm -rf "$SRC/vendor/dsh-openapi" "$H/vendor/dsh-openapi"
  cp -a "$VENDOR_SRC/dsh-openapi" "$SRC/vendor/dsh-openapi"
fi
if [[ -d "$VENDOR_SRC/dsh-our-free-model" ]]; then
  rm -rf "$SRC/vendor/dsh-our-free-model"
  cp -a "$VENDOR_SRC/dsh-our-free-model" "$SRC/vendor/dsh-our-free-model"
fi

OPENAPI_LINK='link:../../vendor/dsh-openapi'

# Pass paths via env so Windows backslashes are not Python string escapes.
WS="$H/pnpm-workspace.yaml"
LOCK="$H/pnpm-lock.yaml"
if [[ -f "$WS" ]]; then
  export FDEX_WS_PATH="$WS"
  export FDEX_LOCK_PATH="$LOCK"
  export FDEX_OPENAPI_LINK="$OPENAPI_LINK"
  python3 - <<'PY'
import os
import re
from pathlib import Path

link = os.environ["FDEX_OPENAPI_LINK"]
ws = Path(os.environ["FDEX_WS_PATH"])
lines = []
for line in ws.read_text(encoding="utf-8").splitlines(True):
    if "dsh-openapi" in line and "link:" in line:
        lines.append(f"  'dsh-openapi': '{link}'\n")
    else:
        lines.append(line)
ws.write_text("".join(lines), encoding="utf-8")
print(f"patched pnpm-workspace.yaml dsh-openapi -> {link}")

lock_path = os.environ.get("FDEX_LOCK_PATH", "")
if lock_path and Path(lock_path).is_file():
    lock = Path(lock_path)
    text = lock.read_text(encoding="utf-8")
    patched = re.sub(
        r"(?m)^(\s*dsh-openapi:\s*)link:.+$",
        rf"\1{link}",
        text,
    )
    patched = re.sub(
        r"(?m)^(\s*specifier:\s*)link:.+/dsh-openapi\s*$",
        rf"\1{link}",
        patched,
    )
    patched = re.sub(
        r"(?m)^(\s*version:\s*)link:.+/dsh-openapi\s*$",
        rf"\1{link}",
        patched,
    )
    if patched != text:
        lock.write_text(patched, encoding="utf-8")
        print("patched pnpm-lock.yaml dsh-openapi override paths")
    else:
        print("pnpm-lock.yaml dsh-openapi paths already relative or absent")
PY
fi

if [[ ! -d "$SRC/vendor/dsh-openapi" ]]; then
  echo "ERROR: missing $SRC/vendor/dsh-openapi (copy from repo vendor/)" >&2
  exit 1
fi

export DSH_CLIENT_COMMIT_HASH=337cd32a63a7042ccfd2ade412619ee41441f4c1
cd "$H"
corepack enable
node -v
corepack pnpm --version

# Actions sets CI=true (frozen lockfile); allow refresh after override rewrite.
corepack pnpm install --no-frozen-lockfile
corepack pnpm run build
echo "[ci-build-workbench] done"
