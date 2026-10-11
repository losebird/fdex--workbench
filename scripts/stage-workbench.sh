#!/usr/bin/env bash
# Stage a slim-but-runnable workbench copy for electron-builder extraResources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-linux}"
SRC_REPO="${FDEX_SRC_REPO:-$ROOT/workbench-src}"
VENDOR="${FDEX_VENDOR:-$ROOT/vendor}"
DEST="$ROOT/staging/workbench"

# GitHub Actions passes github.workspace as D:\... while bash pwd is /d/....
# Normalize early so prefix-stripping and Node fs paths stay consistent.
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -u "$ROOT")"
  SRC_REPO="$(cygpath -u "$SRC_REPO")"
  VENDOR="$(cygpath -u "$VENDOR")"
  DEST="$ROOT/staging/workbench"
fi

echo "[stage] target=$TARGET"
echo "[stage] src=$SRC_REPO"
echo "[stage] dest=$DEST"

if [[ ! -d "$SRC_REPO/upstream/deepseek-harness" ]]; then
  echo "ERROR: harness missing at $SRC_REPO (run scripts/ci-fetch-workbench.sh + ci-build-workbench.sh)" >&2
  exit 1
fi

# pnpm node_modules is a symlink farm, often with cycles (e.g. cordis <-> include).
# NEVER tar -h / dereference that tree — it explodes into "File name too long".
# On Windows, MSYS tar also fails creating *dangling* symlinks. Fix = copy with a
# tool that can create native symlinks, and only after symlink targets exist:
#   1) harness tree with ALL node_modules excluded
#   2) root node_modules (contains .pnpm store)
#   3) nested package node_modules (links into root .pnpm)
is_windows=0
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) is_windows=1 ;;
esac
[[ "${OS:-}" == "Windows_NT" ]] && is_windows=1
case "${MSYSTEM:-}" in MINGW*|MSYS*) is_windows=1 ;; esac
[[ "$TARGET" == "win" ]] && is_windows=1

# Prefer native Windows symlinks from MSYS tools when we fall back to cp/tar.
if [[ "$is_windows" -eq 1 ]]; then
  export MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict"
  export MSYS2_ARG_CONV_EXCL='*'
fi

# Copy a directory tree. Prefer Node fs.cpSync(verbatimSymlinks) on Windows so
# pnpm links are recreated as real symlinks without following cycles.
win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

copy_tree() {
  local src_dir="$1"
  local dest_dir="$2"
  mkdir -p "$(dirname "$dest_dir")"
  if [[ "$is_windows" -eq 1 ]]; then
    node -e '
const fs = require("fs");
fs.cpSync(process.argv[1], process.argv[2], { recursive: true, verbatimSymlinks: true, force: true });
' "$(win_path "$src_dir")" "$(win_path "$dest_dir")"
  else
    cp -a "$src_dir" "$dest_dir"
  fi
}

# Copy contents of src_dir INTO an existing/new dest_dir (like tar pipe of ".")
copy_tree_contents() {
  local src_dir="$1"
  local dest_dir="$2"
  mkdir -p "$dest_dir"
  if [[ "$is_windows" -eq 1 ]]; then
    rm -rf "$dest_dir"
    node -e '
const fs = require("fs");
fs.cpSync(process.argv[1], process.argv[2], { recursive: true, verbatimSymlinks: true, force: true });
' "$(win_path "$src_dir")" "$(win_path "$dest_dir")"
  else
    mkdir -p "$dest_dir"
    (cd "$src_dir" && tar cf - .) | (cd "$dest_dir" && tar xf -)
  fi
}

rm -rf "$DEST"
mkdir -p "$DEST"

