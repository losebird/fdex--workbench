#!/usr/bin/env bash
# FDE-X：本机起工作台并打开浏览器（无需 Electron 安装包）
# 用法：在已 build 过的工作台根目录旁放好本脚本，或：
#   FDE_REPO_ROOT=/path/to/FDEDeliveryWorkbench ./start.sh
# 仓库入口：npm run start:workbench
set -euo pipefail

HOST="${FDEX_HOST:-127.0.0.1}"
PORT="${FDEX_PORT:-3080}"
URL="http://${HOST}:${PORT}"

dump_recent_log() {
  local log="${1:-}"
  echo "" >&2
  echo "===== FDE-X 服务日志（最近 60 行）=====" >&2
  if [[ -n "$log" && -f "$log" ]]; then
    tail -n 60 "$log" >&2 || true
  else
    echo "(尚无日志文件${log:+: $log})" >&2
  fi
  echo "===== 完整日志: ${log:-?} =====" >&2
}

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

NODE_VER="$(node -v 2>/dev/null || echo '?')"
NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ "$NODE_MAJOR" -ge 26 ]]; then
  echo "警告：当前 Node ${NODE_VER}（major≥26）。学员包更稳的是 Node 24；若启动后秒退，请先：nvm install 24 && nvm use 24" >&2
fi

# 挂上 vendor 插件（与 Electron fixupDshHome 同逻辑；每次启动幂等）
# seed 失败不阻断启动（避免坏插件配置让整次 start 直接 abort）
SEED="$(cd "$(dirname "$0")" && pwd)/seed-plugins.sh"
if [[ -f "$SEED" ]]; then
  if ! FDE_REPO_ROOT="$ROOT" DSH_HOME="$DSH_HOME" bash "$SEED"; then
    echo "警告：seed-plugins 失败，继续启动（插件可能未挂上）" >&2
  fi
else
  echo "警告：找不到 seed-plugins.sh，跳过插件挂载" >&2
fi

# 释放旧端口（尽量温和）
if command -v lsof >/dev/null 2>&1; then
  old=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [[ -n "${old:-}" ]]; then
    echo "端口 $PORT 占用，结束 pid: $old"
    # shellcheck disable=SC2086
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
echo "Node ${NODE_VER} | 日志 $LOG"

# 清空本轮日志头，方便对照
{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') start pid-pending ====="
  echo "node=$NODE_VER entry=$ENTRY"
  echo "DSH_HOME=$DSH_HOME URL=$URL"
} >>"$LOG"

node "$ENTRY" web --no-open --host "$HOST" --port "$PORT" >>"$LOG" 2>&1 &
PID=$!
echo "===== node pid=$PID =====" >>"$LOG"

user_stop=0
trap 'user_stop=1; kill "$PID" 2>/dev/null || true' INT TERM

# 等 HTTP 就绪
ok=0
for _i in $(seq 1 90); do
  if curl -fsS -o /dev/null --max-time 2 "$URL" 2>/dev/null; then ok=1; break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "FDE-X 进程在就绪前已退出。浏览器若连不上，原因多半在下面：" >&2
    dump_recent_log "$LOG"
    if [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ "$NODE_MAJOR" -ge 26 ]]; then
      echo "提示：你在用 Node ${NODE_VER}，可先切到 24 再试。" >&2
    fi
    exit 1
  fi
  sleep 1
done
if [[ "$ok" != 1 ]]; then
  echo "等待 HTTP 就绪超时（${URL}）。最近日志：" >&2
  dump_recent_log "$LOG"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  exit 1
fi

if command -v open >/dev/null 2>&1; then
  open "$URL" || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
else
  echo "请手动打开 $URL"
fi

echo "已打开浏览器。终端保持运行；Ctrl+C 停止服务。"

# 子进程退出后务必打日志（以前 wait 返回就静默结束，浏览器只剩 ERR_CONNECTION_REFUSED）
set +e
wait "$PID"
status=$?
set -e

if [[ "$user_stop" == 1 ]]; then
  echo "已停止 FDE-X。"
  exit 0
fi

echo "FDE-X 服务已退出（exit=${status}）。若浏览器显示「连接被拒绝 / ERR_CONNECTION_REFUSED」，原因在下面日志：" >&2
dump_recent_log "$LOG"
if [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ "$NODE_MAJOR" -ge 26 ]]; then
  echo "提示：你在用 Node ${NODE_VER}，可先切到 24 再试：nvm install 24 && nvm use 24" >&2
fi
# exit 0 from node still means "not serving anymore" for our purposes
if [[ "$status" -eq 0 ]]; then
  exit 1
fi
exit "$status"
