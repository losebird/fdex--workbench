#!/usr/bin/env bash
# 首次：在 workbench/upstream/deepseek-harness 里装依赖并 build。
# 只需本机有 Node + npm（自带 npx）。不装全局 pnpm、不用 corepack。
# monorepo 仍须 pnpm 协议；本脚本用：npx --yes pnpm@11.7.0 …
# 用法（仓库根）：npm run setup:workbench
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WB="$ROOT/workbench"
H="$WB/upstream/deepseek-harness"
PNPM_VER="${FDEX_PNPM_VERSION:-11.7.0}"
# 国内默认镜像；可覆盖：export NPM_CONFIG_REGISTRY=https://registry.npmjs.org
REG="${NPM_CONFIG_REGISTRY:-${npm_config_registry:-https://registry.npmmirror.com}}"

if [[ ! -d "$H" ]]; then
  echo "找不到 $H — 确认已 clone 含 workbench/ 的仓库" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "需要 Node。请先安装 Node 24 LTS（https://nodejs.org/ 或 nvm install 24）。" >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
  echo "需要 npm/npx（随 Node 安装）。当前 PATH 里找不到。" >&2
  exit 1
fi

major=$(node -p "process.versions.node.split('.')[0]")
if [[ "$major" -lt 22 ]]; then
  echo "当前 Node $(node -v) 过旧，请装 Node 24（nvm install 24 && nvm use 24）" >&2
  exit 1
fi
if [[ "$major" -ge 26 ]]; then
  echo "提示：检测到 Node $(node -v)。学员包更稳的是 Node 24；若后面报错请 nvm use 24。" >&2
fi

# 让 npx 拉 pnpm、以及 pnpm 拉依赖都走同一镜像（可被环境变量覆盖）
export npm_config_registry="$REG"
export NPM_CONFIG_REGISTRY="$REG"
# pnpm 读这个；也传给子进程
export npm_config_registry="$REG"

run_pnpm() {
  # --yes：不交互确认下载 pnpm@版本
  npx --yes "pnpm@${PNPM_VER}" "$@"
}

echo "==> 使用 npx pnpm@${PNPM_VER}（无需全局安装 pnpm / corepack）"
echo "    registry: $REG"
echo "    Node: $(node -v)  npm: $(npm -v)"
echo ""

cd "$H"

echo "==> pnpm install @ $H"
run_pnpm install --registry="$REG"

echo "==> pnpm run build"
run_pnpm run build

echo ""
echo "完成。之后只需 Node，启动："
echo "  npm run start:workbench"
echo "浏览器将打开 http://127.0.0.1:3080 （可用 FDEX_PORT 改端口）"
echo ""
echo "若 npx 拉 pnpm 失败（@pnpm/exe / registry.npmjs.org）："
echo "  export NPM_CONFIG_REGISTRY=https://registry.npmmirror.com"
echo "  npm run setup:workbench"
