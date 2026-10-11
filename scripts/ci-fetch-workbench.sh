#!/usr/bin/env bash
# Download / extract workbench source for CI (no giant node_modules in git).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${FDEX_SRC_REPO:-$ROOT/workbench-src}"

if [[ -d "$DEST/upstream/deepseek-harness" ]]; then
  echo "[ci-fetch] already present: $DEST"
  exit 0
fi

URL="${WORKBENCH_ASSET_URL:-}"
if [[ -z "$URL" && -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  TAG="${WORKBENCH_ASSET_TAG:-workbench-src-v0.1.0}"
  NAME="${WORKBENCH_ASSET_NAME:-workbench-src.tar.zst}"
  echo "[ci-fetch] resolving release asset $TAG / $NAME from $GITHUB_REPOSITORY"
  API="https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}"
  URL=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$API" \
    | python3 -c "import json,sys; n=sys.argv[1]; r=json.load(sys.stdin); print(next(a['url'] for a in r.get('assets',[]) if a['name']==n))" "$NAME")
  DOWNLOAD_ACCEPT="application/octet-stream"
fi

if [[ -z "${URL:-}" ]]; then
  echo "ERROR: set WORKBENCH_ASSET_URL or publish release asset (see BUILD.md)." >&2
  exit 1
fi

mkdir -p "$ROOT/staging/cache" "$DEST"
CACHE="$ROOT/staging/cache/workbench-src-download"
echo "[ci-fetch] downloading -> $CACHE"
HDR=(-L)
if [[ -n "${GITHUB_TOKEN:-}" && "$URL" == *api.github.com* ]]; then
  HDR+=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: ${DOWNLOAD_ACCEPT:-application/octet-stream}")
fi
curl -f "${HDR[@]}" -o "$CACHE" "$URL"

echo "[ci-fetch] extracting to $DEST"
case "$CACHE" in
  *.zst|*)
    if file "$CACHE" | grep -qi 'zstandard'; then
      zstd -dc "$CACHE" | tar -xf - -C "$DEST"
    elif file "$CACHE" | grep -qi 'gzip'; then
      tar -xzf "$CACHE" -C "$DEST"
    else
      # try zstd then gzip
      if zstd -dc "$CACHE" 2>/dev/null | tar -xf - -C "$DEST" 2>/dev/null; then
        :
      else
        tar -xzf "$CACHE" -C "$DEST"
      fi
    fi
    ;;
esac

# If tarball had a single top-level folder, flatten
if [[ ! -d "$DEST/upstream/deepseek-harness" ]]; then
  inner=$(find "$DEST" -maxdepth 2 -type d -name deepseek-harness | head -1 || true)
  if [[ -n "$inner" ]]; then
    base=$(dirname "$(dirname "$inner")")
    if [[ "$base" != "$DEST" ]]; then
      tmp=$(mktemp -d)
      mv "$base"/* "$tmp"/
      rm -rf "$DEST"
      mkdir -p "$DEST"
      mv "$tmp"/* "$DEST"/
      rm -rf "$tmp"
    fi
  fi
fi

if [[ ! -d "$DEST/upstream/deepseek-harness" ]]; then
  echo "ERROR: harness missing after extract at $DEST" >&2
  exit 1
fi
echo "[ci-fetch] OK"
