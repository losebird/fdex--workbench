#!/usr/bin/env bash
# 首次：在 workbench/upstream/deepseek-harness 里装依赖并 build。
# 说明：deepseek-harness 是 pnpm monorepo（有 pnpm-lock.yaml + link: overrides），
# 不能用 npm install 替代；本脚本用 corepack 拉 pnpm，你日常仍可用 npm。
# 用法（仓库根）：npm run setup:workbench
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WB="$ROOT/workbench"
H="$WB/upstream/deepseek-harness"

if [[ ! -d "$H" ]]; then
  echo "找不到 $H — 确认已 clone 含 workbench/ 的仓库" >&2
  exit 1
fi

# Node：尽量用 24（engines: ^22.19 || >=24）
if command -v node >/dev/null 2>&1; then
  major=$(node -p "process.versions.node.split('.')[0]")
  if [[ "$major" -lt 22 ]]; then
    echo "当前 Node $(node -v) 过旧，请装 Node 24（nvm install 24 && nvm use 24）" >&2
    exit 1
  fi
  if [[ "$major" -ge 26 ]]; then
    echo "提示：检测到 Node $(node -v)。学员包更稳的是 Node 24；若后面报错请 nvm use 24。" >&2
  fi
else
  echo "需要 Node。请先安装 Node 24。" >&2
  exit 1
fi

# pnpm via corepack（不改你的全局 npm 习惯）
export COREPACK_NPM_REGISTRY="${COREPACK_NPM_REGISTRY:-https://registry.npmmirror.com}"
if ! command -v corepack >/dev/null 2>&1; then
  echo "当前 Node 没有 corepack。请改用官方 Node 24 LTS（自带 corepack），或：npm i -g pnpm@11.7.0" >&2
  exit 1
fi
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@11.7.0 --activate

# 镜像（国内网络）
pnpm config set registry "${PNPM_REGISTRY:-https://registry.npmmirror.com}" >/dev/null 2>&1 || true

echo "==> pnpm install @ $H"
cd "$H"
pnpm install

echo "==> pnpm run build"
pnpm run build

echo ""
echo "完成。启动："
echo "  npm run start:workbench"
echo "或："
echo "  ./scripts/start-workbench.sh"
echo "浏览器将打开 http://127.0.0.1:3080 （可用 FDEX_PORT 改端口）"
