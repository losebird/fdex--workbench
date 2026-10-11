#!/usr/bin/env bash
# Download official Node 24 binary into staging/node/<platform>/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
NODE_VER="${NODE_VER:-24.10.0}"
ACTIVE="${2:-}"   # if "active", also mirror into staging/node for electron-builder
mkdir -p "$ROOT/staging/cache"

usage() {
  echo "Usage: $0 <linux-x64|win-x64|darwin-x64|darwin-arm64> [active]"
  exit 1
}
[[ -n "$PLATFORM" ]] || usage

case "$PLATFORM" in
  linux-x64)   FILE="node-v${NODE_VER}-linux-x64.tar.gz";   KIND=tar ;;
  darwin-x64)  FILE="node-v${NODE_VER}-darwin-x64.tar.gz";  KIND=tar ;;
  darwin-arm64) FILE="node-v${NODE_VER}-darwin-arm64.tar.gz"; KIND=tar ;;
  win-x64)     FILE="node-v${NODE_VER}-win-x64.zip";       KIND=zip ;;
  *) usage ;;
esac

URL="https://nodejs.org/dist/v${NODE_VER}/${FILE}"
CACHE="$ROOT/staging/cache/${FILE}"
OUT="$ROOT/staging/node-runtimes/${PLATFORM}"

echo "[fetch-node] $URL -> $OUT"
if [[ ! -f "$CACHE" ]]; then
  curl -fL --retry 3 -o "$CACHE.partial" "$URL"
  mv "$CACHE.partial" "$CACHE"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

if [[ "$KIND" == tar ]]; then
  TMP=$(mktemp -d)
  tar -xzf "$CACHE" -C "$TMP"
  INNER=$(echo "$TMP"/node-v*)
  mkdir -p "$OUT/bin"
  cp -a "$INNER/bin/node" "$OUT/bin/node"
  cp -a "$INNER/LICENSE" "$OUT/LICENSE" 2>/dev/null || true
  rm -rf "$TMP"
  chmod +x "$OUT/bin/node"
  "$OUT/bin/node" -v
else
  TMP=$(mktemp -d)
  unzip -q "$CACHE" -d "$TMP"
  INNER=$(echo "$TMP"/node-v*)
  cp -a "$INNER/node.exe" "$OUT/node.exe"
  cp -a "$INNER/LICENSE" "$OUT/LICENSE" 2>/dev/null || true
  rm -rf "$TMP"
  echo "windows node staged: $OUT/node.exe"
fi

# Mirror into staging/node for electron-builder extraResources
if [[ "$ACTIVE" == "active" ]]; then
  # default: always activate the fetched platform (single-target builds)
  rm -rf "$ROOT/staging/node"
  mkdir -p "$ROOT/staging/node"
  cp -a "$OUT"/. "$ROOT/staging/node/"
  echo "[fetch-node] activated staging/node from $PLATFORM"
fi

echo "[fetch-node] done"
