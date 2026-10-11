#!/usr/bin/env bash
# Stage a slim-but-runnable workbench copy for electron-builder extraResources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-linux}"
SRC_REPO="${FDEX_SRC_REPO:-$ROOT/workbench-src}"
VENDOR="${FDEX_VENDOR:-$ROOT/vendor}"
DEST="$ROOT/staging/workbench"

echo "[stage] target=$TARGET"
echo "[stage] src=$SRC_REPO"
echo "[stage] dest=$DEST"

if [[ ! -d "$SRC_REPO/upstream/deepseek-harness" ]]; then
  echo "ERROR: harness missing at $SRC_REPO (run scripts/ci-fetch-workbench.sh + ci-build-workbench.sh)" >&2
  exit 1
fi

# pnpm stores packages as a symlink farm. Creating those symlinks on Windows
# GitHub runners fails without Developer Mode / SeCreateSymbolicLinkPrivilege.
# Dereference into real files when staging on Windows (or when forced).
is_windows=0
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) is_windows=1 ;;
esac
[[ "${OS:-}" == "Windows_NT" ]] && is_windows=1
case "${MSYSTEM:-}" in MINGW*|MSYS*) is_windows=1 ;; esac
[[ "${FDEX_DEREF_NODE_MODULES:-}" == "1" ]] && is_windows=1
# Always deref when explicitly staging for Windows (CI matrix target), even if uname is odd.
[[ "$TARGET" == "win" ]] && is_windows=1

# Copy a symlink-heavy tree via tar. On Windows, -h dumps file contents instead of links.
tar_copy_modules() {
  local src_dir="$1"
  local dest_dir="$2"
  mkdir -p "$dest_dir"
  if [[ "$is_windows" -eq 1 ]]; then
    (cd "$src_dir" && tar cfh - .) | (cd "$dest_dir" && tar xf -)
  else
    (cd "$src_dir" && tar cf - .) | (cd "$dest_dir" && tar xf -)
  fi
}

rm -rf "$DEST"
mkdir -p "$DEST"

echo "[stage] copying repo (excluding harness node_modules first)..."
[[ "$is_windows" -eq 1 ]] && echo "[stage] Windows detected — dereferencing symlinks when copying node_modules"
for f in "$SRC_REPO"/* "$SRC_REPO"/.[!.]*; do
  base=$(basename "$f")
  [[ "$base" == "." || "$base" == ".." ]] && continue
  if [[ "$base" == "upstream" || "$base" == ".runtime" ]]; then
    continue
  fi
  if [[ -d "$f" ]]; then
    if [[ "$is_windows" -eq 1 ]]; then
      tar_copy_modules "$f" "$DEST/$base"
    else
      cp -a "$f" "$DEST/$base"
    fi
  elif [[ -f "$f" ]]; then
    cp -a "$f" "$DEST/$base"
  fi
done

mkdir -p "$DEST/upstream"
echo "[stage] copying deepseek-harness (skip root node_modules initially)..."
# Exclude EVERY node_modules tree here; nested package links are copied later via tar_copy_modules
# (with -h on Windows). A bare --exclude=./node_modules only skips the harness root and still
# ships package-level symlink farms that break Windows tar extract.
_harness_tar_flags=(cf -)
[[ "$is_windows" -eq 1 ]] && _harness_tar_flags=(cfh -)
(cd "$SRC_REPO/upstream/deepseek-harness" && tar "${_harness_tar_flags[@]}" \
  --exclude=node_modules \
  --exclude=./.git \
  --exclude=./coverage \
  --exclude='*.map' \
  .) | (mkdir -p "$DEST/upstream/deepseek-harness" && cd "$DEST/upstream/deepseek-harness" && tar xf -)

if [[ -d "$SRC_REPO/upstream/deepseek-harness/node_modules" ]]; then
  echo "[stage] copying root node_modules (please wait)..."
  tar_copy_modules \
    "$SRC_REPO/upstream/deepseek-harness/node_modules" \
    "$DEST/upstream/deepseek-harness/node_modules"
else
  echo "ERROR: node_modules missing — run ci-build-workbench.sh first" >&2
  exit 1
fi

echo "[stage] syncing nested node_modules dirs..."
H0="$SRC_REPO/upstream/deepseek-harness"
H="$DEST/upstream/deepseek-harness"
find "$H0" -type d -name node_modules ! -path '*/node_modules/*' ! -path "$H0/node_modules" -print0 |
while IFS= read -r -d '' d; do
  rel="${d#$H0/}"
  dest="$H/$rel"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    tar_copy_modules "$d" "$dest"
  fi
done

mkdir -p "$DEST/vendor"
if [[ -d "$VENDOR/dsh-openapi" ]]; then
  rm -rf "$DEST/vendor/dsh-openapi"
  if [[ "$is_windows" -eq 1 ]]; then
    tar_copy_modules "$VENDOR/dsh-openapi" "$DEST/vendor/dsh-openapi"
  else
    cp -a "$VENDOR/dsh-openapi" "$DEST/vendor/dsh-openapi"
  fi
fi
if [[ -d "$VENDOR/dsh-our-free-model" ]]; then
  rm -rf "$DEST/vendor/dsh-our-free-model"
  if [[ "$is_windows" -eq 1 ]]; then
    tar_copy_modules "$VENDOR/dsh-our-free-model" "$DEST/vendor/dsh-our-free-model"
  else
    cp -a "$VENDOR/dsh-our-free-model" "$DEST/vendor/dsh-our-free-model"
  fi
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
