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

# Patch overrides to relative vendor link. Pass path via env so Windows
# backslashes (e.g. D:\a\...) are not interpreted as Python string escapes.
WS="$H/pnpm-workspace.yaml"
LOCK="$H/pnpm-lock.yaml"
if [[ -f "$WS" ]]; then
  export FDEX_WS_PATH="$WS"
  export FDEX_LOCK_PATH="$LOCK"
  python3 - <<'PY'
import os
import re
from pathlib import Path

ws = Path(os.environ["FDEX_WS_PATH"])
lines = []
for line in ws.read_text(encoding="utf-8").splitlines(True):
    if "dsh-openapi" in line and "link:" in line:
        lines.append("  'dsh-openapi': 'link:vendor/dsh-openapi'\n")
    else:
        lines.append(line)
ws.write_text("".join(lines), encoding="utf-8")
print("patched pnpm-workspace.yaml dsh-openapi -> link:vendor/dsh-openapi")

lock_path = os.environ.get("FDEX_LOCK_PATH", "")
if lock_path and Path(lock_path).is_file():
    lock = Path(lock_path)
    text = lock.read_text(encoding="utf-8")
    # Release tarball may still record an absolute box path in overrides.
    patched = re.sub(
        r"(?m)^(\s*dsh-openapi:\s*)link:.+$",
        r"\1link:vendor/dsh-openapi",
        text,
    )
    patched = re.sub(
        r"(?m)^(\s*specifier:\s*)link:.+/dsh-openapi\s*$",
        r"\1link:vendor/dsh-openapi",
        patched,
    )
    if patched != text:
        lock.write_text(patched, encoding="utf-8")
        print("patched pnpm-lock.yaml dsh-openapi override paths")
    else:
        print("pnpm-lock.yaml dsh-openapi paths already relative or absent")
PY
fi

export DSH_CLIENT_COMMIT_HASH=337cd32a63a7042ccfd2ade412619ee41441f4c1
cd "$H"
corepack enable
node -v
corepack pnpm --version

# GitHub Actions sets CI=true which freezes the lockfile; our vendor override
# may still differ from the packed lockfile, so allow refresh.
corepack pnpm install --no-frozen-lockfile
corepack pnpm run build
echo "[ci-build-workbench] done"