echo "[stage] copying repo (excluding harness / .runtime)..."
[[ "$is_windows" -eq 1 ]] && echo "[stage] Windows — preserving pnpm symlinks via Node fs.cpSync (no dereference)"
for f in "$SRC_REPO"/* "$SRC_REPO"/.[!.]*; do
  base=$(basename "$f")
  [[ "$base" == "." || "$base" == ".." ]] && continue
  if [[ "$base" == "upstream" || "$base" == ".runtime" ]]; then
    continue
  fi
  if [[ -d "$f" ]]; then
    copy_tree "$f" "$DEST/$base"
  elif [[ -f "$f" ]]; then
    cp -a "$f" "$DEST/$base"
  fi
done

mkdir -p "$DEST/upstream"
echo "[stage] copying deepseek-harness (exclude ALL node_modules)..."
# Exclude every node_modules directory. Nested package farms are copied after
# the root .pnpm store exists so Windows symlink creation can resolve targets.
(cd "$SRC_REPO/upstream/deepseek-harness" && tar cf - \
  --exclude=node_modules \
  --exclude=./.git \
  --exclude=./coverage \
  --exclude='*.map' \
  .) | (mkdir -p "$DEST/upstream/deepseek-harness" && cd "$DEST/upstream/deepseek-harness" && tar xf -)

if [[ -d "$SRC_REPO/upstream/deepseek-harness/node_modules" ]]; then
  echo "[stage] copying root node_modules (please wait)..."
  copy_tree_contents \
    "$SRC_REPO/upstream/deepseek-harness/node_modules" \
    "$DEST/upstream/deepseek-harness/node_modules"
else
  echo "ERROR: node_modules missing — run ci-build-workbench.sh first" >&2
  exit 1
fi

echo "[stage] syncing nested node_modules dirs..."
H0="$SRC_REPO/upstream/deepseek-harness"
H="$DEST/upstream/deepseek-harness"
# Use relative paths from inside H0 — absolute Windows paths break ${d#$H0/} stripping
# and Node then joins D:\ into an already-rooted dest (ENOPROTOOPT / bad path).
(cd "$H0" && find . -type d -name node_modules ! -path '*/node_modules/*' ! -path './node_modules' -print0) |
while IFS= read -r -d '' rel; do
  rel="${rel#./}"
  dest="$H/$rel"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    copy_tree_contents "$H0/$rel" "$dest"
  fi
done

mkdir -p "$DEST/vendor"
if [[ -d "$VENDOR/dsh-openapi" ]]; then
  rm -rf "$DEST/vendor/dsh-openapi"
  copy_tree "$VENDOR/dsh-openapi" "$DEST/vendor/dsh-openapi"
fi
if [[ -d "$VENDOR/dsh-our-free-model" ]]; then
  rm -rf "$DEST/vendor/dsh-our-free-model"
  copy_tree "$VENDOR/dsh-our-free-model" "$DEST/vendor/dsh-our-free-model"
fi

# Optional seed (no credentials). Lab seed should stay private — omit by default in CI.
mkdir -p "$DEST/.runtime/dsh-home"
if [[ "${FDEX_INCLUDE_RUNTIME_SEED:-0}" == "1" && -d "$SRC_REPO/.runtime/dsh-home" ]]; then
  (cd "$SRC_REPO/.runtime/dsh-home" && tar cf - \
    --exclude=sessions \
    --exclude=storages \
    --exclude=.credentials.yaml \
    .) | (cd "$DEST/.runtime/dsh-home" && tar xf -)
fi

BRAND_TARGETS=(
  "$DEST/frontend/public/brand"
  "$DEST/upstream/deepseek-harness/apps/web/public"
)
for t in "${BRAND_TARGETS[@]}"; do
  mkdir -p "$t"
  cp -f "$ROOT/resources/brand/logo.svg" "$t/fde-x-logo.svg" 2>/dev/null || true
done

case "$TARGET" in
  linux) echo "[stage] OK for Linux: native .node modules match this box." ;;
  win|mac)
    echo "[stage] Staged tree from this OS. Prefer rebuild-natives on target OS in CI."
    ;;
esac

HAS_LAB=false
[[ -d "$DEST/upstream/deepseek-harness/packages/fde/discovery-lab" ]] && HAS_LAB=true

cat > "$DEST/FDEX_STAGING.json" << META
{
  "stagedAt": "$(date -Iseconds)",
  "target": "$TARGET",
  "harnessVersion": "0.1.1-rc.2",
  "dshClientCommitHash": "337cd32a63a7042ccfd2ade412619ee41441f4c1",
  "hostPlatform": "$(uname -s)-$(uname -m)",
  "includesLabAssets": $HAS_LAB,
  "privateUseOnly": true,
  "licenseNote": "Lab materials and course layer are for Ace private packaging; not a redistribution license claim. Prefer a private GitHub repo."
}
META

du -sh "$DEST" "$DEST/upstream/deepseek-harness/node_modules" 2>/dev/null || true
echo "[stage] done"
