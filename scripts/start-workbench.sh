#!/usr/bin/env bash
# FDE-X：本机起工作台并打开浏览器（无需 Electron 安装包）
# 用法：在已 build 过的工作台根目录旁放好本脚本，或：
#   FDE_REPO_ROOT=/path/to/FDEDeliveryWorkbench ./start.sh
set -euo pipefail

HOST="${FDEX_HOST:-127.0.0.1}"
PORT="${FDEX_PORT:-3080}"
URL="http://${HOST}:${PORT}"

# 工作台根：优先环境变量；否则猜常见布局（脚本旁 / 上级含 upstream/deepseek-harness）
resolve_root() {
  if [[ -n "${FDE_REPO_ROOT:-}" && -d "$FDE_REPO_ROOT/upstream/deepseek-harness" ]]; then
    echo "$FDE_REPO_ROOT"; return
  fi
  local here
  here="$(cd "$(dirname "$0")" && pwd)"
  for cand in \
    "$here" \
    "$here/.." \
    "$here/../workbench" \
    "$here/workbench" \
    "$here/../workbench-src" \
    "$here/workbench-src" \
    "$HOME/Documents/FDE资料/FDEDeliveryWorkbench" \
    "$HOME/Documents/FDE-X/FDEDeliveryWorkbench"
  do
    if [[ -d "$cand/upstream/deepseek-harness" ]]; then
      (cd "$cand" && pwd); return
    fi
  done
  echo "找不到工作台根目录（需要 upstream/deepseek-harness）。" >&2
  echo "请设置：export FDE_REPO_ROOT=/你的/FDEDeliveryWorkbench" >&2
  exit 1
}

ROOT="$(resolve_root)"
H="$ROOT/upstream/deepseek-harness"
export DSH_HOME="${DSH_HOME:-$ROOT/.runtime/dsh-home}"
export DSH_CLIENT_COMMIT_HASH="${DSH_CLIENT_COMMIT_HASH:-337cd32a63a7042ccfd2ade412619ee41441f4c1}"
export FDE_REPO_ROOT="$ROOT"
mkdir -p "$DSH_HOME"

# Node：优先已在 PATH；否则试 nvm 24
if ! command -v node >/dev/null 2>&1; then
  if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    nvm use 24 >/dev/null || nvm use default >/dev/null || true
  fi
fi
command -v node >/dev/null 2>&1 || { echo "需要 Node 24+（先装好再跑）" >&2; exit 1; }

# 释放旧 3080（尽量温和）
if command -v lsof >/dev/null 2>&1; then
  old=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [[ -n "${old:-}" ]]; then
    echo "端口 $PORT 占用，结束 pid: $old"
    kill $old 2>/dev/null || true
    sleep 1
  fi
fi

cd "$H"
# 入口：已 build 的 dsh
ENTRY=""
for c in \
  "apps/cli/lib/bin.js" \
  "node_modules/@deepseek-ai/dsh/lib/bin.js"
do
  [[ -f "$H/$c" ]] && ENTRY="$H/$c" && break
done
if [[ -z "$ENTRY" ]]; then
  echo "未找到 dsh 入口，请先在仓库根执行：npm run setup:workbench" >&2
  exit 1
fi

LOG="${FDEX_LOG:-$ROOT/.runtime/fde-x-web.log}"
mkdir -p "$(dirname "$LOG")"
echo "启动 FDE-X → $URL"
echo "DSH_HOME=$DSH_HOME"
echo "日志 $LOG"

node "$ENTRY" web --no-open --host "$HOST" --port "$PORT" >>"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT INT TERM

# 等 HTTP 就绪
ok=0
for i in $(seq 1 90); do
  if curl -fsS -o /dev/null --max-time 2 "$URL" 2>/dev/null; then ok=1; break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "进程已退出，看日志：$LOG" >&2
    exit 1
  fi
  sleep 1
done
[[ "$ok" == 1 ]] || { echo "等待超时，看日志：$LOG" >&2; exit 1; }

if command -v open >/dev/null 2>&1; then
  open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
else
  echo "请手动打开 $URL"
fi

echo "已打开浏览器。终端保持运行；Ctrl+C 停止服务。"
wait "$PID"
