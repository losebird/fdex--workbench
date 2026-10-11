# FDE-X 交付工作台

仓库：https://github.com/losebird/fdex--workbench

- **`workbench/`** — 可运行的 FDEDeliveryWorkbench 源码（DeepSeek Harness **0.1.1-rc.2** + FDE 插件，含侧栏遮罩修复）
- **`scripts/start-workbench.sh`** — 本机起 `dsh web` 并打开浏览器（无需 `.dmg`）
- Electron 安装包相关文件仍保留，但日常请直接跑源码

> 课程/实验材料再分发建议用私有仓库，见 [NOTICE.md](./NOTICE.md)。

## 你只需要 Node + npm

**不必安装全局 pnpm，也不必有 corepack。**  
Mac 上装好 [Node 24 LTS](https://nodejs.org/)（自带 `npm` / `npx`）即可。

`setup` 内部用一行：`npx --yes pnpm@11.7.0 …` 临时下载 pnpm 来装 monorepo；装完后 **启动只用 `node`**。

```bash
git clone https://github.com/losebird/fdex--workbench.git
cd fdex--workbench

# 强烈建议 Node 24（nvm install 24 && nvm use 24）
# 国内网络（推荐先设镜像，避免 npx 拉 @pnpm/exe 失败）：
export NPM_CONFIG_REGISTRY=https://registry.npmmirror.com

npm run setup:workbench   # 首次：npx pnpm install + build
npm run start:workbench   # 之后每次：起服务并打开浏览器
```

默认地址：`http://127.0.0.1:3080`  
改端口：`FDEX_PORT=3081 npm run start:workbench`  
`DSH_HOME` 默认在 `workbench/.runtime/dsh-home`，**不会动你全局其它 dsh 安装**。
`npm run start:workbench` 会自动把 `vendor/dsh-our-free-model` 挂进 `DSH_HOME`（幂等，无需 pnpm）。

**`dsh-openapi` 默认不自动挂载。** 它依赖 `@deepseek-ai/schemastery` 等 peer；直接拷进 `bundled-plugins` 会缺包、服务秒退。启动脚本若发现已挂过的坏 openapi，会自动卸掉以恢复启动。

可选安装 OpenAPI（会从 harness 链上 peer）：

```bash
SEED_OPENAPI=1 npm run start:workbench
# 或手动（在 harness 目录，保证解析到 peer）：
cd workbench/upstream/deepseek-harness
export DSH_HOME="$(cd ../.. && pwd)/.runtime/dsh-home"
# 先链 peer 再 add，或用 SEED_OPENAPI=1
node apps/cli/lib/bin.js plugin --profile web add "$(cd ../.. && pwd)/vendor/dsh-openapi"
```

若服务秒退且日志里有 `Cannot find package '@deepseek-ai/schemastery'`（旧版误 seed 了 openapi）：

```bash
cd fdex--workbench
git pull
DSH="$PWD/workbench/.runtime/dsh-home"
rm -rf "$DSH/bundled-plugins/dsh-openapi"
rm -f "$DSH/profiles/web/node_modules/dsh-openapi"
# 从 profiles/web/package.json 的 dependencies / dsh.profile.bundles 里删掉 dsh-openapi
# （或直接再跑一次 start：新脚本会自动 unseed）
npm run start:workbench
```

### 网络 / 镜像说明

若出现连不上 `registry.npmjs.org`、下载 `@pnpm/exe` 失败：

```bash
export NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
# 可选（部分环境还认这个）：
export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
npm run setup:workbench
```

脚本默认已用 `registry.npmmirror.com`；若你要官方源：

```bash
export NPM_CONFIG_REGISTRY=https://registry.npmjs.org
npm run setup:workbench
```

### 为什么不是「纯 npm install」？

`workbench/upstream/deepseek-harness` 是 **pnpm workspace**（`pnpm-lock.yaml`、`link:` overrides）。  
根目录 `npm install` 装的是 Electron 壳，**不会**装好工作台 monorepo。  
对 harness 目录直接 `npm install` 也装不全。  
所以首次必须走 `npm run setup:workbench`（底层仍是 pnpm，但经由 **npx**，不用你装）。

## 目录

```
workbench/                 # 工作台源码（git 可见）
  upstream/deepseek-harness/
  vendor/dsh-openapi/
  vendor/dsh-our-free-model/
  frontend/
  start.sh
scripts/
  setup-workbench.sh       # npm run setup:workbench（npx pnpm@11.7.0）
  start-workbench.sh       # npm run start:workbench（仅 node）
  seed-plugins.sh         # 挂 vendor/dsh-our-free-model 到 DSH_HOME
src/                       # Electron 壳（可选）
```

`node_modules`、`.runtime`、构建产物 **不进 git**。

## Electron 安装包（可选，已不推荐日常用）

体积大、未签名。若仍需要，见 [BUILD.md](./BUILD.md)。
