# FDE-X 交付工作台

仓库：https://github.com/losebird/fdex--workbench

- **`workbench/`** — 可运行的 FDEDeliveryWorkbench 源码（DeepSeek Harness **0.1.1-rc.2** + FDE 插件，含侧栏遮罩修复）
- **`scripts/start-workbench.sh`** — 本机起 `dsh web` 并打开浏览器（无需 `.dmg`）
- Electron 安装包相关文件仍保留，但日常开发请直接跑源码

> 课程/实验材料再分发建议用私有仓库，见 [NOTICE.md](./NOTICE.md)。

## 克隆后本机启动（推荐）

你平时用 **npm** 即可；工作台 monorepo 的**安装**一步必须走 pnpm（`packageManager: pnpm@11.7.0`），仓库根提供了 npm 包装脚本，内部用 corepack 拉 pnpm，**不必改掉你的 npm 习惯**。

```bash
git clone https://github.com/losebird/fdex--workbench.git
cd fdex--workbench

# 建议 Node 24（nvm install 24 && nvm use 24）
# 国内网络可先：
#   export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com

npm run setup:workbench   # 首次：pnpm install + build
npm run start:workbench   # 之后每次：起服务并打开浏览器
```

默认地址：`http://127.0.0.1:3080`  
改端口：`FDEX_PORT=3081 npm run start:workbench`  
`DSH_HOME` 默认在 `workbench/.runtime/dsh-home`，**不会动你全局其它 dsh 安装**。

等价命令：

```bash
./scripts/setup-workbench.sh
export FDE_REPO_ROOT="$PWD/workbench"
./scripts/start-workbench.sh
# 或：cd workbench && ./start.sh
```

更细说明见 [`workbench/README.md`](./workbench/README.md)。

### 为什么 setup 不是 `npm install`？

`workbench/upstream/deepseek-harness` 是 **pnpm workspace**（只有 `pnpm-lock.yaml`，还有 `link:` overrides）。  
对这个目录直接 `npm install` 装不全，容易缺 `tsx` 等工具。  
`npm run setup:workbench` = corepack 启用 pnpm 11.7.0 → `pnpm install` → `pnpm run build`。  
**启动阶段只用 `node`**，不再依赖 npm/pnpm。

## 目录

```
workbench/                 # 工作台源码（git 可见）
  upstream/deepseek-harness/
  vendor/dsh-openapi/
  vendor/dsh-our-free-model/
  frontend/
  start.sh
scripts/
  setup-workbench.sh       # npm run setup:workbench
  start-workbench.sh       # npm run start:workbench
src/                       # Electron 壳（可选）
vendor/                    # 安装器侧 vendor 副本
ci/build-desktop.yml       # 桌面安装包 workflow 模板
```

`node_modules`、`.runtime`、构建产物 **不进 git**。

## Electron 安装包（可选，已不推荐日常用）

体积大、未签名。若仍需要，见 [BUILD.md](./BUILD.md)。工作流模板在 `ci/build-desktop.yml`。
