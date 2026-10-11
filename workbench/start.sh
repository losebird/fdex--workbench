#!/usr/bin/env bash
# 便捷入口：从 workbench/ 目录启动
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export FDE_REPO_ROOT="$HERE"
exec bash "$HERE/../scripts/start-workbench.sh"
